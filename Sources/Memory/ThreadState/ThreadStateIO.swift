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

