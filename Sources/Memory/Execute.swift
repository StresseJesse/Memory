//
//  Execute.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/25/25.
//

import Darwin.Mach

public enum RemoteExecute {

    /// Executes a function in a remote task by hijacking a "worker" thread.
    /// This is a minimal, sleep-based executor suitable for first validation.
    ///
    /// - Returns: Integer/boolean return value (retInt). For float-returning functions
    ///            like `traceline`, validate via out-params (e.g. TraceResult.fraction)
    ///            until XMM support is added.
    public static func executeAndReturn(
        task: mach_port_t,
        function address: mach_vm_address_t,
        arguments: [UInt64] = [],
        sleepUS: useconds_t = 50_000
    ) -> UInt64? {

        guard let thread = ThreadSelector.selectWorkerThread(task: task) else { return nil }
        guard var stateBox = makeThreadState(for: task) else { return nil }

        // Suspend the worker while we hijack it
        thread_suspend(thread)
        defer { thread_resume(thread) }

        switch stateBox {

        case .arm64:
            // 1) Capture original
            guard var original: ThreadStateARM64 = getThreadState(ThreadStateARM64.self, thread: thread) else {
                return nil
            }

            // 2) Setup call state
            var call = original
            call.pc = UInt64(address)

            if arguments.count > 0 { call.arg0 = arguments[0] }
            if arguments.count > 1 { call.arg1 = arguments[1] }
            if arguments.count > 2 { call.arg2 = arguments[2] }
            if arguments.count > 3 { call.arg3 = arguments[3] }

            // NOTE: On ARM64, we are not setting LR here.
            // For first validation (traceline), we only need the out-struct to update.
            // A robust executor should set a trap stub and poll PC/LR.

            // 3) Inject + run
            guard setThreadState(&call, thread: thread) else { return nil }
            thread_resume(thread)
            usleep(sleepUS)
            thread_suspend(thread)

            // 4) Read final
            guard let final: ThreadStateARM64 = getThreadState(ThreadStateARM64.self, thread: thread) else {
                // Restore anyway
                _ = setThreadState(&original, thread: thread)
                return nil
            }

            // 5) Restore original
            _ = setThreadState(&original, thread: thread)

            return final.retInt

        case .x86_64:
            // 1) Capture original
            guard var original: ThreadStateX86_64 = getThreadState(ThreadStateX86_64.self, thread: thread) else {
                return nil
            }

            // 2) Setup call state
            var call = original
            call.pc = UInt64(address)

            if arguments.count > 0 { call.arg0 = arguments[0] }
            if arguments.count > 1 { call.arg1 = arguments[1] }
            if arguments.count > 2 { call.arg2 = arguments[2] }
            if arguments.count > 3 { call.arg3 = arguments[3] }

            // NOTE: For first validation we are not pushing a return address.
            // A robust implementation should push a known trap return and wait for it.

            // 3) Inject + run
            guard setThreadState(&call, thread: thread) else { return nil }
            thread_resume(thread)
            usleep(sleepUS)
            thread_suspend(thread)

            // 4) Read final
            guard var final: ThreadStateX86_64 = getThreadState(ThreadStateX86_64.self, thread: thread) else {
                _ = setThreadState(&original, thread: thread)
                return nil
            }

            // 5) Restore original
            _ = setThreadState(&original, thread: thread)

            return final.retInt
        }
    }
}
