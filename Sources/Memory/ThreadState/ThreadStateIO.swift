//
//  ThreadStateIO.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/27/25.
//

import Darwin.Mach

@inline(__always)

public func getThreadState<T: AnyThreadState>(_ type: T.Type, thread: thread_act_t) -> T? {
    var state = T()
    var count = T.count

    let kr: kern_return_t = withIntegerBuffer(of: &state, count: count) {
        thread_get_state(thread, T.flavor, $0, &count)
    }

    return (kr == KERN_SUCCESS) ? state : nil
}

public func setThreadState<T: AnyThreadState>(_ state: inout T, thread: thread_act_t) -> Bool {
    var count = T.count

    let kr: kern_return_t = withIntegerBuffer(of: &state, count: count) {
        thread_set_state(thread, T.flavor, $0, count)
    }

    return kr == KERN_SUCCESS
}


@inline(__always)
private func krString(_ kr: kern_return_t) -> String {
    if let c = mach_error_string(kr) {
        return String(cString: c)
    }
    return "unknown"
}

public struct ThreadStateResult<T> {
    public let state: T?
    public let kr: kern_return_t
    public let requestedCount: mach_msg_type_number_t
    public let returnedCount: mach_msg_type_number_t
}

public func getThreadStateDebug<T: AnyThreadState>(_ type: T.Type, thread: thread_act_t) -> ThreadStateResult<T> {
    var state = T()
    var count = T.count
    let requested = count

    let kr: kern_return_t = withIntegerBuffer(of: &state, count: count) {
        thread_get_state(thread, T.flavor, $0, &count)
    }

    return ThreadStateResult(
        state: (kr == KERN_SUCCESS) ? state : nil,
        kr: kr,
        requestedCount: requested,
        returnedCount: count
    )
}

public func setThreadStateDebug<T: AnyThreadState>(_ state: inout T, thread: thread_act_t) -> (ok: Bool, kr: kern_return_t) {
    let count = T.count
    let kr: kern_return_t = withIntegerBuffer(of: &state, count: count) {
        thread_set_state(thread, T.flavor, $0, count)
    }
    return (kr == KERN_SUCCESS, kr)
}
