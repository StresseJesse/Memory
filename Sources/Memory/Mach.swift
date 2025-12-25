//
//  Mach.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/25/25.
//

import Darwin.Mach

enum Mach {

    // MARK: - Integer rebinding (single choke point)

    @inline(__always)
    static func withIntegerBuffer<T, R>(
        of value: inout T,
        count: mach_msg_type_number_t,
        _ body: (UnsafeMutablePointer<integer_t>) -> R
    ) -> R {
        withUnsafeMutablePointer(to: &value) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                body($0)
            }
        }
    }

    // MARK: - Thread state

    @inline(__always)
    static func getThreadState(
        _ thread: thread_act_t,
        into state: inout NativeThreadState,
        count: inout mach_msg_type_number_t
    ) -> kern_return_t {
        withIntegerBuffer(of: &state, count: count) {
            thread_get_state(thread, THREAD_STATE_FLAVOR, $0, &count)
        }
    }

    @inline(__always)
    static func setThreadState(
        _ thread: thread_act_t,
        from state: inout NativeThreadState,
        count: mach_msg_type_number_t
    ) -> kern_return_t {
        withIntegerBuffer(of: &state, count: count) {
            thread_set_state(thread, THREAD_STATE_FLAVOR, $0, count)
        }
    }

    // MARK: - Thread info

    @inline(__always)
    static func getThreadBasicInfo(
        _ thread: thread_act_t,
        info: inout thread_basic_info,
        count: inout mach_msg_type_number_t
    ) -> kern_return_t {
        withIntegerBuffer(of: &info, count: count) {
            thread_info(
                thread,
                thread_flavor_t(THREAD_BASIC_INFO),
                $0,
                &count
            )
        }
    }
}
