//
//  MachRegion.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/12/25.
//

import Foundation
import AppKit


// MARK: - Mach Region Representation
public struct Region {
    let address: mach_vm_address_t
    let size: mach_vm_size_t
    let info: vm_region_basic_info_64
    let task: mach_port_t

    // Read from memory
    public func read<T>(at address: mach_vm_address_t) -> T? {
        let size = MemoryLayout<T>.size
        var outSize: mach_vm_size_t = 0

        let buffer = UnsafeMutableRawPointer
            .allocate(byteCount: size,
                      alignment: MemoryLayout<T>.alignment)
        defer { buffer.deallocate() }

        let kr = mach_vm_read_overwrite(
            task,
            address,
            UInt64(size),
            mach_vm_address_t(UInt(bitPattern: buffer)),
            &outSize
        )

        guard kr == KERN_SUCCESS, outSize == size else { return nil }

        return buffer.load(as: T.self)
    }
    // Read a specific number of bytes
    public func read(at address: mach_vm_address_t, bytes: Int) -> [UInt8]? {
        print("reading \(bytes) bytes from \(address)")
        var buffer = [UInt8](repeating: 0, count: bytes)
        var outSize: mach_vm_size_t = 0

        let kr = buffer.withUnsafeMutableBytes { ptr -> kern_return_t in
            mach_vm_read_overwrite(task,
                                   address,
                                   UInt64(bytes),
                                   mach_vm_address_t(UInt(bitPattern: ptr.baseAddress!)),
                                   &outSize)
        }

        guard kr == KERN_SUCCESS, outSize == bytes else { return nil }
        return buffer
    }
    
    /// A specialized write function for Rosetta 2.
    /// It captures current permissions, elevates them to allow writing,
    /// performs the write, and restores permissions to trigger re-translation.
    public func safeWrite(bytes: [UInt8], to remoteAddress: mach_vm_address_t) -> Bool {
        // suspend process
        task_suspend(task)
        // 1. Get current permissions (using the info stored in this Region)
        // Note: If writing to a sub-range, you might want to call mach_vm_region again,
        // but for most cases, self.info.protection is the source of truth for this block.
        let originalProtection = self.info.protection
        
        // 2. Ensure we have Write + Copy permissions
        // VM_PROT_COPY is vital when writing to executable pages to handle COW (Copy-on-Write)
        let tempProtection = VM_PROT_READ | VM_PROT_WRITE
        
        guard protect(address: remoteAddress, size: mach_vm_size_t(bytes.count), newProtection: tempProtection) else {
            return false
        }
        
        // 3. Perform the actual write
        let writeSuccess = self.write(bytes: bytes, to: remoteAddress)
        
        // 4. Restore original permissions
        // Transitioning BACK to Execute (if it was executable) is the "kick"
        // Rosetta 2 needs to invalidate its ARM64 instruction cache.
        let restoreSuccess = protect(address: remoteAddress,
                                     size: mach_vm_size_t(bytes.count),
                                     newProtection: originalProtection)
    
        // resume process
        task_resume(task)
        return writeSuccess && restoreSuccess
    }

    /// Generic version of safeWrite for single values
    public func safeWrite<T>(value: T, to remoteAddress: mach_vm_address_t) -> Bool {
        var val = value
        let bytes = withUnsafeBytes(of: &val) { Array($0) }
        return safeWrite(bytes: bytes, to: remoteAddress)
    }
    
