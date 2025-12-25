//
//  ThreadStateHelpers.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/25/25.
//
import Darwin.Mach

@inline(__always)
func threadFlavor(_ value: Int32) -> thread_flavor_t {
    thread_flavor_t(value)
}

func getThreadState(_ thread: thread_act_t) -> ThreadState? {
    var state = ThreadState()
    var count = THREAD_STATE_COUNT

    let kr = withIntegerBuffer(of: &state.raw, count: count) {
        thread_get_state(thread, THREAD_STATE_FLAVOR, $0, &count)
    }

    return kr == KERN_SUCCESS ? state : nil
}

func setThreadState(_ state: ThreadState, on thread: thread_act_t) -> Bool {
    var copy = state
    let count = THREAD_STATE_COUNT

    let kr = withIntegerBuffer(of: &copy.raw, count: count) {
        thread_set_state(thread, THREAD_STATE_FLAVOR, $0, count)
    }

    return kr == KERN_SUCCESS
}


public func selectWorkerThread(task: mach_port_t) -> thread_act_t? {
    var threads: thread_act_array_t?
    var count: mach_msg_type_number_t = 0

    guard task_threads(task, &threads, &count) == KERN_SUCCESS,
          let list = threads else { return nil }

    for i in 0..<Int(count) {
        let thread = list[i]

        var info = thread_basic_info()
        var infoCount = THREAD_BASIC_INFO_COUNT

        let kr = withIntegerBuffer(of: &info, count: infoCount) {
            thread_info(
                thread,
                thread_flavor_t(THREAD_BASIC_INFO),
                $0,
                &infoCount
            )
        }

        guard kr == KERN_SUCCESS else { continue }

        // Skip main thread
        if info.run_state == TH_STATE_RUNNING &&
           info.user_time.seconds == 0 &&
           info.system_time.seconds == 0 {
            return thread
        }
    }

    return nil
}

