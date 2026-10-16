import Foundation
import Darwin.Mach

struct SystemSnapshot {
    let memoryUsedRatio: Double
    let memoryText: String
    let diskUsedRatio: Double
    let diskText: String
    let networkActivityRatio: Double
    let networkActivityText: String
    let appMemoryRatio: Double
    let appMemoryText: String
    let cpuLoadRatio: Double
    let cpuLoadText: String
    let uptimeText: String
    let logSizeText: String
}

enum SystemMonitor {
    static func snapshot(logURL: URL) -> SystemSnapshot {
        let memory = memoryUsage()
        let disk = diskUsage()
        let network = networkActivity()
        let appMemory = appMemoryUsage()
        let cpu = cpuLoad()
        return SystemSnapshot(
            memoryUsedRatio: memory.ratio,
            memoryText: memory.text,
            diskUsedRatio: disk.ratio,
            diskText: disk.text,
            networkActivityRatio: network.ratio,
            networkActivityText: network.text,
            appMemoryRatio: min(appMemory.bytes / 1_000_000_000, 1),
            appMemoryText: byteText(appMemory.bytes),
            cpuLoadRatio: cpu.ratio,
            cpuLoadText: cpu.text,
            uptimeText: uptimeText(),
            logSizeText: logSizeText(logURL)
        )
    }

    private static var previousNetworkTotalBytes: UInt64?
    private static var previousNetworkSampleDate: Date?

    private static func memoryUsage() -> (ratio: Double, text: String) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return (0, "Unavailable")
        }

        let pageSize = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * pageSize
        let inactive = Double(stats.inactive_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let used = active + inactive + wired + compressed
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        return (total > 0 ? used / total : 0, "\(byteText(used)) / \(byteText(total))")
    }

    private static func diskUsage() -> (ratio: Double, text: String) {
        do {
            let url = URL(fileURLWithPath: NSHomeDirectory())
            let values = try url.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey
            ])
            let available = Double(values.volumeAvailableCapacityForImportantUsage ?? 0)
            let total = Double(values.volumeTotalCapacity ?? 0)
            let used = max(total - available, 0)
            return (total > 0 ? used / total : 0, "\(byteText(available)) free")
        } catch {
            return (0, "Unavailable")
        }
    }

    private static func networkActivity() -> (ratio: Double, text: String) {
        let totalBytes = networkInterfaceBytes()
        let now = Date()
        defer {
            previousNetworkTotalBytes = totalBytes
            previousNetworkSampleDate = now
        }

        guard
            let previousBytes = previousNetworkTotalBytes,
            let previousDate = previousNetworkSampleDate
        else {
            return (0, "Sampling")
        }

        let elapsed = max(now.timeIntervalSince(previousDate), 1)
        let byteDelta = totalBytes >= previousBytes ? totalBytes - previousBytes : 0
        let bytesPerSecond = Double(byteDelta) / elapsed
        let ratio = min(bytesPerSecond / 5_000_000, 1)
        return (ratio, "\(byteText(bytesPerSecond))/s")
    }

    private static func networkInterfaceBytes() -> UInt64 {
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0, let firstAddress = addressPointer else {
            return 0
        }
        defer { freeifaddrs(addressPointer) }

        var total: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let interface = cursor?.pointee {
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK
            if isUp, !isLoopback, interface.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
               let data = interface.ifa_data {
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                total += UInt64(stats.ifi_ibytes) + UInt64(stats.ifi_obytes)
            }
            cursor = interface.ifa_next
        }
        return total
    }

    private static func appMemoryUsage() -> (bytes: Double, text: String) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, "Unavailable") }
        return (Double(info.resident_size), byteText(Double(info.resident_size)))
    }

    private static func cpuLoad() -> (ratio: Double, text: String) {
        var averages = [Double](repeating: 0, count: 3)
        let count = getloadavg(&averages, 3)
        guard count > 0 else { return (0, "Unavailable") }
        let cores = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        let ratio = averages[0] / Double(cores)
        return (min(ratio, 1), String(format: "%.2f load", averages[0]))
    }

    private static func uptimeText() -> String {
        let seconds = Int(ProcessInfo.processInfo.systemUptime)
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        return "\(hours)h \((seconds % 3_600) / 60)m"
    }

    private static func logSizeText(_ url: URL) -> String {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber
        else {
            return "0 KB"
        }
        return byteText(size.doubleValue)
    }

    private static func byteText(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
