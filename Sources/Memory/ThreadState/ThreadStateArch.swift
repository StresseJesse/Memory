//
//  Untitled.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/29/25.
//

import Darwin.Mach

public enum ThreadStateArch: CustomStringConvertible {
    case arm64
    case x86_64

    public var description: String {
        switch self {
        case .arm64: return "arm64"
        case .x86_64: return "x86_64"
        }
    }
}

/// Detects which thread_get_state flavors are actually accepted for this task.
/// This is the thing you MUST use for Rosetta targets.
public func detectThreadStateArch(task: mach_port_t) -> ThreadStateArch? {
    var threads: thread_act_array_t?
    var count: mach_msg_type_number_t = 0

    let kr = task_threads(task, &threads, &count)
    guard kr == KERN_SUCCESS, let list = threads, count > 0 else { return nil }
    defer {
        vm_deallocate(
            mach_task_self_,
            vm_address_t(UInt(bitPattern: list)),
            vm_size_t(count) * vm_size_t(MemoryLayout<thread_act_t>.stride)
        )
    }

    for i in 0..<Int(count) {
        let t = list[i]
        if t == mach_thread_self() { continue }

        // Probe ARM64 flavor
        var a = arm_thread_state64_t()
        var ac = mach_msg_type_number_t(UInt32(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size))
        let krA: kern_return_t = withUnsafeMutablePointer(to: &a) { p in
            p.withMemoryRebound(to: UInt32.self, capacity: Int(ac)) {
                thread_get_state(t, thread_state_flavor_t(ARM_THREAD_STATE64), $0, &ac)
            }
        }
        if krA == KERN_SUCCESS { return .arm64 }

        // Probe x86_64 flavor
        var x = x86_thread_state64_t()
        var xc = mach_msg_type_number_t(UInt32(MemoryLayout<x86_thread_state64_t>.size / MemoryLayout<UInt32>.size))
        let krX: kern_return_t = withUnsafeMutablePointer(to: &x) { p in
            p.withMemoryRebound(to: UInt32.self, capacity: Int(xc)) {
                thread_get_state(t, thread_state_flavor_t(x86_THREAD_STATE64), $0, &xc)
            }
        }
        if krX == KERN_SUCCESS { return .x86_64 }
    }

    return nil
}
