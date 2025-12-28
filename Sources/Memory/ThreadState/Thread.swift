//
//  Thread.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/27/25.
//

import Darwin.Mach

public final class RemoteThread {

    public enum Error: Swift.Error {
        case noWorkerThread
        case unsupportedTargetArch
        case failedGetState
        case failedSetState
    }

    private let task: mach_port_t
    private let thread: thread_act_t
    private var originalState: ThreadStateBox?

    public init(task: mach_port_t) throws {
        self.task = task
        guard let t = ThreadSelector.selectWorkerThread(task: task) else {
            throw Error.noWorkerThread
        }
        self.thread = t
    }

    public func suspend() { thread_suspend(thread) }
    public func resume()  { thread_resume(thread) }

    // MARK: - Basic call (sleep-based; good for first validation)

    /// Executes `entry` with up to 4 integer/pointer args.
    /// Returns the integer return register (`retInt`).
    ///
    /// NOTE: This is intentionally "minimal" for first proof.
    /// For real use, switch to a breakpoint/trap-based executor.
    public func call(
        entry: mach_vm_address_t,
        arg0: UInt64 = 0,
        arg1: UInt64 = 0,
        arg2: UInt64 = 0,
        arg3: UInt64 = 0,
        timeoutUS: useconds_t = 5_000
    ) throws -> UInt64 {

        suspend()

        guard var stateBox = makeThreadState(for: task) else {
            resume()
            throw Error.unsupportedTargetArch
        }

        // Capture original state
        switch stateBox {
        case .arm64:
            guard let orig: ThreadStateARM64 = getThreadState(ThreadStateARM64.self, thread: thread) else {
                resume(); throw Error.failedGetState
            }
            originalState = .arm64(orig)

        case .x86_64:
            guard let orig: ThreadStateX86_64 = getThreadState(ThreadStateX86_64.self, thread: thread) else {
                resume(); throw Error.failedGetState
            }
            originalState = .x86_64(orig)
        }

        // Prepare call state
        switch stateBox {
        case .arm64(var s):
            guard let orig = originalState, case .arm64(let o) = orig else {
                resume(); throw Error.failedGetState
            }
            s = o
            s.pc = UInt64(entry)
            s.arg0 = arg0
            s.arg1 = arg1
            s.arg2 = arg2
            s.arg3 = arg3

            var copy = s
            guard setThreadState(&copy, thread: thread) else {
                resume(); throw Error.failedSetState
            }
            stateBox = .arm64(copy)

        case .x86_64(var s):
            guard let orig = originalState, case .x86_64(let o) = orig else {
                resume(); throw Error.failedGetState
            }
            s = o
            s.pc = UInt64(entry)
            s.arg0 = arg0
            s.arg1 = arg1
            s.arg2 = arg2
            s.arg3 = arg3

            var copy = s
            guard setThreadState(&copy, thread: thread) else {
                resume(); throw Error.failedSetState
            }
            stateBox = .x86_64(copy)
        }

        resume()

        // Let it run briefly (first proof only)
        usleep(timeoutUS)

        suspend()

        // Read result
        let ret: UInt64
        switch stateBox {
        case .arm64:
            guard let now: ThreadStateARM64 = getThreadState(ThreadStateARM64.self, thread: thread) else {
                resume(); throw Error.failedGetState
            }
            ret = now.retInt

        case .x86_64:
            guard let now: ThreadStateX86_64 = getThreadState(ThreadStateX86_64.self, thread: thread) else {
                resume(); throw Error.failedGetState
            }
            ret = now.retInt
        }

        // Restore original
        if let orig = originalState {
            switch orig {
            case .arm64(var o):
                _ = setThreadState(&o, thread: thread)
            case .x86_64(var o):
                _ = setThreadState(&o, thread: thread)
            }
        }

        resume()
        return ret
    }
}
