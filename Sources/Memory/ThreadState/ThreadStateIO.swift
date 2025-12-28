//
//  ThreadStateIO.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/27/25.
//

import Darwin.Mach

@inline(__always)
private func withIntegerBuffer<T>(
    of value: inout T,
    count: mach_msg_type_number_t,
    _ body: (UnsafeMutablePointer<UInt32>) -> kern_return_t
) -> kern_return_t {
    withUnsafeMutablePointer(to: &value) {
        $0.withMemoryRebound(to: UInt32.self, capacity: Int(count)) {
            body($0)
        }
    }
}

public func getThreadState<T: AnyThreadState>(
    _ type: T.Type,
    thread: thread_act_t
) -> T? {
    var state = T()
    var count = T.count

    let kr = withIntegerBuffer(of: &state, count: count) {
        thread_get_state(thread, T.flavor, $0, &count)   // ✅ types match now
    }

    return kr == KERN_SUCCESS ? state : nil
}

public func setThreadState<T: AnyThreadState>(
    _ state: inout T,
    thread: thread_act_t
) -> Bool {
    let count = T.count

    let kr = withIntegerBuffer(of: &state, count: count) {
        thread_set_state(thread, T.flavor, $0, count)
    }

    return kr == KERN_SUCCESS
}

