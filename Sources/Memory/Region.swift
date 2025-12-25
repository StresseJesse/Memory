//
//  MachRegion.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/12/25.
//

import Foundation
import Darwin.Mach

public class Region {
    public let address: mach_vm_address_t
    public let size: mach_vm_size_t
    public let info: vm_region_basic_info_64
    public let task: mach_port_t

    private var cachedProtection: vm_prot_t?
    private let memory: RemoteMemory

    public init(address: mach_vm_address_t,
                size: mach_vm_size_t,
                info: vm_region_basic_info_64,
                task: mach_port_t,
                useSnapshot: Bool = false) {
        self.address = address
        self.size = size
        self.info = info
        self.task = task
        self.cachedProtection = info.protection
        self.memory = useSnapshot ? (RemoteMemory(task: task, address: address, size: size) ?? RemoteMemory(task: task))
                                  : RemoteMemory(task: task)
    }

    public var isReadable: Bool { (info.protection & VM_PROT_READ) != 0 }
    public var isWritable: Bool { (info.protection & VM_PROT_WRITE) != 0 }
    public var isExecutable: Bool { (info.protection & VM_PROT_EXECUTE) != 0 }

    // MARK: - Reading

    public func read<T>(at address: mach_vm_address_t) -> T? {
        memory.read(at: address)
    }

    public func read(numBytes: Int, at address: mach_vm_address_t) -> [UInt8]? {
        memory.read(numBytes: numBytes, at: address)
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
        guard MachCalls.protect(task: task, address: address, size: size, protection: newProtection) == KERN_SUCCESS else {
            return false
        }
        cachedProtection = newProtection
        return true
    }

    // MARK: - Allocation / Deallocation

    public func allocate(size: mach_vm_size_t) -> mach_vm_address_t? {
        var addr: mach_vm_address_t = 0
        guard MachCalls.allocate(task: task, size: size, address: &addr) == KERN_SUCCESS else { return nil }
        return addr
    }

    public func deallocate(address: mach_vm_address_t, size: mach_vm_size_t) {
        MachCalls.deallocate(task: task, address: address, size: size)
    }

    // MARK: - Code Cave

    public func findCodeCave(length: Int) -> mach_vm_address_t? {
        guard length > 0, size >= length else { return nil }
        guard let buffer = read(numBytes: Int(size), at: address) else { return nil }

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
