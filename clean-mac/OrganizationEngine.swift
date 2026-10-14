import CryptoKit
import CoreGraphics
import Darwin
import Foundation
import ImageIO

enum OrganizationError: LocalizedError {
    case cannotOpenHome

    var errorDescription: String? { "Não foi possível acessar a pasta pessoal." }
}

struct OrganizedFile: Identifiable, Sendable {
    let url: URL
    let relativePath: String
    let logicalBytes: UInt64
    let modifiedAt: Date
    let identity: PersonalFileIdentity

    var id: String { relativePath }
    var selection: PersonalFileSelection { PersonalFileSelection(url: url, logicalBytes: logicalBytes, identity: identity) }
}

struct DuplicateGroup: Identifiable, Sendable {
    let digest: String
    let files: [OrganizedFile]

    var id: String { digest }
    var possibleSavings: UInt64 { UInt64(files.count - 1) * files[0].logicalBytes }
}

struct FolderUsage: Identifiable, Sendable {
    let name: String
    let logicalBytes: UInt64
    let fileCount: Int

    var id: String { name }
}

struct SimilarImagePair: Identifiable, Sendable {
    let first: OrganizedFile
    let second: OrganizedFile
    let distance: Int

    var id: String { first.relativePath + "|" + second.relativePath }
}

struct OrganizationSnapshot: Sendable {
    let downloads: [OrganizedFile]
    let oldFiles: [OrganizedFile]
    let duplicateGroups: [DuplicateGroup]
    let similarImages: [SimilarImagePair]
    let folders: [FolderUsage]
    let scannedFiles: Int
    let inaccessibleLocations: Int
    let skippedImages: Int
}

