//
//  Untitled.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/27/25.
//

import CMach
import Darwin.Mach


public struct ThreadStateX86: AnyThreadState {
    public var raw = x86_thread_state64_t()
    public init() {}
    
    public static let flavor: thread_state_flavor_t =
        thread_state_flavor_t(x86_THREAD_STATE64)

    public static let count: mach_msg_type_number_t =
        mach_msg_type_number_t(MemoryLayout<x86_thread_state64_t>.size / MemoryLayout<UInt32>.size)

    public var pc: UInt64 { get { raw.__rip } set { raw.__rip = newValue } }
    public var sp: UInt64 { get { raw.__rsp } set { raw.__rsp = newValue } }
    public var retVal: UInt64 { raw.__rax }

    // SysV AMD64: rdi, rsi, rdx, rcx, r8, r9
    public var arg0: UInt64 { get { raw.__rdi } set { raw.__rdi = newValue } }
    public var arg1: UInt64 { get { raw.__rsi } set { raw.__rsi = newValue } }
    public var arg2: UInt64 { get { raw.__rdx } set { raw.__rdx = newValue } }
    public var arg3: UInt64 { get { raw.__rcx } set { raw.__rcx = newValue } }
    public var arg4: UInt64 { get { raw.__r8 } set { raw.__r8 = newValue } }
    public var arg5: UInt64 { get { raw.__r9 } set { raw.__r9 = newValue } }
}

