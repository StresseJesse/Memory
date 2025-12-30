//
//  MachRegion.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/12/25.
//

import Foundation
import Darwin.Mach
import MachO

public final class Region {

    public let address: mach_vm_address_t
    public let size: mach_vm_size_t
    public let info: vm_region_basic_info_64
    public let task: mach_port_t

    private var cachedProtection: vm_prot_t?
    private let memory: Memory

    // MARK: - Mach-O cache (per Region instance)

    private var machoDidCompute: Bool = false
    private var machoMagic: UInt32? = nil
    private var machoHeader: mach_header_64? = nil
    private var machoIsMachO: Bool = false

    public init(
        address: mach_vm_address_t,
        size: mach_vm_size_t,
        info: vm_region_basic_info_64,
        task: mach_port_t,
        useSnapshot: Bool = false
    ) {
        self.address = address
        self.size = size
        self.info = info
        self.task = task
        self.cachedProtection = info.protection
        self.memory = useSnapshot
            ? (Memory(task: task, address: address, size: size) ?? Memory(task: task))
            : Memory(task: task)
    }

    // MARK: - Protection flags

    public var isReadable: Bool { (info.protection & VM_PROT_READ) != 0 }
    public var isWritable: Bool { (info.protection & VM_PROT_WRITE) != 0 }
    public var isExecutable: Bool { (info.protection & VM_PROT_EXECUTE) != 0 }

    // MARK: - Mach-O helpers (base address implied)

    /// First 4 bytes at region base (cached).
    public var magic: UInt32? {
        ensureMachOCache()
        return machoMagic
    }

    /// mach_header_64 at region base (cached if Mach-O 64).
    public var header: mach_header_64? {
        ensureMachOCache()
        return machoHeader
    }

    /// True if region base looks like a 64-bit Mach-O header (cached).
    public var isMachO: Bool {
        ensureMachOCache()
        return machoIsMachO
    }

    /// CPU type from Mach-O header (cached).
    public var cpuType: cpu_type_t? {
        ensureMachOCache()
        return machoHeader?.cputype
    }

    /// CPU subtype from Mach-O header (cached).
    public var cpuSubtype: cpu_subtype_t? {
        ensureMachOCache()
        return machoHeader?.cpusubtype
    }

    /// If you ever need to refresh the header (usually not).
    public func invalidateMachOCache() {
        machoDidCompute = false
        machoMagic = nil
        machoHeader = nil
        machoIsMachO = false
    }

    @inline(__always)
    private func ensureMachOCache() {
        if machoDidCompute { return }
        machoDidCompute = true

        guard isReadable else { return }

        guard let m: UInt32 = read(at: address) else { return }
        machoMagic = m

        guard m == MH_MAGIC_64 || m == MH_CIGAM_64 else { return }
        machoIsMachO = true

        machoHeader = (read(at: address) as mach_header_64?)
    }

    // MARK: - Reading

    public func read<T>(at address: mach_vm_address_t) -> T? {
        memory.read(at: address)
    }

    public func read(at address: mach_vm_address_t, numBytes: Int) -> [UInt8]? {
        memory.read(at: address, numBytes: numBytes)
    }

    // MARK: - Writing

    /// Write automatically handles temporary protection changes if necessary
    @discardableResult
    public func write<T>(value: T, to address: mach_vm_address_t) -> Bool {
        var val = value
        let bytes = withUnsafeBytes(of: &val) { Array($0) }
        return write(bytes: bytes, to: address)
    }

    @discardableResult
    public func write(bytes: [UInt8], to address: mach_vm_address_t) -> Bool {
        // Try direct write first
        if memory.write(bytes: bytes, to: address) {
            return true
        }

        // Fallback: temporarily make page writable
        let original = cachedProtection ?? info.protection
        let tempProt: vm_prot_t = VM_PROT_READ | VM_PROT_WRITE

        guard protect(address: address, size: mach_vm_size_t(bytes.count), newProtection: tempProt) else {
            return false
        }

        let success = memory.write(bytes: bytes, to: address)
        _ = protect(address: address, size: mach_vm_size_t(bytes.count), newProtection: original)

        return success
    }

    /// Explicit safeWrite in case you know you need it
    @discardableResult
    public func safeWrite<T>(value: T, to address: mach_vm_address_t) -> Bool {
        var val = value
        let bytes = withUnsafeBytes(of: &val) { Array($0) }
        return safeWrite(bytes: bytes, to: address)
    }

    @discardableResult
    public func safeWrite(bytes: [UInt8], to address: mach_vm_address_t) -> Bool {
        let original = cachedProtection ?? info.protection
        let tempProt: vm_prot_t = VM_PROT_READ | VM_PROT_WRITE

        guard protect(address: address, size: mach_vm_size_t(bytes.count), newProtection: tempProt) else {
            return false
        }

        let success = memory.write(bytes: bytes, to: address)
        _ = protect(address: address, size: mach_vm_size_t(bytes.count), newProtection: original)
        return success
    }

    // MARK: - Memory Protection

    @discardableResult
    public func protect(address: mach_vm_address_t, size: mach_vm_size_t, newProtection: vm_prot_t) -> Bool {
        guard Mach.protect(task: task, address: address, size: size, protection: newProtection) == KERN_SUCCESS else {
            return false
        }
        cachedProtection = newProtection
        return true
    }

    // MARK: - Allocation / Deallocation

    public func allocate(size: mach_vm_size_t) -> mach_vm_address_t? {
        var addr: mach_vm_address_t = 0
        guard Mach.allocate(task: task, size: size, address: &addr) == KERN_SUCCESS else { return nil }
        return addr
    }

    public func allocate(size: Int) -> mach_vm_address_t? {
        allocate(size: mach_vm_size_t(size))
    }

    public func deallocate(at address: mach_vm_address_t, size: mach_vm_size_t) {
        Mach.deallocate(task: task, address: address, size: size)
    }

    public func deallocate(at address: mach_vm_address_t, size: Int) {
        Mach.deallocate(task: task, address: address, size: mach_vm_size_t(size))
    }

    // MARK: - Code Cave

    public func findCodeCave(length: Int) -> mach_vm_address_t? {
        guard length > 0, size >= length else { return nil }
        guard let buffer = read(at: address, numBytes: Int(size)) else { return nil }

        var caveStart: mach_vm_address_t? = nil
        var caveLen: Int = 0

        for i in 0..<buffer.count {
            let b = buffer[i]
            if b == 0x00 || b == 0x90 {
                if caveLen == 0 { caveStart = address + mach_vm_address_t(i) }
                caveLen += 1
                if caveLen >= length { return caveStart }
            } else {
                caveLen = 0
                caveStart = nil
            }
        }

        return nil
    }
}
