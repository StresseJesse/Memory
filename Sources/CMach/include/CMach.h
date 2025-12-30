#pragma once

#include <mach/mach.h>
#include <mach/thread_act.h>
#include <mach/thread_status.h>
#include <stdint.h>

/*
 CMach.h shims
 ============

 Goal:
 - When building an *arm64* host app (Apple Silicon), Darwin headers hide x86 thread-state types.
   We provide minimal shims for:
     - x86_thread_state64_t
     - x86_THREAD_STATE64

 - When building an *x86_64* host app (Intel / Rosetta host build), Darwin headers may hide ARM
   thread-state types.
   We provide minimal shims for:
     - arm_thread_state64_t
     - ARM_THREAD_STATE64
     - ARM_THREAD_STATE64_COUNT

 IMPORTANT:
 - Never redefine types that the platform headers already define.
 - These shims are ONLY for cross-arch thread_get_state/thread_set_state plumbing.
 */

// ------------------------------------------------------------
// x86_64 thread state shim (needed on arm64 hosts)
// ------------------------------------------------------------

#if !defined(__x86_64__)

// On Apple Silicon, x86 thread state is typically hidden.
#ifndef x86_THREAD_STATE64
  // thread_state_flavor_t value for x86_64 general registers
  // (matches Apple's x86_THREAD_STATE64)
  #define x86_THREAD_STATE64 4
#endif

#ifndef __X86_THREAD_STATE64_T__
#define __X86_THREAD_STATE64_T__ 1

typedef struct x86_thread_state64 {
    uint64_t __rax;
    uint64_t __rbx;
    uint64_t __rcx;
    uint64_t __rdx;
    uint64_t __rdi;
    uint64_t __rsi;
    uint64_t __rbp;
    uint64_t __rsp;
    uint64_t __r8;
    uint64_t __r9;
    uint64_t __r10;
    uint64_t __r11;
    uint64_t __r12;
    uint64_t __r13;
    uint64_t __r14;
    uint64_t __r15;
    uint64_t __rip;
    uint64_t __rflags;
    uint64_t __cs;
    uint64_t __fs;
    uint64_t __gs;
} x86_thread_state64_t;

#endif /* __X86_THREAD_STATE64_T__ */

#endif /* !__x86_64__ */


// ------------------------------------------------------------
// arm64 thread state shim (needed on x86_64 hosts)
// ------------------------------------------------------------

#if defined(__x86_64__)

// Some x86_64 SDK configurations do not expose ARM thread-state structs.
// Only define if missing.
#ifndef ARM_THREAD_STATE64
  // thread_state_flavor_t value for ARM64 general registers
  // (matches Apple's ARM_THREAD_STATE64)
  #define ARM_THREAD_STATE64 6
#endif

#ifndef __ARM_THREAD_STATE64_T__
#define __ARM_THREAD_STATE64_T__ 1

typedef struct arm_thread_state64 {
    // x0-x28
    uint64_t __x[29];
    // frame pointer (x29)
    uint64_t __fp;
    // link register (x30)
    uint64_t __lr;
    // stack pointer
    uint64_t __sp;
    // program counter
    uint64_t __pc;
    // current program status register
    uint32_t __cpsr;
    uint32_t __pad;
} arm_thread_state64_t;

#endif /* __ARM_THREAD_STATE64_T__ */

#ifndef ARM_THREAD_STATE64_COUNT
  // mach_msg_type_number_t count is in 32-bit words
  #define ARM_THREAD_STATE64_COUNT ((mach_msg_type_number_t)(sizeof(arm_thread_state64_t) / sizeof(uint32_t)))
#endif

#endif /* __x86_64__ */
