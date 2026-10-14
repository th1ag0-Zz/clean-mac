import Foundation
import CoreGraphics

@main
struct SpaceLensSmoke {
    static func main() async throws {
        let snapshot = try await SpaceLensEngine().scan()
        guard let downloads = snapshot.roots.first(where: { $0.name == "Downloads" }),
              let archive = downloads.children.first(where: { $0.name == "Archive" }),
              let nested = archive.children.first(where: { $0.name == "nested.dmg" }) else {
            fatalError("A árvore deve expor arquivos dentro das subpastas de Downloads")
        }
        precondition(nested.logicalBytes > 0)
        precondition(archive.logicalBytes == nested.logicalBytes)
        precondition(downloads.logicalBytes >= archive.logicalBytes)
        precondition(archive.fileCount == 1)
        precondition(!snapshot.truncated)
        let weights = [60.0, 25.0, 10.0, 5.0]
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 400)
        let frames = SpaceTreemapLayout.frames(weights: weights, in: bounds)
        for index in weights.indices {
            let fraction = frames[index].width * frames[index].height / (bounds.width * bounds.height)
            precondition(abs(fraction - weights[index] / 100) < 0.000_001)
            precondition(bounds.contains(frames[index]))
            for other in weights.indices where other > index {
                let intersection = frames[index].intersection(frames[other])
                precondition(intersection.isNull || intersection.width * intersection.height == 0)
            }
        }
        let custom = try await SpaceLensEngine().scan(root: archive.url)
        precondition(custom.roots.count == 1 && custom.roots[0].logicalBytes == archive.logicalBytes)
        print("SpaceLensSmoke: OK")
    }
}
