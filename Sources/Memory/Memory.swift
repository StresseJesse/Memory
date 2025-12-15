//
//  Memory.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/12/25.
//

import Foundation
import Darwin
import AppKit

// -------------------------------
// MARK: - Architecture-specific constants
// -------------------------------

#if arch(arm64)
import Darwin.Mach

typealias ThreadState         = arm_thread_state64_t
let THREAD_STATE_FLAVOR       = ARM_THREAD_STATE64
let THREAD_STATE_COUNT        = mach_msg_type_number_t(
                                    MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)

#elseif arch(x86_64)
import Darwin.Mach

typealias ThreadState         = x86_thread_state64_t
let THREAD_STATE_FLAVOR       = x86_THREAD_STATE64
let THREAD_STATE_COUNT        = mach_msg_type_number_t(MemoryLayout<x86_thread_state64_t>.size / MemoryLayout<natural_t>.size)
#endif


// -------------------------------
// MARK: - ProcessMemory Class
// -------------------------------

public final class ProcessMemory {

    public let pid: pid_t
    public let taskPort: mach_port_t
    public let regions: Regions
    public let mainExecutable: Region
    public let baseAddress: mach_vm_address_t
    public let isTranslated: Bool = false   // assuming Rosetta is handled externally

    // ---------------------------
    // Initializer by PID
    // ---------------------------
    public init?(pid: pid_t) {
        print("attempting to get task port for pid: \(pid)")
        guard let tport = ProcessMemory.getTaskPort(pid: pid) else { return nil }
        print("taskPort: \(tport)")
        self.pid = pid
        self.taskPort = tport
        self.regions = Regions(taskPort: tport)
        guard let mainExec = self.regions.mainExecutable() else { return nil }
        self.mainExecutable = mainExec
        self.baseAddress = mainExec.address
    }

    // ---------------------------
    // Convenience initializer by process name
    // ---------------------------
    public convenience init?(processName: String) {
        // honestly just because I'm too lazy to keep looking up pids
        guard let foundApp = NSWorkspace.shared.runningApplications
                .first(where: { $0.localizedName?.lowercased() == processName.lowercased() }) else {
            return nil
        }
        let pid = foundApp.processIdentifier
        print("pid: \(pid)")
        self.init(pid: pid)
    }

    // ---------------------------
    // Read a value of type T
    // ---------------------------
    public func read<T>(at address: mach_vm_address_t) -> T? {
        let size = MemoryLayout<T>.size
        var outSize: mach_vm_size_t = 0

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size,
                                                      alignment: MemoryLayout<T>.alignment)
        defer { buffer.deallocate() }

        let kr = mach_vm_read_overwrite(
            taskPort,
            address,
            UInt64(size),
            mach_vm_address_t(UInt(bitPattern: buffer)),
            &outSize
        )

        guard kr == KERN_SUCCESS, outSize == size else { return nil }

        return buffer.load(as: T.self)
    }
    
    // ---------------------------
    // Read a specific number of bytes from address
    // ---------------------------
    public func read(at address: mach_vm_address_t, bytes: Int) -> [UInt8]? {
        print("reading \(bytes) bytes from \(address)")
        var buffer = [UInt8](repeating: 0, count: bytes)
        var outSize: mach_vm_size_t = 0

        let kr = buffer.withUnsafeMutableBytes { ptr -> kern_return_t in
            mach_vm_read_overwrite(taskPort,
                                   address,
                                   UInt64(bytes),
                                   mach_vm_address_t(UInt(bitPattern: ptr.baseAddress!)),
                                   &outSize)
        }

        guard kr == KERN_SUCCESS, outSize == bytes else { return nil }
        return buffer
    }

    // ---------------------------
    // Write a value of type T
    // ---------------------------
