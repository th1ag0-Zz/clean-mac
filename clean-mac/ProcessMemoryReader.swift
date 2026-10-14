import Foundation

enum ProcessMemoryReader {
    /// RSS em bytes por PID. `ps` informa RSS em blocos de 1024 bytes no macOS.
    static func snapshot() -> [Int32: UInt64]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,rss="]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            output.fileHandleForWriting.closeFile()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return parse(String(decoding: data, as: UTF8.self))
        } catch {
            return nil
        }
    }

    static func parse(_ output: String) -> [Int32: UInt64] {
        var memory: [Int32: UInt64] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2,
                  let pid = Int32(fields[0]), pid > 0,
                  let kib = UInt64(fields[1]),
                  kib <= UInt64.max / 1024 else { continue }
            memory[pid] = kib * 1024
        }
        return memory
    }
}
