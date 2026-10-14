import AppKit
import Combine
import Darwin
import IOKit.ps

struct HealthSnapshot: Sendable {
    var cpuUsage: Double?
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    var diskAvailable: UInt64 = 0
    var diskTotal: UInt64 = 0
    var uptime: TimeInterval = 0
    var batteryPercent: Int?
    var batteryCharging = false
    var thermalState = "Normal"
}

@MainActor
final class SystemHealth: ObservableObject {
    @Published private(set) var snapshot = HealthSnapshot()
    private var refreshTask: Task<Void, Never>?
    private var users = 0

    /// Each visible consumer owns a subscription, so closing one doesn't stop another.
    func start() {
        users += 1
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            var previous: [UInt64]?
            while !Task.isCancelled {
                let sample = await Task.detached(priority: .utility) { HealthReader.read() }.value
                guard !Task.isCancelled, let self else { return }
                var next = sample.snapshot
                if let previous, previous.count == sample.ticks.count {
                    let deltas = zip(sample.ticks, previous).map { $0 >= $1 ? $0 - $1 : 0 }
                    let total = deltas.reduce(0, +)
                    if total > 0 { next.cpuUsage = Double(total - deltas[Int(CPU_STATE_IDLE)]) / Double(total) }
                }
                previous = sample.ticks
                self.snapshot = next
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        refreshTask?.cancel()
        refreshTask = nil
    }

    deinit { refreshTask?.cancel() }
}

private enum HealthReader {
    static func read() -> (snapshot: HealthSnapshot, ticks: [UInt64]) {
        var result = HealthSnapshot()
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var cpu = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let cpuStatus = withUnsafeMutablePointer(to: &cpu) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        let ticks = cpuStatus == KERN_SUCCESS ? withUnsafeBytes(of: cpu.cpu_ticks) {
            Array($0.bindMemory(to: UInt32.self)).map(UInt64.init)
        } : []
        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let vmStatus = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &vmCount)
            }
        }
        if vmStatus == KERN_SUCCESS {
            var pageSize: vm_size_t = 0
            host_page_size(host, &pageSize)
            // Wired + active/inactive minus reclaimable cache + compressed physical pages.
            let pages = UInt64(vm.active_count) + UInt64(vm.inactive_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)
            let reclaimable = UInt64(vm.purgeable_count) + UInt64(vm.external_page_count)
            result.memoryUsed = min(result.memoryTotal, (pages > reclaimable ? pages - reclaimable : 0) * UInt64(pageSize))
        }
        var disk = statfs()
        if statfs(NSHomeDirectory(), &disk) == 0 {
            result.diskTotal = UInt64(disk.f_blocks) * UInt64(disk.f_bsize)
            result.diskAvailable = UInt64(disk.f_bavail) * UInt64(disk.f_bsize)
        }
        result.uptime = ProcessInfo.processInfo.systemUptime
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: result.thermalState = "Normal"
        case .fair: result.thermalState = "Aquecendo"
        case .serious: result.thermalState = "Elevada"
        case .critical: result.thermalState = "Crítica"
        @unknown default: result.thermalState = "Indisponível"
        }
        if let sources = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(sources)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let values = IOPSGetPowerSourceDescription(sources, source)?.takeUnretainedValue() as? [String: Any],
                      values[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                      let current = values[kIOPSCurrentCapacityKey] as? Int,
                      let maximum = values[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
                result.batteryPercent = Int((Double(current) / Double(maximum) * 100).rounded())
                result.batteryCharging = values[kIOPSIsChargingKey] as? Bool ?? false
                break
            }
        }
        return (result, ticks)
    }
}

struct LocalCommandResult: Sendable {
    let status: Int32
    let output: String
}

enum LocalCommand {
    static var isFixture: Bool { ProcessInfo.processInfo.environment["CLEANUP_MAC_FIXTURE_HOME"] != nil }

    static func run(_ executable: String, _ arguments: [String]) -> LocalCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            pipe.fileHandleForWriting.closeFile()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return .init(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        } catch { return .init(status: -1, output: error.localizedDescription) }
    }

    static func maintenance(_ task: MaintenanceTask) -> LocalCommandResult {
        guard !isFixture else { return .init(status: -1, output: "Operação desativada na sessão de testes.") }
        // Fixed commands only. macOS presents its own authorization dialog.
        let command: String
        switch task {
        case .spotlight: command = "/usr/bin/mdutil -E /"
        case .dns: command = "/usr/bin/dscacheutil -flushcache && /usr/bin/killall -HUP mDNSResponder"
        }
        return run("/usr/bin/osascript", ["-e", "do shell script \"\(command)\" with administrator privileges"])
    }

    enum MaintenanceTask: Sendable { case spotlight, dns }
}

struct StartupEntry: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let label: String
    let program: String
    let scope: String
    let startsAtLoad: Bool

    static func inventory() -> [StartupEntry] {
        let home = ProcessInfo.processInfo.environment["CLEANUP_MAC_FIXTURE_HOME"] ?? NSHomeDirectory()
        var directories = [(home + "/Library/LaunchAgents", "Sua sessão")]
        if !LocalCommand.isFixture {
            directories += [("/Library/LaunchAgents", "Todas as sessões"), ("/Library/LaunchDaemons", "Sistema")]
        }
        return directories.flatMap { directory, scope in
            let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: directory), includingPropertiesForKeys: nil)) ?? []
            return urls.filter { $0.pathExtension == "plist" }.compactMap { url -> StartupEntry? in
                guard let data = try? Data(contentsOf: url),
                      let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
                let program = values["Program"] as? String ?? (values["ProgramArguments"] as? [String])?.first ?? "Não informado"
                return StartupEntry(url: url, label: values["Label"] as? String ?? url.deletingPathExtension().lastPathComponent,
                                    program: program, scope: scope, startsAtLoad: values["RunAtLoad"] as? Bool ?? false)
            }
        }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
}
