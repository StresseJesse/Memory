//
//  ThreadStateX64.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/27/25.
//


import Darwin.Mach

public struct ThreadStateArm: AnyThreadState {
    public var raw = arm_thread_state64_t()
    public init() {}

    public static let flavor: thread_state_flavor_t =
        thread_state_flavor_t(ARM_THREAD_STATE64)

    public static let count: mach_msg_type_number_t =
        mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size)

    // Convenience accessors (same as before)
    public var pc: UInt64 { get { raw.__pc } set { raw.__pc = newValue } }
    public var sp: UInt64 { get { raw.__sp } set { raw.__sp = newValue } }
    public var lr: UInt64 { get { raw.__lr } set { raw.__lr = newValue } }

    public var retVal: UInt64 { raw.__x.0 }

    public var arg0: UInt64 { get { raw.__x.0 } set { raw.__x.0 = newValue } }
    public var arg1: UInt64 { get { raw.__x.1 } set { raw.__x.1 = newValue } }
    public var arg2: UInt64 { get { raw.__x.2 } set { raw.__x.2 = newValue } }
    public var arg3: UInt64 { get { raw.__x.3 } set { raw.__x.3 = newValue } }
    public var arg4: UInt64 { get { raw.__x.4 } set { raw.__x.4 = newValue } }
    public var arg5: UInt64 { get { raw.__x.5 } set { raw.__x.5 = newValue } }
    public var arg6: UInt64 { get { raw.__x.6 } set { raw.__x.6 = newValue } }
    public var arg7: UInt64 { get { raw.__x.7 } set { raw.__x.7 = newValue } }
}
