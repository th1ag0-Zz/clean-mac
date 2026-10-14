import AppKit
import CryptoKit
import Foundation
import ImageIO
import Photos

struct LocalPhotoItem: Identifiable, Sendable {
    let id: String
    let filename: String
    let creationDate: Date?
    let modificationDate: Date?
    let width: Int
    let height: Int
    let bytes: Int
    let digest: Data
    let visualHash: UInt64?
}

struct LocalPhotoGroup: Identifiable, Sendable {
    enum Kind: String, Sendable { case exact = "Duplicatas exatas", similar = "Fotos semelhantes" }
    let id: String
    let kind: Kind
    let items: [LocalPhotoItem]
}

struct PhotosClutterSnapshot: Sendable {
    let groups: [LocalPhotoGroup]
    let libraryCount: Int
    let examinedCount: Int
    let bytesRead: Int
    let unavailableCount: Int
    let omittedCount: Int
    let notes: [String]
}

enum PhotosClutterError: LocalizedError {
    case fixture, denied, changed, preserveOriginal, emptySelection
    var errorDescription: String? {
        switch self {
        case .fixture: "A fototeca real fica desativada na fixture de teste."
        case .denied: "Autorize o acesso à fototeca em Ajustes do Sistema → Privacidade e Segurança → Fotos."
        case .changed: "Uma foto mudou ou deixou de estar disponível desde a análise. Analise novamente antes de remover."
        case .preserveOriginal: "Mantenha pelo menos uma foto de cada grupo."
        case .emptySelection: "Selecione fotos de um grupo antes de remover."
        }
    }
}

/// Pure grouping logic is also used by fixture tests, without touching Photos.
enum PhotoClutterGrouping {
    static func groups(_ items: [LocalPhotoItem]) -> [LocalPhotoGroup] {
        let exact = Dictionary(grouping: items, by: \.digest).values.filter { $0.count > 1 }
            .map { $0.sorted { $0.id < $1.id } }.sorted { $0[0].id < $1[0].id }
        var result = exact.map { LocalPhotoGroup(id: "exact-" + $0[0].id, kind: .exact, items: $0) }
        let exactIDs = Set(exact.flatMap { $0.map(\.id) })
        var remaining = items.filter { !exactIDs.contains($0.id) && $0.visualHash != nil }.sorted { $0.id < $1.id }
        while !remaining.isEmpty {
            let anchor = remaining.removeFirst()
            guard let hash = anchor.visualHash else { continue }
            let matches = remaining.filter { photo in
                guard let value = photo.visualHash else { return false }
                let a = Double(anchor.width) / Double(max(1, anchor.height))
                let b = Double(photo.width) / Double(max(1, photo.height))
                return abs(a - b) < 0.12 && (hash ^ value).nonzeroBitCount <= 6
            }
            if !matches.isEmpty {
                let IDs = Set(matches.map(\.id)); remaining.removeAll { IDs.contains($0.id) }
                result.append(LocalPhotoGroup(id: "similar-" + anchor.id, kind: .similar, items: [anchor] + matches))
            }
        }
        return result
    }

    static func validateSelection(_ selected: Set<String>, groups: [LocalPhotoGroup]) throws {
        guard !selected.isEmpty else { throw PhotosClutterError.emptySelection }
        guard selected.isSubset(of: Set(groups.flatMap { $0.items.map(\.id) })) else { throw PhotosClutterError.changed }
        for group in groups where group.items.allSatisfy({ selected.contains($0.id) }) { throw PhotosClutterError.preserveOriginal }
    }

    static func visualHash(_ data: Data) -> UInt64? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 64] as CFDictionary) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 9 * 8)
        return pixels.withUnsafeMutableBytes { buffer -> UInt64? in
            guard let context = CGContext(data: buffer.baseAddress, width: 9, height: 8, bitsPerComponent: 8,
                                          bytesPerRow: 9, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 9, height: 8))
            guard let values = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            var hash: UInt64 = 0
            for row in 0..<8 { for column in 0..<8 {
                if values[row * 9 + column] > values[row * 9 + column + 1] { hash |= UInt64(1) << UInt64(row * 8 + column) }
            } }
            return hash
        }
    }
}

private struct LocalPhotoRead: Sendable {
    let data: Data?
    let bytesRead: Int
    let error: String?
}

/// Photos calls callbacks on its own queues. One locked continuation owns every
/// request, including cancellation, size overflow and timeout paths.
private final class LocalPhotoReadRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<LocalPhotoRead, Never>?
    private var buffer = Data()
    private var bytesRead = 0
    private var finished = false
    private var requestID: PHAssetResourceDataRequestID?
    private let maximum: Int
    init(maximum: Int) { self.maximum = maximum }
    func begin(_ value: CheckedContinuation<LocalPhotoRead, Never>) {
        lock.lock()
        if finished { lock.unlock(); value.resume(returning: LocalPhotoRead(data: nil, bytesRead: 0, error: "Cancelado.")); return }
        continuation = value; lock.unlock()
    }
    func install(_ id: PHAssetResourceDataRequestID) {
        lock.lock(); requestID = id; let cancel = finished; lock.unlock()
        if cancel { PHAssetResourceManager.default().cancelDataRequest(id) }
    }
    func append(_ data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        let exceeds = data.count > maximum - buffer.count
        bytesRead += min(data.count, max(0, maximum - bytesRead))
        if !exceeds { buffer.append(data) }
        lock.unlock()
        if exceeds { finish(error: "Recurso maior que o limite por foto.", cancel: true) }
    }
    func finish(error: String?, cancel: Bool = false) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let value = LocalPhotoRead(data: error == nil ? buffer : nil, bytesRead: bytesRead, error: error)
        buffer = Data()
        let callback = continuation; continuation = nil; let id = requestID
        lock.unlock()
        if cancel, let id { PHAssetResourceManager.default().cancelDataRequest(id) }
        callback?.resume(returning: value)
    }
}

