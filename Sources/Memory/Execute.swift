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
            
            guard Mach.allocate(task: task, size: 16, address: &retAddr) == KERN_SUCCESS,
                  Mach.allocate(task: task, size: 64, address: &stubAddr) == KERN_SUCCESS
            else {
                print("[RemoteExecute] allocate stub/ret failed")
                return nil
            }
            
            defer {
                Mach.deallocate(task: task, address: retAddr, size: 16)
                Mach.deallocate(task: task, address: stubAddr, size: 64)
            }
            
            // Fill return area with 0xAA so you can see if it changes
            let fill = [UInt8](repeating: 0xAA, count: 16)
            let krFill = fill.withUnsafeBytes { raw -> kern_return_t in
                Mach.write(task: task,
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
                Mach.write(task: task,
                           address: stubAddr,
                           buffer: raw.baseAddress!,
                           count: raw.count)
            }
            guard krStubWrite == KERN_SUCCESS else {
                print("[RemoteExecute] stub write failed:", krStubWrite)
                return nil
            }
            
            // Make stub RX (no longer writable)
            let krProt = Mach.protect(task: task,
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
                Mach.readOverwrite(task: task,
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
        }
    }
}
