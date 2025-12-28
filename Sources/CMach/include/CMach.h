#pragma once

#include <mach/mach.h>
#include <mach/thread_act.h>
#include <mach/thread_status.h>

#include <stdint.h>

#ifndef x86_THREAD_STATE64
  // Flavor constant used by thread_get_state/thread_set_state for x86_64 GP regs.
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

#endif