actor PhotosClutterEngine {
    func analyze() async throws -> PhotosClutterSnapshot {
        guard !ScanScope.isFixture else { throw PhotosClutterError.fixture }
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        guard status == .authorized || status == .limited else { throw PhotosClutterError.denied }
        let options = PHFetchOptions(); options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        let maximumAssets = 300, maximumBytes = 256 * 1_024 * 1_024, perPhotoBytes = 16 * 1_024 * 1_024
        var items: [LocalPhotoItem] = []
        var bytesRead = 0, unavailable = 0, attempted = 0
        var undecodable = 0
        var notes: [String] = []
        for index in 0..<min(maximumAssets, assets.count) {
            try Task.checkCancellation()
            guard bytesRead < maximumBytes else { break }
            let asset = assets.object(at: index); attempted += 1
            let resources = PHAssetResource.assetResources(for: asset)
            guard let resource = resources.first(where: { $0.type == .photo }) ?? resources.first(where: { $0.type == .fullSizePhoto }) else { unavailable += 1; continue }
            let read = await readLocal(resource, maximum: min(perPhotoBytes, maximumBytes - bytesRead))
            bytesRead += read.bytesRead
            let filename: String
            if #available(macOS 27, *) { filename = resource.filename ?? "Foto sem nome" }
            else { filename = resource.originalFilename }
            guard let data = read.data, !data.isEmpty else {
                unavailable += 1
                if notes.count < 8 { notes.append("\(filename): \(read.error ?? "recurso indisponível localmente")") }
                continue
            }
            let visualHash = PhotoClutterGrouping.visualHash(data)
            if visualHash == nil { undecodable += 1 }
            items.append(LocalPhotoItem(id: asset.localIdentifier, filename: filename,
                creationDate: asset.creationDate, modificationDate: asset.modificationDate, width: asset.pixelWidth,
                height: asset.pixelHeight, bytes: data.count, digest: Data(SHA256.hash(data: data)),
                visualHash: visualHash))
        }
        try Task.checkCancellation()
        if status == .limited { notes.append("Acesso limitado: somente as fotos autorizadas pelo macOS são consideradas.") }
        if undecodable > 0 { notes.append("\(undecodable) imagem(ns) sem miniatura decodificável foram comparadas somente por bytes, sem teste de semelhança.") }
        return PhotosClutterSnapshot(groups: PhotoClutterGrouping.groups(items), libraryCount: assets.count,
            examinedCount: items.count, bytesRead: bytesRead, unavailableCount: unavailable,
            omittedCount: max(0, assets.count - attempted), notes: notes)
    }

    func delete(_ snapshot: PhotosClutterSnapshot, selectedIDs: Set<String>) async throws -> Int {
        guard !ScanScope.isFixture else { throw PhotosClutterError.fixture }
        try PhotoClutterGrouping.validateSelection(selectedIDs, groups: snapshot.groups)
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { throw PhotosClutterError.denied }
        // Revalidate the retained items too: an original may have been removed in
        // Photos after this review, and must not silently become the last copy.
        let items = snapshot.groups.filter { group in group.items.contains { selectedIDs.contains($0.id) } }.flatMap(\.items)
        let expectedIDs = Set(items.map(\.id))
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: Array(expectedIDs), options: nil)
        guard fetched.count == expectedIDs.count else { throw PhotosClutterError.changed }
        var assets: [PHAsset] = []
        for index in 0..<fetched.count {
            let asset = fetched.object(at: index)
            guard let expected = items.first(where: { $0.id == asset.localIdentifier }),
                  expected.modificationDate == asset.modificationDate,
                  expected.width == asset.pixelWidth, expected.height == asset.pixelHeight else { throw PhotosClutterError.changed }
            if selectedIDs.contains(asset.localIdentifier) { assets.append(asset) }
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
        return selectedIDs.count
    }

    private func readLocal(_ resource: PHAssetResource, maximum: Int) async -> LocalPhotoRead {
        let request = LocalPhotoReadRequest(maximum: maximum)
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                request.begin(continuation)
                let options = PHAssetResourceRequestOptions(); options.isNetworkAccessAllowed = false
                let id = PHAssetResourceManager.default().requestData(for: resource, options: options, dataReceivedHandler: { data in
                    request.append(data)
                }, completionHandler: { error in request.finish(error: error?.localizedDescription) })
                request.install(id)
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 12) {
                    request.finish(error: "Tempo limite de leitura local excedido.", cancel: true)
                }
            }
        }, onCancel: { request.finish(error: "Análise cancelada.", cancel: true) })
    }
}
