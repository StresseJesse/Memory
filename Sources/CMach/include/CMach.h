#pragma once

#include <mach/mach.h>
#include <mach/thread_act.h>
#include <mach/thread_status.h>
#include <stdint.h>

/*
 IMPORTANT:
 ----------
 On real x86_64 builds, Darwin ALREADY defines:
   - x86_thread_state64_t
   - x86_THREAD_STATE64

 Redefining them causes:
   "typedef redefinition with different types"

 Therefore:
   • On x86_64 → do NOTHING
   • On arm64  → provide shim definitions so Swift can see them
*/

#if defined(__x86_64__)

/*
 * x86_64 host:
 * Use system-provided definitions.
 * DO NOT define anything here.
 */

#else  /* arm64 host (Apple Silicon) */

/*
 * Apple Silicon:
 * Darwin headers intentionally hide x86 thread state.
 * We provide minimal ABI-compatible shims so Swift can use them.
 */

#ifndef x86_THREAD_STATE64
  // thread_state_flavor_t value for x86_64 general registers
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

#endif /* __x86_64__ */
