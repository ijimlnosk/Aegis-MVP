import Darwin.Mach
import Foundation

enum VisionMemoryPressure: String, Sendable { case normal, warning, critical }

protocol VisionMemoryPressureProviding: Sendable {
  func current() -> VisionMemoryPressure
}

struct SystemMemoryPressure: VisionMemoryPressureProviding {
  func current() -> VisionMemoryPressure {
    var pageSize: vm_size_t = 0
    guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return .warning }
    var statistics = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: statistics)
      / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &statistics) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }
    guard status == KERN_SUCCESS else { return .warning }
    let pages = UInt64(statistics.free_count + statistics.inactive_count
      + statistics.speculative_count)
    let available = pages * UInt64(pageSize)
    let ratio = Double(available) / Double(ProcessInfo.processInfo.physicalMemory)
    if ratio < 0.05 { return .critical }
    if ratio < 0.12 { return .warning }
    return .normal
  }
}
