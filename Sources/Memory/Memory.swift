////
////  Memory.swift
////  Memory
////
////  Created by Jesse Ramsey on 12/12/25.
////
//
//import Foundation
//import Darwin
//import AppKit
//
//// -------------------------------
//// MARK: - Architecture-specific constants
//// -------------------------------
//
//
//#if arch(arm64)
//let THREAD_STATE_FLAVOR = ARM_THREAD_STATE64
//let THREAD_STATE_COUNT = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
//
//struct ThreadState {
//    var raw = arm_thread_state64_t()
//    var pc: UInt64 { get { raw.__pc } set { raw.__pc = newValue } }
//    var lr: UInt64 { get { raw.__lr } set { raw.__lr = newValue } } // Link Register
//    var arg0: UInt64 { get { raw.__x.0 } set { raw.__x.0 = newValue } }
//    var arg1: UInt64 { get { raw.__x.1 } set { raw.__x.1 = newValue } }
//    var arg2: UInt64 { get { raw.__x.2 } set { raw.__x.2 = newValue } }
//    var retVal: UInt64 { get { raw.__x.0 } }
//}
//#elseif arch(x86_64)
//let THREAD_STATE_FLAVOR = x86_THREAD_STATE64
//let THREAD_STATE_COUNT = mach_msg_type_number_t(MemoryLayout<x86_thread_state64_t>.size / MemoryLayout<natural_t>.size)
//struct ThreadState {
//    var raw = x86_thread_state64_t()
//    var pc: UInt64 { get { raw.__rip } set { raw.__rip = newValue } }
//    var sp: UInt64 { get { raw.__rsp } set { raw.__rsp = newValue } } // Added Stack Pointer
//    var arg0: UInt64 { get { raw.__rdi } set { raw.__rdi = newValue } }
//    var arg1: UInt64 { get { raw.__rsi } set { raw.__rsi = newValue } }
//    var arg2: UInt64 { get { raw.__rdx } set { raw.__rdx = newValue } }
//    var retVal: UInt64 { get { raw.__rax } }
//}
//#endif
//
//
//
//// -------------------------------
//// MARK: - ProcessMemory Class
//// -------------------------------
//
//public final class ProcessMemory {
//
//    public let pid: pid_t
//    public let task: mach_port_t
//    public let regions: Regions
//    public let mainExecutable: Region
//    public let baseAddress: mach_vm_address_t
//    public let isTranslated: Bool = false   // assuming Rosetta is handled externally
//
//    // ---------------------------
//    // Initializer by PID
//    // ---------------------------
//    public init?(pid: pid_t) {
//        print("attempting to get task port for pid: \(pid)")
//        guard let tport = ProcessMemory.getTaskPort(pid: pid) else { return nil }
//        print("taskPort: \(tport)")
//        self.pid = pid
//        self.task = tport
//        self.regions = Regions(taskPort: tport)
//        guard let mainExec = self.regions.mainExecutable() else { return nil }
//        self.mainExecutable = mainExec
//        self.baseAddress = mainExec.address
//    }
//
//    // ---------------------------
//    // Convenience initializer by process name
//    // ---------------------------
//    public convenience init?(processName: String) {
//        // honestly just because I'm too lazy to keep looking up pids
//        guard let foundApp = NSWorkspace.shared.runningApplications
//                .first(where: { $0.localizedName?.lowercased() == processName.lowercased() }) else {
//            return nil
//        }
//        let pid = foundApp.processIdentifier
//        print("pid: \(pid)")
//        self.init(pid: pid)
//    }
//
//    // ---------------------------
//    // Read a value of type T
//    // ---------------------------
//    public func read<T>(at address: mach_vm_address_t) -> T? {
//        let result: T? = self.mainExecutable.read(at: address)
//        return result
//    }
//    
//    // ---------------------------
//    // Read a specific number of bytes from address
//    // ---------------------------
//    public func read(at address: mach_vm_address_t, bytes: Int) -> [UInt8]? {
//        return self.mainExecutable.read(at: address, bytes: bytes)
//    }
//
//    // ---------------------------
//    // Write a value of type T
//    // ---------------------------
//    public func write<T>(value: T, to address: mach_vm_address_t) -> Bool {
//        return self.mainExecutable.write(value: value, to: address)
//    }
//    
//    // ---------------------------
//    // Write bytes to address
//    // ---------------------------
//    public func write(bytes: [UInt8], to address: mach_vm_address_t) -> Bool {
//        return self.mainExecutable.write(bytes: bytes, to: address)
//    }
//
//    // ---------------------------
//    // Follow a pointer chain
//    // ---------------------------
//    public func followPointerChain(base: mach_vm_address_t, offsets: [UInt64]) -> mach_vm_address_t? {
//        var current = base
//        for offset in offsets {
//            guard let next: UInt64 = read(at: current) else { return nil }
//            current = next + offset
//        }
//        return current
//    }
//
//    public func followPointerChain(offsets: [UInt64]) -> mach_vm_address_t? {
//        guard let first = offsets.first else { return nil }
//        return followPointerChain(base: baseAddress + first,
//                                  offsets: Array(offsets.dropFirst()))
//    }
//    
//    func executeAndReturn(at address: mach_vm_address_t, arguments: [UInt64]) -> UInt64? {
//        var threadList: thread_act_array_t?
//        var threadCount: mach_msg_type_number_t = 0
//        
//        // 1. Get the list of threads
//        let kr = task_threads(self.task, &threadList, &threadCount)
//        guard kr == KERN_SUCCESS, let threads = threadList, threadCount > 0 else { return nil }
//        
//        // 2. Pick a thread to hijack (e.g., the first one)
//        // FIX: 'threads' is a pointer; we access index 0 to get a single 'thread_t'
//        let targetThread = threads[0]
//        
//        // Deallocate the thread list after we've picked our target to avoid leaks
//        defer {
//            let size = threadCount * mach_msg_type_number_t(MemoryLayout<thread_t>.size)
//            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(size))
//        }
//
//        thread_suspend(targetThread)
//        
//        var state = ThreadState()
//        var stateCount = THREAD_STATE_COUNT
//        
//        // 3. Get and Set State using the single 'targetThread' port
//        let getKr = withUnsafeMutablePointer(to: &state.raw) {
//            $0.withMemoryRebound(to: integer_t.self, capacity: Int(stateCount)) {
//                thread_get_state(targetThread, THREAD_STATE_FLAVOR, $0, &stateCount)
//            }
//        }
//        
//        guard getKr == KERN_SUCCESS else { thread_resume(targetThread); return nil }
//
//        state.pc = UInt64(address)
//        if arguments.count > 0 { state.arg0 = arguments[0] }
//        if arguments.count > 1 { state.arg1 = arguments[1] }
//        if arguments.count > 2 { state.arg2 = arguments[2] }
//        
//        let setKr = withUnsafeMutablePointer(to: &state.raw) {
//            $0.withMemoryRebound(to: integer_t.self, capacity: Int(stateCount)) {
//                thread_set_state(targetThread, THREAD_STATE_FLAVOR, $0, stateCount)
//            }
//        }
//        
//        if setKr == KERN_SUCCESS {
//            thread_resume(targetThread)
//            
//            // Polling loop logic...
//            while true {
//                usleep(500)
//                thread_suspend(targetThread)
//                _ = withUnsafeMutablePointer(to: &state.raw) {
//                    $0.withMemoryRebound(to: integer_t.self, capacity: Int(stateCount)) {
//                        thread_get_state(targetThread, THREAD_STATE_FLAVOR, $0, &stateCount)
//                    }
//                }
//                if state.pc != UInt64(address) { break }
//                thread_resume(targetThread)
//            }
//        }
//        
//        let result = state.retVal
//        thread_resume(targetThread)
//        return result
//    }
//
//
//    // ---------------------------
//    // Get all thread states
//    // ---------------------------
//    func getAllThreadStates() -> [ThreadState] {
//        var threadList: thread_act_array_t?
//        var threadCount: mach_msg_type_number_t = 0
//        let kr = task_threads(task, &threadList, &threadCount)
//        guard kr == KERN_SUCCESS, let list = threadList else {
//            print("Failed to get threads: \(kr)")
//            return []
//        }
//
//        defer {
//            vm_deallocate(mach_task_self_,
//                          vm_address_t(UInt(bitPattern: list)),
//                          vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_act_t>.size))
//        }
//
//        var results: [ThreadState] = []
//        for i in 0..<Int(threadCount) {
//            let thread = list[i]
//            if let state = getThreadState(thread: thread) {
//                results.append(state)
//            }
//            mach_port_deallocate(mach_task_self_, thread)
//        }
//        return results
//    }
//
//    private func getThreadState(thread: thread_act_t) -> ThreadState? {
//        var state = ThreadState()
//        var count = THREAD_STATE_COUNT
//
//        let kr = withUnsafeMutableBytes(of: &state) { rawBuffer -> kern_return_t in
//            thread_get_state(thread,
//                             THREAD_STATE_FLAVOR,
//                             rawBuffer.baseAddress!.assumingMemoryBound(to: natural_t.self),
//                             &count)
//        }
//
//        return (kr == KERN_SUCCESS) ? state : nil
//    }
//
//    // ---------------------------
//    // Task port acquisition
//    // ---------------------------
//    private static func getTaskPort(pid: pid_t) -> mach_port_t? {
//        var port: mach_port_t = mach_port_t(MACH_PORT_NULL)
//        let kr = task_for_pid(mach_task_self_, pid, &port)
//        guard kr == KERN_SUCCESS else {
//            print("task_for_pid(\(pid)) failed: \(kr)")
//            return nil
//        }
//        return port
//    }
//
//    // ---------------------------
//    // Executable path helper
//    // ---------------------------
//    static func getExecutablePath(pid: pid_t) -> String? {
//        let PROC_PIDPATHINFO_MAXSIZE = 4096
//        var buf = [CChar](repeating: 0, count: PROC_PIDPATHINFO_MAXSIZE)
//        // Ensure the buffer size is cast correctly for the C function signature
//        let ret = proc_pidpath(pid, &buf, UInt32(buf.count))
//        
//        guard ret > 0 else { return nil }
//
//        // Create a buffer slice up to the number of bytes returned (which includes the null terminator)
//        let data = Data(bytes: buf, count: Int(ret))
//
//        if let string = String(data: data, encoding: .utf8) {
//             // Remove the expected single null terminator that proc_pidpath ensures
//             return string.trimmingCharacters(in: CharacterSet(["\0"]))
//        }
//        
//        return nil
//    }
//}
