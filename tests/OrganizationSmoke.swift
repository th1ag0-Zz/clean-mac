import CoreGraphics
import Foundation
import ImageIO

@main
struct OrganizationSmoke {
    static func main() async throws {
        let home = try ScanScope.homeDirectory()
        let root = home.appendingPathComponent("Documents/organization-smoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let payload = Data(repeating: 0x5A, count: 2_048)
        let first = root.appendingPathComponent("first.bin")
        let second = root.appendingPathComponent("second.bin")
        let different = root.appendingPathComponent("different.bin")
        try payload.write(to: first)
        try payload.write(to: second)
        try Data(repeating: 0x41, count: 2_048).write(to: different)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -400 * 86_400)],
                                              ofItemAtPath: first.path)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.bin"),
                                                   withDestinationURL: first)

        let context = CGContext(data: nil, width: 90, height: 80, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<80 {
            for x in 0..<90 {
                let shade = CGFloat((x * 13 + y * 7) % 256) / 255
                context.setFillColor(red: shade, green: shade, blue: shade, alpha: 1)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let image = context.makeImage()!
        let imageA = root.appendingPathComponent("image-a.png")
        let imageB = root.appendingPathComponent("image-b.jpg")
        for url in [imageA, imageB] {
            let type = url.pathExtension == "jpg" ? "public.jpeg" : "public.png"
            let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, image, [
                kCGImageDestinationLossyCompressionQuality: 0.9
            ] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        }

        let result = try await OrganizationEngine().scan()
        let matching = result.duplicateGroups.first {
            Set($0.files.map(\.url)) == Set([first, second])
        }
        guard matching != nil,
              !result.duplicateGroups.contains(where: { $0.files.contains(where: { $0.url == different }) }),
              result.oldFiles.contains(where: { $0.url == first }),
              !result.oldFiles.contains(where: { $0.url == second }),
              !result.oldFiles.contains(where: { $0.url.lastPathComponent == "link.bin" }),
              result.similarImages.contains(where: {
                  Set([$0.first.url, $0.second.url]) == Set([imageA, imageB])
              }),
              result.folders.contains(where: { $0.name == "Documents" && $0.logicalBytes >= 6_144 }) else {
            throw NSError(domain: "OrganizationSmoke", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Resultado inesperado da organização"])
        }
        precondition(result.downloads.contains(where: { $0.relativePath == "Downloads/Archive/nested.dmg" }))
        print("OK: duplicados exatos, imagens semelhantes, data, links e espaço por pasta")
    }
}