    private func performMachWrite(
        remoteAddress: mach_vm_address_t,
        localBuffer: UnsafeRawPointer,
        byteCount: Int
    ) -> Bool {
        let kr = mach_vm_write(
            task,
            remoteAddress,
            vm_offset_t(UInt(bitPattern: localBuffer)),
            mach_msg_type_number_t(byteCount)
        )

        if kr != KERN_SUCCESS {
            let err = String(cString: mach_error_string(kr), encoding: .ascii) ?? "Unknown Error"
            print("Failed to write \(byteCount) bytes at \(String(format: "%#llx", remoteAddress)): KERN error \(kr) (\(err))")
        }

        return kr == KERN_SUCCESS
    }

    // MARK: - Public Write Functions

    /// Public function to write a single Swift value (e.g., Int, Float, Struct).
    public func write<T>(value: T, to address: mach_vm_address_t) -> Bool {
        var val = value // Make a local mutable copy

        // Use withUnsafePointer to access the raw memory of the single value T
        return withUnsafePointer(to: &val) { ptr in
            // Delegate the actual write operation to the common function
            performMachWrite(
                remoteAddress: address,
                localBuffer: UnsafeRawPointer(ptr),
                byteCount: MemoryLayout<T>.size
            )
        }
    }
    
    /// Public function to write an array of bytes ([UInt8] or Data).
    public func write(bytes: [UInt8], to address: mach_vm_address_t) -> Bool {
        // Use withUnsafeBytes on the array to access its raw memory buffer
        return bytes.withUnsafeBytes { bufferPointer in
            guard let baseAddress = bufferPointer.baseAddress else { return false }
            
            // Delegate the actual write operation to the common function
            return performMachWrite(
                remoteAddress: address,
                localBuffer: baseAddress,
                byteCount: bytes.count
            )
        }
    }
    /// Changes the memory protection for a range of addresses within the remote task.
    /// - Returns: True if successful.
    public func protect(address: mach_vm_address_t, size: mach_vm_size_t, newProtection: vm_prot_t) -> Bool {
        let kr = mach_vm_protect(
            task,
            address,
            size,
            // 'false' means we are NOT extending the maximum permissions
            boolean_t(truncating: false),
            newProtection
        )
        if kr != KERN_SUCCESS {
            let err = String(cString: mach_error_string(kr), encoding: .ascii) ?? "Unknown Error"
            print("Failed to change memory protection at \(String(format: "%#llx", address)): KERN error \(kr) (\(err))")
        }
        return kr == KERN_SUCCESS
    }
    
    /// Allocates memory in the target process.
    /// - Parameter size: The number of bytes to allocate.
    /// - Returns: The remote memory address, or nil if the allocation failed.
    public func allocate(size: Int) -> mach_vm_address_t? {
        var remoteAddress: mach_vm_address_t = 0
        let machSize = mach_vm_size_t(size)
        
        // VM_FLAGS_ANYWHERE tells the kernel to find any available address
        let kr = mach_vm_allocate(task, &remoteAddress, machSize, VM_FLAGS_ANYWHERE)
        
        guard kr == KERN_SUCCESS else {
            print("Failed to allocate remote memory: \(kr)")
            return nil
        }
        
        return remoteAddress
    }
    
    /// Frees memory previously allocated in the target process.
    /// - Parameters:
    ///   - address: The remote address to free.
    ///   - size: The size of the allocated block.
    public func deallocate(at address: mach_vm_address_t, size: Int) {
        _ = mach_vm_deallocate(self.task, address, mach_vm_size_t(size))
    }
    
    public func executeAndReturn(at address: mach_vm_address_t, arguments: [UInt64]) -> UInt64? {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        
        // 1. Get the list of threads
        let kr = task_threads(task, &threadList, &threadCount)
        guard kr == KERN_SUCCESS, let threads = threadList, threadCount > 0 else { return nil }
        
        // 2. Pick a thread to hijack (e.g., the first one)
        // FIX: 'threads' is a pointer; we access index 0 to get a single 'thread_t'
        let targetThread = threads[0]
        
        // Deallocate the thread list after we've picked our target to avoid leaks
        defer {
            let size = threadCount * mach_msg_type_number_t(MemoryLayout<thread_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(size))
        }

        thread_suspend(targetThread)
        
        var state = ThreadState()
        var stateCount = THREAD_STATE_COUNT
        
        // 3. Get and Set State using the single 'targetThread' port
        let getKr = withUnsafeMutablePointer(to: &state.raw) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(stateCount)) {
                thread_get_state(targetThread, THREAD_STATE_FLAVOR, $0, &stateCount)
            }
        }
        
        guard getKr == KERN_SUCCESS else { thread_resume(targetThread); return nil }

        state.pc = UInt64(address)
        if arguments.count > 0 { state.arg0 = arguments[0] }
        if arguments.count > 1 { state.arg1 = arguments[1] }
        if arguments.count > 2 { state.arg2 = arguments[2] }
        
        let setKr = withUnsafeMutablePointer(to: &state.raw) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(stateCount)) {
                thread_set_state(targetThread, THREAD_STATE_FLAVOR, $0, stateCount)
            }
        }
        
        if setKr == KERN_SUCCESS {
            thread_resume(targetThread)
            
            var count = 0
            // Polling loop logic...
            while true {
                count += 1
                print("[DEBUG] Polling... (\(count))")
                usleep(500)
                thread_suspend(targetThread)
                _ = withUnsafeMutablePointer(to: &state.raw) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: Int(stateCount)) {
                        thread_get_state(targetThread, THREAD_STATE_FLAVOR, $0, &stateCount)
                    }
                }
                if state.pc != UInt64(address) { break }
                thread_resume(targetThread)
            }
        }
        
        let result = state.retVal
        thread_resume(targetThread)
        return result
    }


    // Read Mach-O header using the read func
    public func readHeader() -> mach_header_64? {
        return read(at: address)
    }

    // Read first 4 bytes (magic) using the read func
    public func readMagic() -> UInt32? {
        return read(at: address)
    }

    // Check if region starts with a valid Mach-O magic number
    var isMachO: Bool {
        guard let magic = readMagic() else { return false }
        let validMagics: [UInt32] = [MH_MAGIC, MH_CIGAM, MH_MAGIC_64, MH_CIGAM_64]
        return validMagics.contains(magic)
    }

    // Check if this region is the main executable
    var isMainExecutable: Bool {
        guard isMachO, let header = readHeader() else { return false }
        return header.filetype == MH_EXECUTE
    }

    // Get CPU architecture
    var cpuType: cpu_type_t? {
        guard isMachO, let header = readHeader() else { return nil }
        return header.cputype
    }

    // Get CPU architecture as readable string
    var architecture: String? {
        guard let cpu = cpuType else { return nil }
        switch cpu {
        case CPU_TYPE_X86:       return "x86"
        case CPU_TYPE_X86_64:    return "x86_64"
        case CPU_TYPE_ARM:       return "arm"
        case CPU_TYPE_ARM64:     return "arm64"
        default:                 return "unknown (\(cpu))"
        }
    }

    // Check Architecture
    var isTranslated: Bool {
        guard let cpu = cpuType else { return false }
        // A simplistic heuristic: on Apple Silicon, x86_64 code regions are translated.
        // This placeholder can be refined using dyld info if needed.
        return cpu == CPU_TYPE_X86_64 || cpu == CPU_TYPE_X86
    }
    
    // Find a code cave using the read func
    public func findCodeCave<T: BinaryInteger>(length: T) -> mach_vm_address_t? {
        let bitLength = mach_vm_size_t(length)
        guard length > 0, size >= length else { return nil }
        guard let buffer = Buffer(address: address, size: size, taskPort: task) else { return nil }

        
        let bytes = buffer.pointer.bindMemory(to: UInt8.self, capacity: Int(buffer.dataCount))
        let dataCount = buffer.dataCount

        var caveStart: mach_vm_address_t? = nil
        var caveLen: mach_vm_size_t = 0

        for i in 0..<mach_vm_size_t(dataCount) {
            let b = bytes[Int(i)]

            if b == 0x00 || b == 0x90 {          // NULL or NOP
                if caveLen == 0 {
                    caveStart = address + i
                }
                caveLen += 1

                if caveLen >= length {
                    return caveStart
                }
            } else {
                caveStart = nil
                caveLen = 0
            }
        }

        return nil
    }
}
