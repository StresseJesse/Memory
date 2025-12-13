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
    let taskPort: mach_port_t

    // Read from memory
    func read<T>(at address: mach_vm_address_t) -> T? {
        let size = MemoryLayout<T>.size
        var outSize: mach_vm_size_t = 0

        let buffer = UnsafeMutableRawPointer
            .allocate(byteCount: size,
                      alignment: MemoryLayout<T>.alignment)
        defer { buffer.deallocate() }

        let kr = mach_vm_read_overwrite(
            taskPort,
            address,
            UInt64(size),
            mach_vm_address_t(UInt(bitPattern: buffer)),
            &outSize
        )

        guard kr == KERN_SUCCESS, outSize == size else { return nil }

        return buffer.load(as: T.self)
    }

    // Read Mach-O header using the read func
    func readHeader() -> mach_header_64? {
        return read(at: address)
    }

    // Read first 4 bytes (magic) using the read func
    func readMagic() -> UInt32? {
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
    func findCodeCave(length: mach_vm_size_t) -> mach_vm_address_t? {
        guard length > 0, size >= length else { return nil }
        guard let buffer = Buffer(address: address, size: size, taskPort: taskPort) else { return nil }

        
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
