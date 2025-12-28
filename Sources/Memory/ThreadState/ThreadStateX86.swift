//
//  Untitled.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/27/25.
//

import Darwin.Mach

// MARK: - Mach constants (from XNU)

/// x86_THREAD_STATE64 flavor value (from mach/i386/thread_status.h)
public let THREAD_STATE_X86_64: thread_state_flavor_t = thread_state_flavor_t(4)


/// Number of 32-bit words in the x86_64 thread state
public let THREAD_STATE_X86_64_COUNT: mach_msg_type_number_t =
    mach_msg_type_number_t(
        MemoryLayout<ThreadStateX86_64Raw>.size /
        MemoryLayout<UInt32>.size
    )

// MARK: - Raw x86_64 register mirror
//
// This struct matches the memory layout of x86_thread_state64_t
// used by the kernel. Field order and size MUST remain exact.

public struct ThreadStateX86_64Raw {

    // General-purpose registers
    public var rax: UInt64 = 0
    public var rbx: UInt64 = 0
    public var rcx: UInt64 = 0
    public var rdx: UInt64 = 0
    public var rdi: UInt64 = 0
    public var rsi: UInt64 = 0
    public var rbp: UInt64 = 0
    public var rsp: UInt64 = 0

    public var r8:  UInt64 = 0
    public var r9:  UInt64 = 0
    public var r10: UInt64 = 0
    public var r11: UInt64 = 0
    public var r12: UInt64 = 0
    public var r13: UInt64 = 0
    public var r14: UInt64 = 0
    public var r15: UInt64 = 0

    // Instruction pointer and flags
    public var rip: UInt64 = 0
    public var rflags: UInt64 = 0

    // Segment registers (mostly unused but required)
    public var cs: UInt64 = 0
    public var fs: UInt64 = 0
    public var gs: UInt64 = 0

    public init() {}
}

// MARK: - High-level ThreadState wrapper

/// High-level x86_64 ThreadState used by RemoteExecute.
///
/// This conforms to AnyThreadState and provides
/// SysV ABI argument and return register access.
public struct ThreadStateX86_64: AnyThreadState {

    public var raw = ThreadStateX86_64Raw()

    // Mach metadata
    public static let flavor: thread_state_flavor_t = THREAD_STATE_X86_64
    public static let count: mach_msg_type_number_t = THREAD_STATE_X86_64_COUNT

    public init() {}

    // MARK: - Control registers

    /// Instruction pointer (RIP)
    public var pc: UInt64 {
        get { raw.rip }
        set { raw.rip = newValue }
    }

    /// Stack pointer (RSP)
    public var sp: UInt64 {
        get { raw.rsp }
        set { raw.rsp = newValue }
    }

    // MARK: - SysV integer / pointer arguments

    /// arg0 → RDI
    public var arg0: UInt64 {
        get { raw.rdi }
        set { raw.rdi = newValue }
    }

    /// arg1 → RSI
    public var arg1: UInt64 {
        get { raw.rsi }
        set { raw.rsi = newValue }
    }

    /// arg2 → RDX
    public var arg2: UInt64 {
        get { raw.rdx }
        set { raw.rdx = newValue }
    }

    /// arg3 → RCX
    public var arg3: UInt64 {
        get { raw.rcx }
        set { raw.rcx = newValue }
    }

    /// arg4 → R8
    public var arg4: UInt64 {
        get { raw.r8 }
        set { raw.r8 = newValue }
    }

    /// arg5 → R9
    public var arg5: UInt64 {
        get { raw.r9 }
        set { raw.r9 = newValue }
    }

    // MARK: - Return values

    /// Integer / boolean / pointer return (RAX)
    public var retInt: UInt64 {
        raw.rax
    }
}
