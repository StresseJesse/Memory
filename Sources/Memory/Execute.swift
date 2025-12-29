//
//  Execute.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/25/25.
//

import Darwin.Mach

public enum RemoteExecute {

    public static func executeAndReturn(
        task: mach_port_t,
        function address: mach_vm_address_t,
        arguments: [UInt64] = [],
        sleepUS: useconds_t = 50_000
    ) -> UInt64? {

        guard let thread = ThreadSelector.selectWorkerThread(task: task) else {
            print("[RemoteExecute] selectWorkerThread failed")
            return nil
        }

        guard let arch = detectTargetArch(task: task) else {
            print("[RemoteExecute] detectTargetArch failed")
            return nil
        }
        print("[RemoteExecute] target arch:", arch)

        thread_suspend(thread)
        defer { thread_resume(thread) }

        switch arch {

        case .arm64:
            guard var original: ThreadStateArm = getThreadState(ThreadStateArm.self, thread: thread) else {
                print("[RemoteExecute] getThreadState ARM64 failed")
                return nil
            }

            var call = original
            call.pc = UInt64(address)
            if arguments.count > 0 { call.arg0 = arguments[0] }
            if arguments.count > 1 { call.arg1 = arguments[1] }
            if arguments.count > 2 { call.arg2 = arguments[2] }
            if arguments.count > 3 { call.arg3 = arguments[3] }

            var tmp = call
            guard setThreadState(&tmp, thread: thread) else {
                print("[RemoteExecute] setThreadState ARM64 failed")
                return nil
            }

            thread_resume(thread)
            usleep(sleepUS)
            thread_suspend(thread)

            guard let final: ThreadStateArm = getThreadState(ThreadStateArm.self, thread: thread) else {
                print("[RemoteExecute] getThreadState ARM64 final failed")
                _ = setThreadState(&original, thread: thread)
                return nil
            }

            _ = setThreadState(&original, thread: thread)
            return final.retVal

        case .x86_64:
            // 1) Snapshot original thread state so we can restore later
            guard var original: ThreadStateX86 = getThreadState(ThreadStateX86.self, thread: thread) else {
                print("[RemoteExecute] getThreadState X86_64 failed")
                return nil
            }

            // ---- Allocate remote stub + return storage ----
            var retAddr: mach_vm_address_t = 0
            var stubAddr: mach_vm_address_t = 0

            guard MachCalls.allocate(task: task, size: 16, address: &retAddr) == KERN_SUCCESS,
                  MachCalls.allocate(task: task, size: 64, address: &stubAddr) == KERN_SUCCESS
            else {
                print("[RemoteExecute] allocate stub/ret failed")
                return nil
            }

            defer {
                MachCalls.deallocate(task: task, address: retAddr, size: 16)
                MachCalls.deallocate(task: task, address: stubAddr, size: 64)
            }

            // Fill return area with 0xAA so you can see if it changes
            let fill = [UInt8](repeating: 0xAA, count: 16)
            let krFill = fill.withUnsafeBytes { raw -> kern_return_t in
                MachCalls.write(task: task,
                                address: retAddr,
                                buffer: raw.baseAddress!,
                                count: raw.count)
            }
            if krFill != KERN_SUCCESS {
                print("[RemoteExecute] fill ret area write failed:", krFill)
                // continue anyway
            }

            // ---- Build x86_64 stub ----
            // mov rax, <func>
            // call rax
            // mov rcx, <retAddr>
            // movd dword ptr [rcx], xmm0
            // mov [rcx+8], rax
            // jmp $-2
            var code: [UInt8] = []

            @inline(__always) func append(_ bytes: [UInt8]) { code.append(contentsOf: bytes) }
            @inline(__always) func le64(_ v: UInt64) -> [UInt8] {
                withUnsafeBytes(of: v.littleEndian, Array.init)
            }

            append([0x48, 0xB8]); append(le64(UInt64(address)))   // mov rax, imm64
            append([0xFF, 0xD0])                                  // call rax
            append([0x48, 0xB9]); append(le64(UInt64(retAddr)))   // mov rcx, imm64
            append([0x66, 0x0F, 0x7E, 0x01])                       // movd [rcx], xmm0
            append([0x48, 0x89, 0x41, 0x08])                       // mov [rcx+8], rax
            append([0xEB, 0xFE])                                  // jmp $

            // Write stub into remote memory
            let krStubWrite = code.withUnsafeBytes { raw -> kern_return_t in
                MachCalls.write(task: task,
                                address: stubAddr,
                                buffer: raw.baseAddress!,
                                count: raw.count)
            }
            guard krStubWrite == KERN_SUCCESS else {
                print("[RemoteExecute] stub write failed:", krStubWrite)
                return nil
            }

            // Make stub RX (no longer writable)
            let krProt = MachCalls.protect(task: task,
                                           address: stubAddr,
                                           size: 64,
                                           protection: VM_PROT_READ | VM_PROT_EXECUTE)
            if krProt != KERN_SUCCESS {
                print("[RemoteExecute] protect RX failed:", krProt)
                // not fatal for first test, but usually you'd bail
            }

            // ---- Configure thread state to start at stub ----
            var call = original
            call.pc = UInt64(stubAddr)

            // SysV x86_64 args: rdi, rsi, rdx, rcx, r8, r9
            if arguments.count > 0 { call.arg0 = arguments[0] } // rdi
            if arguments.count > 1 { call.arg1 = arguments[1] } // rsi
            if arguments.count > 2 { call.arg2 = arguments[2] } // rdx
            if arguments.count > 3 { call.arg3 = arguments[3] } // rcx

            var tmp = call
            guard setThreadState(&tmp, thread: thread) else {
                print("[RemoteExecute] setThreadState X86_64 failed")
                return nil
            }

            // Run briefly so stub can execute, then stop it (stub spins so it’s safe)
            thread_resume(thread)
            usleep(sleepUS)
            thread_suspend(thread)

            // Read stored return(s)
            var outSize: mach_vm_size_t = 0
            var retBuf = [UInt8](repeating: 0, count: 16)
            let krRead = retBuf.withUnsafeMutableBytes { raw -> kern_return_t in
                MachCalls.readOverwrite(task: task,
                                        remote: retAddr,
                                        size: 16,
                                        local: mach_vm_address_t(UInt(bitPattern: raw.baseAddress!)),
                                        outSize: &outSize)
            }
            guard krRead == KERN_SUCCESS, outSize == 16 else {
                _ = setThreadState(&original, thread: thread)
                return nil
            }

            let rax: UInt64 = retBuf[8..<16].withUnsafeBytes { $0.load(as: UInt64.self) }

            // Restore original thread state before returning
            _ = setThreadState(&original, thread: thread)
            return rax
//            ///---------------
//            // VERSION 2
//            ///---------------
//            guard var original: ThreadStateX86 = getThreadState(ThreadStateX86.self, thread: thread) else {
//                print("[RemoteExecute] getThreadState X86_64 failed")
//                return nil
//            }
//
//            // ---- Allocate remote stub + return storage ----
//            // Store: [0..3] = float return (xmm0), [8..15] = rax (integer return if any)
//            guard let retAddr = MachCalls.write(task: task, size: 16),
//                  let stubAddr = memoryAllocate(task: task, size: 64)
//            else {
//                print("[RemoteExecute] allocate stub/ret failed")
//                return nil
//            }
//            defer {
//                _ = memoryDeallocate(task: task, address: retAddr, size: 16)
//                _ = memoryDeallocate(task: task, address: stubAddr, size: 64)
//            }
//
//            // Fill return area with 0xAA so you can see if it changes
//            _ = memoryWrite(task: task, address: retAddr, bytes: [UInt8](repeating: 0xAA, count: 16))
//
//            // ---- Build x86_64 stub ----
//            // mov rax, <func>
//            // call rax
//            // mov rcx, <retAddr>
//            // movd dword ptr [rcx], xmm0        ; store float return
//            // mov [rcx+8], rax                  ; store integer return
//            // jmp $-2                           ; spin forever
//            var code: [UInt8] = []
//
//            func append(_ bytes: [UInt8]) { code.append(contentsOf: bytes) }
//            func le64(_ v: UInt64) -> [UInt8] {
//                withUnsafeBytes(of: v.littleEndian, Array.init)
//            }
//
//            append([0x48, 0xB8]); append(le64(UInt64(address)))     // mov rax, imm64
//            append([0xFF, 0xD0])                                    // call rax
//            append([0x48, 0xB9]); append(le64(UInt64(retAddr)))     // mov rcx, imm64
//            append([0x66, 0x0F, 0x7E, 0x01])                         // movd [rcx], xmm0
//            append([0x48, 0x89, 0x41, 0x08])                         // mov [rcx+8], rax
//            append([0xEB, 0xFE])                                    // jmp $
//
//            _ = memoryWrite(task: task, address: stubAddr, bytes: code)
//
//            // Make stub RX (no longer writable). If you don't have a helper, use mach_vm_protect.
//            _ = memoryProtect(task: task,
//                              address: stubAddr,
//                              size: 64,
//                              prot: VM_PROT_READ | VM_PROT_EXECUTE)
//
//            // ---- Configure thread state to start at stub ----
//            var call = original
//            call.pc = UInt64(stubAddr)
//
//            if arguments.count > 0 { call.arg0 = arguments[0] } // rdi
//            if arguments.count > 1 { call.arg1 = arguments[1] } // rsi
//            if arguments.count > 2 { call.arg2 = arguments[2] } // rdx
//            if arguments.count > 3 { call.arg3 = arguments[3] } // rcx (4th arg)
//
//            var tmp = call
//            guard setThreadState(&tmp, thread: thread) else {
//                print("[RemoteExecute] setThreadState X86_64 failed")
//                return nil
//            }
//
//            // Run briefly so stub can execute, then stop it (stub spins so it’s safe)
//            thread_resume(thread)
//            usleep(sleepUS)
//            thread_suspend(thread)
//
//            // Read stored return(s)
//            let retBytes = memoryRead(task: task, address: retAddr, numBytes: 16) ?? []
//            if retBytes.count == 16 {
//                let rax = retBytes[8..<16].withUnsafeBytes { $0.load(as: UInt64.self) }
//                // restore original thread state before returning
//                _ = setThreadState(&original, thread: thread)
//                return rax
//            } else {
//                _ = setThreadState(&original, thread: thread)
//                return nil
//            }
            ///---------------
            // INITIAL VERSION
            ///---------------
//        case .x86_64:
//            guard var original: ThreadStateX86 = getThreadState(ThreadStateX86.self, thread: thread) else {
//                print("[RemoteExecute] getThreadState X86_64 failed")
//                return nil
//            }
//
//            var call = original
//            call.pc = UInt64(address)
//            if arguments.count > 0 { call.arg0 = arguments[0] }
//            if arguments.count > 1 { call.arg1 = arguments[1] }
//            if arguments.count > 2 { call.arg2 = arguments[2] }
//            if arguments.count > 3 { call.arg3 = arguments[3] }
//
//            var tmp = call
//            guard setThreadState(&tmp, thread: thread) else {
//                print("[RemoteExecute] setThreadState X86_64 failed")
//                return nil
//            }
//
//            thread_resume(thread)
//            usleep(sleepUS)
//            thread_suspend(thread)
//
//            guard let final: ThreadStateX86 = getThreadState(ThreadStateX86.self, thread: thread) else {
//                print("[RemoteExecute] getThreadState X86_64 final failed")
//                _ = setThreadState(&original, thread: thread)
//                return nil
//            }
//
//            _ = setThreadState(&original, thread: thread)
//            return final.retVal
//        }
    }
}

//public enum RemoteExecute {
//
//    /// Executes a function in a remote task by hijacking a "worker" thread.
//    /// This is a minimal, sleep-based executor suitable for first validation.
//    ///
//    /// - Returns: Integer/boolean return value (retInt). For float-returning functions
//    ///            like `traceline`, validate via out-params (e.g. TraceResult.fraction)
//    ///            until XMM support is added.
//    public static func executeAndReturn(
//        task: mach_port_t,
//        function address: mach_vm_address_t,
//        arguments: [UInt64] = [],
//        sleepUS: useconds_t = 5_000
//    ) -> UInt64? {
//
//        guard let thread = ThreadSelector.selectWorkerThread(task: task) else { return nil }
//        guard var stateBox = makeThreadState(for: task) else { return nil }
//
//        // Suspend the worker while we hijack it
//        thread_suspend(thread)
//        defer { thread_resume(thread) }
//
//        switch stateBox {
//
//        case .arm64:
//            // 1) Capture original
//            guard var original: ThreadStateARM64 = getThreadState(ThreadStateARM64.self, thread: thread) else {
//                return nil
//            }
//
//            // 2) Setup call state
//            var call = original
//            call.pc = UInt64(address)
//
//            if arguments.count > 0 { call.arg0 = arguments[0] }
//            if arguments.count > 1 { call.arg1 = arguments[1] }
//            if arguments.count > 2 { call.arg2 = arguments[2] }
//            if arguments.count > 3 { call.arg3 = arguments[3] }
//
//            // NOTE: On ARM64, we are not setting LR here.
//            // For first validation (traceline), we only need the out-struct to update.
//            // A robust executor should set a trap stub and poll PC/LR.
//
//            // 3) Inject + run
//            guard setThreadState(&call, thread: thread) else { return nil }
//            thread_resume(thread)
//            usleep(sleepUS)
//            thread_suspend(thread)
//
//            // 4) Read final
//            guard let final: ThreadStateARM64 = getThreadState(ThreadStateARM64.self, thread: thread) else {
//                // Restore anyway
//                _ = setThreadState(&original, thread: thread)
//                return nil
//            }
//
//            // 5) Restore original
//            _ = setThreadState(&original, thread: thread)
//
//            return final.retInt
//
//        case .x86_64:
//            // 1) Capture original
//            guard var original: ThreadStateX86_64 = getThreadState(ThreadStateX86_64.self, thread: thread) else {
//                return nil
//            }
//
//            // 2) Setup call state
//            var call = original
//            call.pc = UInt64(address)
//
//            if arguments.count > 0 { call.arg0 = arguments[0] }
//            if arguments.count > 1 { call.arg1 = arguments[1] }
//            if arguments.count > 2 { call.arg2 = arguments[2] }
//            if arguments.count > 3 { call.arg3 = arguments[3] }
//
//            // NOTE: For first validation we are not pushing a return address.
//            // A robust implementation should push a known trap return and wait for it.
//
//            // 3) Inject + run
//            guard setThreadState(&call, thread: thread) else { return nil }
//            thread_resume(thread)
//            usleep(sleepUS)
//            thread_suspend(thread)
//
//            // 4) Read final
//            guard var final: ThreadStateX86_64 = getThreadState(ThreadStateX86_64.self, thread: thread) else {
//                _ = setThreadState(&original, thread: thread)
//                return nil
//            }
//
//            // 5) Restore original
//            _ = setThreadState(&original, thread: thread)
//
//            return final.retInt
//        }
//    }
}
