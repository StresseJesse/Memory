//
//  ThreadStateX64.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/27/25.
//


import Darwin.Mach

public struct ThreadStateARM64: AnyThreadState {

    public init() {}

    public static let flavor: thread_state_flavor_t =
        thread_state_flavor_t(ARM_THREAD_STATE64)

    public static let count: mach_msg_type_number_t =
        mach_msg_type_number_t(
            MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size
        )

    public var raw = arm_thread_state64_t()

    // MARK: - Control

    public var pc: UInt64 {
        get { raw.__pc }
        set { raw.__pc = newValue }
    }

    public var sp: UInt64 {
        get { raw.__sp }
        set { raw.__sp = newValue }
    }

    // MARK: - Arguments (AAPCS64)

    public var arg0: UInt64 { get { raw.__x.0 } set { raw.__x.0 = newValue } }
    public var arg1: UInt64 { get { raw.__x.1 } set { raw.__x.1 = newValue } }
    public var arg2: UInt64 { get { raw.__x.2 } set { raw.__x.2 = newValue } }
    public var arg3: UInt64 { get { raw.__x.3 } set { raw.__x.3 = newValue } }

    // MARK: - Return

    public var retInt: UInt64 {
        raw.__x.0
    }
}