actor OrganizationEngine {
    private static let folders = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"]
    private static let oldAge: TimeInterval = 365 * 24 * 60 * 60
    private static let minimumDuplicateBytes: UInt64 = 1_024
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp"]
    private static let maximumImages = 500
    private static let maximumImageBytes: UInt64 = 40 * 1_024 * 1_024

    func scan(now: Date = .now) throws -> OrganizationSnapshot {
        let home = try ScanScope.homeDirectory()
        var homeInfo = stat()
        guard lstat(home.path, &homeInfo) == 0, homeInfo.st_mode & S_IFMT == S_IFDIR else {
            throw OrganizationError.cannotOpenHome
        }

        var oldFiles: [OrganizedFile] = []
        var downloads: [OrganizedFile] = []
        var bySize: [UInt64: [OrganizedFile]] = [:]
        var imageCandidates: [OrganizedFile] = []
        var skippedImages = 0
        var folders: [FolderUsage] = []
        var scannedFiles = 0
        var inaccessibleLocations = 0
        let manager = FileManager.default

        for name in Self.folders {
            try Task.checkCancellation()
            let folder = home.appendingPathComponent(name, isDirectory: true)
            var folderInfo = stat()
            guard lstat(folder.path, &folderInfo) == 0 else {
                if errno != ENOENT { inaccessibleLocations += 1 }
                continue
            }
            guard folderInfo.st_mode & S_IFMT == S_IFDIR, folderInfo.st_dev == homeInfo.st_dev else { continue }
            guard (try? PersonalFileActions.validateLocation(folder, home: home)) != nil else { continue }

            var folderBytes: UInt64 = 0
            var folderFiles = 0
            guard let entries = manager.enumerator(at: folder,
                                                   includingPropertiesForKeys: nil,
                                                   options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                   errorHandler: { _, _ in
                                                       inaccessibleLocations += 1
                                                       return true
                                                   }) else {
                inaccessibleLocations += 1
                continue
            }
            for case let url as URL in entries {
                try Task.checkCancellation()
                var info = stat()
                guard (try? PersonalFileActions.validateLocation(url, home: home)) != nil else {
                    entries.skipDescendants()
                    continue
                }
                guard lstat(url.path, &info) == 0 else {
                    inaccessibleLocations += 1
                    continue
                }
                guard info.st_dev == homeInfo.st_dev else {
                    entries.skipDescendants()
                    continue
                }
                guard info.st_mode & S_IFMT == S_IFREG else {
                    if info.st_mode & S_IFMT != S_IFDIR { entries.skipDescendants() }
                    continue
                }
                guard info.st_size >= 0 else { continue }

                let size = UInt64(info.st_size)
                let file = OrganizedFile(url: url,
                                         relativePath: String(url.path.dropFirst(home.path.count + 1)),
                                         logicalBytes: size,
                                         modifiedAt: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)),
                                         identity: PersonalFileIdentity(info))
                scannedFiles += 1
                if name == "Downloads" { downloads.append(file) }
                folderFiles += 1
                let sum = folderBytes.addingReportingOverflow(size)
                folderBytes = sum.overflow ? UInt64.max : sum.partialValue
                if now.timeIntervalSince(file.modifiedAt) >= Self.oldAge { oldFiles.append(file) }
                if size >= Self.minimumDuplicateBytes, info.st_nlink == 1 {
                    bySize[size, default: []].append(file)
                }
                if Self.imageExtensions.contains(url.pathExtension.lowercased()) {
                    if size > 0, size <= Self.maximumImageBytes, imageCandidates.count < Self.maximumImages {
                        imageCandidates.append(file)
                    } else {
                        skippedImages += 1
                    }
                }
            }
            folders.append(FolderUsage(name: name, logicalBytes: folderBytes, fileCount: folderFiles))
        }

        var duplicateGroups: [DuplicateGroup] = []
        for (size, candidates) in bySize where candidates.count > 1 {
            try Task.checkCancellation()
            var byDigest: [String: [OrganizedFile]] = [:]
            for file in candidates {
                try Task.checkCancellation()
                do {
                    let digest = try hash(file.url, expectedSize: size)
                    byDigest[digest, default: []].append(file)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    inaccessibleLocations += 1
                }
            }
            for (digest, files) in byDigest where files.count > 1 {
                duplicateGroups.append(DuplicateGroup(digest: digest,
                                                       files: files.sorted { $0.relativePath < $1.relativePath }))
            }
        }
        oldFiles.sort { $0.modifiedAt < $1.modifiedAt }
        downloads.sort {
            $0.logicalBytes == $1.logicalBytes
                ? $0.relativePath < $1.relativePath
                : $0.logicalBytes > $1.logicalBytes
        }
        duplicateGroups.sort { $0.possibleSavings > $1.possibleSavings }
        var fingerprints: [(OrganizedFile, UInt64, Double)] = []
        for file in imageCandidates {
            try Task.checkCancellation()
            if let fingerprint = imageFingerprint(file.url) {
                fingerprints.append((file, fingerprint.hash, fingerprint.aspectRatio))
            } else {
                skippedImages += 1
            }
        }
        var similarImages: [SimilarImagePair] = []
        for firstIndex in fingerprints.indices {
            try Task.checkCancellation()
            for secondIndex in fingerprints.indices where secondIndex > firstIndex {
                let first = fingerprints[firstIndex]
                let second = fingerprints[secondIndex]
                guard abs(first.2 - second.2) <= 0.10 else { continue }
                let distance = (first.1 ^ second.1).nonzeroBitCount
                if distance <= 5 {
                    similarImages.append(SimilarImagePair(first: first.0, second: second.0,
                                                          distance: distance))
                }
            }
        }
        similarImages.sort { $0.distance == $1.distance
            ? $0.first.relativePath < $1.first.relativePath : $0.distance < $1.distance }
        folders.sort { $0.logicalBytes > $1.logicalBytes }
        return OrganizationSnapshot(downloads: downloads, oldFiles: oldFiles, duplicateGroups: duplicateGroups,
                                    similarImages: similarImages, folders: folders,
                                    scannedFiles: scannedFiles, inaccessibleLocations: inaccessibleLocations,
                                    skippedImages: skippedImages)
    }

    func moveToTrash(_ files: [OrganizedFile], duplicateGroups: [DuplicateGroup]) throws -> PersonalFileRemovalReport {
        try PersonalFileActions.moveToTrash(files.map(\.selection), duplicates: duplicateGroups.map {
            PersonalDuplicateConstraint(digest: $0.digest, files: $0.files.map(\.selection))
        })
    }

    private func hash(_ url: URL, expectedSize: UInt64) throws -> String {
        var before = stat()
        guard lstat(url.path, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_nlink == 1, before.st_size >= 0, UInt64(before.st_size) == expectedSize else {
            throw CocoaError(.fileReadUnknown)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let data = try handle.read(upToCount: 1_024 * 1_024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        var after = stat()
        guard lstat(url.path, &after) == 0,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
            throw CocoaError(.fileReadUnknown)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func imageFingerprint(_ url: URL) -> (hash: UInt64, aspectRatio: Double)? {
        var before = stat()
        guard lstat(url.path, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_nlink == 1 else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 128
              ] as CFDictionary), image.width >= 32, image.height >= 32 else { return nil }

        var pixels = [UInt8](repeating: 0, count: 9 * 8)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 9, height: 8,
                                          bitsPerComponent: 8, bytesPerRow: 9,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: 9, height: 8))
            return true
        }
        guard drawn else { return nil }
        var after = stat()
        guard lstat(url.path, &after) == 0,
              before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { return nil }

        var hash: UInt64 = 0
        for y in 0..<8 {
            for x in 0..<8 {
                if pixels[y * 9 + x] > pixels[y * 9 + x + 1] {
                    hash |= 1 << UInt64(y * 8 + x)
                }
            }
        }
        guard hash != 0, hash != UInt64.max else { return nil }
        return (hash, Double(image.width) / Double(image.height))
    }
}
