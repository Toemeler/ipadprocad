import Foundation
import UIKit

/// The numbers Dart cannot see.
///
/// WHY THIS EXISTS
/// ---------------
/// The whole perf effort is aimed at one question: will this be usable on an
/// M2 or an A-series chip, when the only device available to test on is an M4?
/// Three of the facts that decide that answer are invisible from Dart:
///
///  1. THERMAL STATE. A sustained benchmark on a fanless iPad throttles. An M4
///     may never leave `.nominal` where an A-chip sits in `.serious` for the
///     whole run — and a report that does not say which was which invites the
///     conclusion that the code got slower, when the silicon got hotter. This
///     is the single most important number here: without it, cross-chip
///     comparison is guesswork dressed up as measurement.
///
///  2. PHYSICAL FOOTPRINT. Dart reports `ProcessInfo.currentRss`, the resident
///     set. iOS does not kill on RSS — it kills on `phys_footprint`, which
///     counts compressed and IOKit-mapped memory RSS does not. The device
///     session that died during a fillet reported 839 MB of RSS; the number
///     that actually mattered was never captured. `os_proc_available_memory`
///     is the other half: how much headroom is left before jetsam.
///
///  3. PER-THREAD CPU. Flutter splits work across the platform, UI, raster and
///     IO threads. "The app used 180% CPU" says nothing about which one to
///     fix; a per-thread breakdown says whether a stall is Dart, the
///     rasteriser, or a background isolate.
///
/// WHAT THIS DELIBERATELY DOES NOT DO
/// ----------------------------------
/// No sampling profiler, no signposts, no MetricKit subscription. Those want a
/// lifecycle and a delivery path; this is a pull-only snapshot that any caller
/// can take at any moment, which is what a scenario runner and a bug bundle
/// both need. Everything is best effort: a probe that throws while reporting
/// on health is worse than one that returns a partial map.
enum PerfProbe {

    /// One snapshot. Keys are stable — a baseline is diffed on them.
    static func snapshot() -> [String: Any] {
        var out: [String: Any] = [:]

        // ---- thermal + power ----------------------------------------------
        let info = ProcessInfo.processInfo
        out["thermalState"] = thermalName(info.thermalState)
        // Ordinal too: a report can plot 0..3 but cannot plot a word, and the
        // interesting signal is a RISE during a run.
        out["thermalOrdinal"] = info.thermalState.rawValue
        out["lowPowerMode"] = info.isLowPowerModeEnabled
        out["processorCount"] = info.processorCount
        out["activeProcessorCount"] = info.activeProcessorCount
        // Physical RAM is what separates an 8 GB A-chip iPad from a 16 GB M4,
        // and it changes which parts are openable at all.
        out["physicalMemoryMB"] = Int(info.physicalMemory / (1024 * 1024))

        // ---- memory --------------------------------------------------------
        if let m = memoryFootprint() {
            out["footprintMB"] = m.footprint / (1024 * 1024)
            out["residentMB"] = m.resident / (1024 * 1024)
            out["peakResidentMB"] = m.peakResident / (1024 * 1024)
        }
        if #available(iOS 13.0, *) {
            // Headroom before jetsam. A part that opens with 40 MB left is one
            // fillet away from being killed, and nothing in the Dart-side
            // numbers would say so.
            out["availableMB"] = Int(os_proc_available_memory() / (1024 * 1024))
        }

        // ---- CPU ------------------------------------------------------------
        if let cpu = cpuUsage() {
            out["cpuPercent"] = cpu.total
            out["threads"] = cpu.threads
            out["threadCount"] = cpu.count
        }

        out["uptimeSec"] = Int(info.systemUptime)
        return out
    }

    // MARK: - thermal

    private static func thermalName(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    // MARK: - memory

    private struct Mem {
        let footprint: UInt64
        let resident: UInt64
        let peakResident: UInt64
    }

    /// `task_vm_info` carries `phys_footprint` — the figure iOS enforces its
    /// memory limit against, and the one RSS does not equal.
    private static func memoryFootprint() -> Mem? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return Mem(footprint: UInt64(info.phys_footprint),
                   resident: UInt64(info.resident_size),
                   peakResident: UInt64(info.resident_size_peak))
    }

    // MARK: - CPU

    private struct Cpu {
        let total: Int
        let threads: [String: Int]
        let count: Int
    }

    /// Per-thread CPU, keyed by the thread's own name where it has one.
    ///
    /// Flutter names its threads (`io.flutter.ui`, `io.flutter.raster`,
    /// `io.flutter.io`), which is exactly the breakdown that makes the number
    /// actionable: the same 150% means something different when it is the
    /// rasteriser than when it is the UI thread.
    private static func cpuUsage() -> Cpu? {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threads = threadList else { return nil }
        defer {
            // The kernel hands over a mapping we own; leaking it on every
            // snapshot would turn a diagnostic into a slow leak.
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: threads)),
                          vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride))
        }

        var total = 0
        var byName: [String: Int] = [:]
        for i in 0..<Int(threadCount) {
            var basic = thread_basic_info()
            var count = mach_msg_type_number_t(THREAD_BASIC_INFO_COUNT)
            let kr: kern_return_t = withUnsafeMutablePointer(to: &basic) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO),
                                $0, &count)
                }
            }
            guard kr == KERN_SUCCESS, basic.flags & TH_FLAGS_IDLE == 0 else { continue }
            let pct = Int(Double(basic.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0)
            total += pct
            if pct > 0, let name = threadName(threads[i]) {
                byName[name, default: 0] += pct
            }
        }
        return Cpu(total: total, threads: byName, count: Int(threadCount))
    }

    private static func threadName(_ t: thread_t) -> String? {
        var info = thread_extended_info()
        var count = mach_msg_type_number_t(THREAD_EXTENDED_INFO_COUNT)
        let kr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(t, thread_flavor_t(THREAD_EXTENDED_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let name = withUnsafePointer(to: info.pth_name) {
            $0.withMemoryRebound(to: CChar.self,
                                 capacity: MemoryLayout.size(ofValue: info.pth_name)) {
                String(cString: $0)
            }
        }
        return name.isEmpty ? nil : name
    }
}
