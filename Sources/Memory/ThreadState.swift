//
//  ThreadState.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/24/25.
//

import Darwin.Mach

// MARK: - Architecture Selection (ARM64 FIRST)

#if arch(arm64)

// MARK: ARM64

typealias NativeThreadState = arm_thread_state64_t

let THREAD_STATE_FLAVOR = ARM_THREAD_STATE64
let THREAD_STATE_COUNT = mach_msg_type_number_t(
    MemoryLayout<NativeThreadState>.size / MemoryLayout<UInt32>.size
)
let THREAD_BASIC_INFO_COUNT = mach_msg_type_number_t(
    MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size
)


struct ThreadState {
    var raw = NativeThreadState()

    // Program Counter
    var pc: UInt64 {
        get { raw.__pc }
        set { raw.__pc = newValue }
    }

    // Stack Pointer
    var sp: UInt64 {
        get { raw.__sp }
        set { raw.__sp = newValue }
    }

    // Link Register (return address)
    var lr: UInt64 {
        get { raw.__lr }
        set { raw.__lr = newValue }
    }

    // Return value
    var retVal: UInt64 {
        raw.__x.0
    }

    // Arguments (AAPCS64: x0–x7)
    var arg0: UInt64 {
        get { raw.__x.0 }
        set { raw.__x.0 = newValue }
    }

    var arg1: UInt64 {
        get { raw.__x.1 }
        set { raw.__x.1 = newValue }
    }

    var arg2: UInt64 {
        get { raw.__x.2 }
        set { raw.__x.2 = newValue }
    }

    var arg3: UInt64 {
        get { raw.__x.3 }
        set { raw.__x.3 = newValue }
    }

    var arg4: UInt64 {
        get { raw.__x.4 }
        set { raw.__x.4 = newValue }
    }

    var arg5: UInt64 {
        get { raw.__x.5 }
        set { raw.__x.5 = newValue }
    }

    var arg6: UInt64 {
        get { raw.__x.6 }
        set { raw.__x.6 = newValue }
    }

    var arg7: UInt64 {
        get { raw.__x.7 }
        set { raw.__x.7 = newValue }
    }
}

#elseif arch(x86_64)

// MARK: x86_64 (fallback)

typealias NativeThreadState = x86_thread_state64_t

let THREAD_STATE_FLAVOR = x86_THREAD_STATE64
let THREAD_STATE_COUNT = mach_msg_type_number_t(
    MemoryLayout<NativeThreadState>.size / MemoryLayout<UInt32>.size
)

struct ThreadState {
    var raw = NativeThreadState()

    var pc: UInt64 {
        get { raw.__rip }
        set { raw.__rip = newValue }
    }

    var sp: UInt64 {
        get { raw.__rsp }
        set { raw.__rsp = newValue }
    }

    var retVal: UInt64 {
        raw.__rax
    }

    var arg0: UInt64 {
        get { raw.__rdi }
        set { raw.__rdi = newValue }
    }

    var arg1: UInt64 {
        get { raw.__rsi }
        set { raw.__rsi = newValue }
    }

    var arg2: UInt64 {
        get { raw.__rdx }
        set { raw.__rdx = newValue }
    }

    var arg3: UInt64 {
        get { raw.__rcx }
        set { raw.__rcx = newValue }
    }

    var arg4: UInt64 {
        get { raw.__r8 }
        set { raw.__r8 = newValue }
    }

    var arg5: UInt64 {
        get { raw.__r9 }
        set { raw.__r9 = newValue }
    }
}

#else
#error("Unsupported architecture")
#endif
