import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct PhotosClutterSmoke {
    static func main() async throws {
        guard ScanScope.isFixture else { fatalError("Photos smoke tests require fixture mode and never request real Photos authorization.") }
        func item(_ id: String, _ digest: UInt8, _ hash: UInt64?, width: Int = 900, height: Int = 800) -> LocalPhotoItem {
            LocalPhotoItem(id: id, filename: id + ".png", creationDate: nil, modificationDate: nil,
                width: width, height: height, bytes: 10, digest: Data(SHA256.hash(data: Data([digest]))), visualHash: hash)
        }
        let increasing = try gradientImage(decreasing: false)
        let decreasing = try gradientImage(decreasing: true)
        let increaseHash = PhotoClutterGrouping.visualHash(increasing)
        let decreaseHash = PhotoClutterGrouping.visualHash(decreasing)
        precondition(increaseHash != nil && decreaseHash != nil)
        precondition((increaseHash! ^ decreaseHash!).nonzeroBitCount >= 60, "dHash must distinguish opposing gradients")
        precondition(PhotoClutterGrouping.visualHash(Data("not an image".utf8)) == nil)
        let items = [item("a", 1, 0), item("b", 1, 0), item("c", 2, 0xF0), item("d", 3, 0xF1),
                     item("e", 4, UInt64.max), item("f", 5, 0xF1, width: 800, height: 900), item("g", 6, nil)]
        let groups = PhotoClutterGrouping.groups(items)
        precondition(groups.count == 2)
        precondition(groups[0].kind == .exact && Set(groups[0].items.map(\.id)) == ["a", "b"])
        precondition(groups[1].kind == .similar && Set(groups[1].items.map(\.id)) == ["c", "d"])
        precondition(Set(groups.flatMap { $0.items.map(\.id) }).count == groups.flatMap(\.items).count, "Groups must not overlap")
        try PhotoClutterGrouping.validateSelection(["a", "c"], groups: groups)
        do { try PhotoClutterGrouping.validateSelection(["a", "b"], groups: groups); fatalError("Must preserve a copy") }
        catch PhotosClutterError.preserveOriginal {}
        do { try PhotoClutterGrouping.validateSelection(["unknown"], groups: groups); fatalError("Unknown identifier must fail") }
        catch PhotosClutterError.changed {}
        do { try PhotoClutterGrouping.validateSelection([], groups: groups); fatalError("Empty selection must fail") }
        catch PhotosClutterError.emptySelection {}
        let engine = PhotosClutterEngine()
        do { _ = try await engine.analyze(); fatalError("Fixture must not access real Photos") }
        catch PhotosClutterError.fixture {}
        let snapshot = PhotosClutterSnapshot(groups: groups, libraryCount: 7, examinedCount: 7, bytesRead: 70, unavailableCount: 0, omittedCount: 0, notes: [])
        do { _ = try await engine.delete(snapshot, selectedIDs: ["a"]); fatalError("Fixture deletion must be disabled") }
        catch PhotosClutterError.fixture {}
        print("OK: Photos fixture refusal, real PNG dHash, SHA256 duplicate groups, similarity/aspect ratio, non-overlap and preserved copy selection")
    }

    private static func gradientImage(decreasing: Bool) throws -> Data {
        let width = 90, height = 80
        var bytes = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height { for column in 0..<width {
            let value = UInt8(column * 255 / (width - 1)); bytes[row * width + column] = decreasing ? 255 - value : value
        } }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
