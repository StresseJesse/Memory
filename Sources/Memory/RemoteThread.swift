//
//  RemoteThread.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/24/25.
//

// Thread/RemoteThread.swift
import Darwin.Mach

public final class RemoteThread {

    private let task: mach_port_t
    private let thread: thread_act_t
    private var originalState: ThreadState?

    public init?(task: mach_port_t) {
        var threads: thread_act_array_t?
        var count: mach_msg_type_number_t = 0

        guard task_threads(task, &threads, &count) == KERN_SUCCESS,
              let list = threads,
              count > 0 else {
            return nil
        }

        self.task = task
        self.thread = list[0]
    }

    private func getState() -> ThreadState {
        var state = ThreadState()
        var count = THREAD_STATE_COUNT

        _ = withUnsafeMutablePointer(to: &state.raw) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_get_state(thread, THREAD_STATE_FLAVOR, $0, &count)
            }
        }
        return state
    }

    private func setState(_ state: ThreadState) {
        var s = state
        _ = withUnsafeMutablePointer(to: &s.raw) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(THREAD_STATE_COUNT)) {
                thread_set_state(thread, THREAD_STATE_FLAVOR, $0, THREAD_STATE_COUNT)
            }
        }
    }

    public func suspend() { thread_suspend(thread) }
    public func resume()  { thread_resume(thread) }

    // MARK: - Remote Call

    public func call(
        entry: mach_vm_address_t,
        arguments: [UInt64] = [],
        timeoutUS: useconds_t = 1_000
    ) -> UInt64? {

        suspend()
        let original = getState()
        originalState = original

        var state = original

        // --- Setup call ---
        state.pc = UInt64(entry)

        #if arch(arm64)
        state.lr = UInt64(entry)   // temporary safety loop if needed
        #endif

        if arguments.count > 0 { state.arg0 = arguments[0] }
        if arguments.count > 1 { state.arg1 = arguments[1] }
        if arguments.count > 2 { state.arg2 = arguments[2] }
        if arguments.count > 3 { state.arg3 = arguments[3] }
        if arguments.count > 4 { state.arg4 = arguments[4] }
        if arguments.count > 5 { state.arg5 = arguments[5] }
        if arguments.count > 6 { state.arg6 = arguments[6] }
        if arguments.count > 7 { state.arg7 = arguments[7] }

        setState(state)
        resume()

        usleep(timeoutUS)

        suspend()
        let result = getState().retVal

        // --- Restore original thread state ---
        setState(original)
        resume()

        return result
    }
}