//    public func write<T>(value: T, to address: mach_vm_address_t) -> Bool {
//        var val = value
//        let kr = withUnsafePointer(to: &val) { ptr -> kern_return_t in
//            let rawPtr = UnsafeRawPointer(ptr)
//            return mach_vm_write(taskPort,
//                                 address,
//                                 vm_offset_t(UInt(bitPattern: rawPtr)),
//                                 mach_msg_type_number_t(MemoryLayout<T>.size))
//        }
//
//        if kr != KERN_SUCCESS {
//            print("Failed to write value at \(String(format: "%#llx", address))")
//        }
//
//        return kr == KERN_SUCCESS
//    }

    // ---------------------------
    // Follow a pointer chain
    // ---------------------------
    public func followPointerChain(base: mach_vm_address_t, offsets: [UInt64]) -> mach_vm_address_t? {
        var current = base
        for offset in offsets {
            guard let next: UInt64 = read(at: current) else { return nil }
            current = next + offset
        }
        return current
    }

    public func followPointerChain(offsets: [UInt64]) -> mach_vm_address_t? {
        guard let first = offsets.first else { return nil }
        return followPointerChain(base: baseAddress + first,
                                  offsets: Array(offsets.dropFirst()))
    }

    // ---------------------------
    // Get all thread states
    // ---------------------------
    func getAllThreadStates() -> [ThreadState] {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let kr = task_threads(taskPort, &threadList, &threadCount)
        guard kr == KERN_SUCCESS, let list = threadList else {
            print("Failed to get threads: \(kr)")
            return []
        }

        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: list)),
                          vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_act_t>.size))
        }

        var results: [ThreadState] = []
        for i in 0..<Int(threadCount) {
            let thread = list[i]
            if let state = getThreadState(thread: thread) {
                results.append(state)
            }
            mach_port_deallocate(mach_task_self_, thread)
        }
        return results
    }

    private func getThreadState(thread: thread_act_t) -> ThreadState? {
        var state = ThreadState()
        var count = THREAD_STATE_COUNT

        let kr = withUnsafeMutableBytes(of: &state) { rawBuffer -> kern_return_t in
            thread_get_state(thread,
                             THREAD_STATE_FLAVOR,
                             rawBuffer.baseAddress!.assumingMemoryBound(to: natural_t.self),
                             &count)
        }

        return (kr == KERN_SUCCESS) ? state : nil
    }

    // ---------------------------
    // Register access helpers
    // ---------------------------
    static func pc(of state: ThreadState) -> UInt64 {
        #if arch(arm64)
        return state.__pc
        #elseif arch(x86_64)
        return state.__rip
        #endif
    }

    static func sp(of state: ThreadState) -> UInt64 {
        #if arch(arm64)
        return state.__sp
        #elseif arch(x86_64)
        return state.__rsp
        #endif
    }

    // ---------------------------
    // Task port acquisition
    // ---------------------------
    private static func getTaskPort(pid: pid_t) -> mach_port_t? {
        var port: mach_port_t = mach_port_t(MACH_PORT_NULL)
        let kr = task_for_pid(mach_task_self_, pid, &port)
        guard kr == KERN_SUCCESS else {
            print("task_for_pid(\(pid)) failed: \(kr)")
            return nil
        }
        return port
    }

    // ---------------------------
    // Executable path helper
    // ---------------------------
    static func getExecutablePath(pid: pid_t) -> String? {
        let PROC_PIDPATHINFO_MAXSIZE = 4096
        var buf = [CChar](repeating: 0, count: PROC_PIDPATHINFO_MAXSIZE)
        // Ensure the buffer size is cast correctly for the C function signature
        let ret = proc_pidpath(pid, &buf, UInt32(buf.count))
        
        guard ret > 0 else { return nil }

        // Create a buffer slice up to the number of bytes returned (which includes the null terminator)
        let data = Data(bytes: buf, count: Int(ret))

        if let string = String(data: data, encoding: .utf8) {
             // Remove the expected single null terminator that proc_pidpath ensures
             return string.trimmingCharacters(in: CharacterSet(["\0"]))
        }
        
        return nil
    }
}
