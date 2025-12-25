//
//  RemoteMemory.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/24/25.
//

import Darwin.Mach
import Foundation

/// Represents remote memory in a target task, supporting both snapshot and direct-access modes
public final class RemoteMemory {

    public let task: mach_port_t

    /// Snapshot buffer (nil if direct access mode)
    public let pointer: UnsafeRawPointer?
    public let count: mach_msg_type_number_t?
    private let baseAddress: mach_vm_address_t?

    // MARK: - Initializers

    /// Direct access mode: reads happen directly from remote task
    public init(task: mach_port_t) {
        self.task = task
        self.pointer = nil
        self.count = nil
        self.baseAddress = nil
    }

    /// Snapshot mode: reads a remote memory region once
    public init?(task: mach_port_t, address: mach_vm_address_t, size: mach_vm_size_t) {
        self.task = task
        var data: vm_offset_t = 0
        var dataCount: mach_msg_type_number_t = 0

        let kr = MachCalls.read(task: task, address: address, size: size, data: &data, count: &dataCount)
        guard kr == KERN_SUCCESS, let rawPtr = UnsafeRawPointer(bitPattern: UInt(data)), dataCount > 0 else { return nil }

        self.pointer = rawPtr
        self.count = dataCount
        self.baseAddress = address
    }

    deinit {
        if let ptr = pointer, let count = count {
            MachCalls.deallocate(task: task, address: mach_vm_address_t(UInt(bitPattern: ptr)), size: mach_vm_size_t(count))
        }
    }

    // MARK: - Read

    /// Reads a single Swift value of type T from remote memory
    public func read<T>(at address: mach_vm_address_t) -> T? {
        var value: T = unsafeBitCast(0, to: T.self)
        let size = MemoryLayout<T>.size
        var outSize: mach_vm_size_t = 0

        let success = withUnsafeMutablePointer(to: &value) { ptr -> Bool in
            let kr = MachCalls.readOverwrite(task: task,
                                             remote: address,
                                             size: mach_vm_size_t(size),
                                             local: mach_vm_address_t(UInt(bitPattern: ptr)),
                                             outSize: &outSize)
            return kr == KERN_SUCCESS && outSize == size
        }

        return success ? value : nil
    }

    /// Reads a specific number of bytes from a remote address
    public func read(numBytes: Int, at address: mach_vm_address_t) -> [UInt8]? {
        if let ptr = pointer, let base = baseAddress, let count = count {
            let offset = Int(address - base)
            guard offset + numBytes <= count else { return nil }
            let buffer = ptr.advanced(by: offset).bindMemory(to: UInt8.self, capacity: numBytes)
            return Array(UnsafeBufferPointer(start: buffer, count: numBytes))
        }

        var buffer = [UInt8](repeating: 0, count: numBytes)
        var outSize: mach_vm_size_t = 0

        let success = buffer.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return false }
            let kr = MachCalls.readOverwrite(task: task,
                                             remote: address,
                                             size: mach_vm_size_t(numBytes),
                                             local: mach_vm_address_t(UInt(bitPattern: baseAddress)),
                                             outSize: &outSize)
            return kr == KERN_SUCCESS && outSize == numBytes
        }

        return success ? buffer : nil
    }

    // MARK: - Write / Protect / Allocate / Deallocate

    public func write(bytes: [UInt8], to address: mach_vm_address_t) -> Bool {
        return MachCalls.write(task: task, address: address, buffer: bytes, count: bytes.count) == KERN_SUCCESS
    }

    public func write<T>(value: T, to address: mach_vm_address_t) -> Bool {
        var val = value
        return withUnsafePointer(to: &val) { ptr in
            MachCalls.write(task: task, address: address, buffer: ptr, count: MemoryLayout<T>.size) == KERN_SUCCESS
        }
    }

    @discardableResult
    public func protect(address: mach_vm_address_t, size: mach_vm_size_t, newProtection: vm_prot_t) -> Bool {
        return MachCalls.protect(task: task, address: address, size: size, protection: newProtection) == KERN_SUCCESS
    }

    public func allocate(size: mach_vm_size_t) -> mach_vm_address_t? {
        var remoteAddress: mach_vm_address_t = 0
        let kr = MachCalls.allocate(task: task, size: size, address: &remoteAddress)
        return kr == KERN_SUCCESS ? remoteAddress : nil
    }

    public func deallocate(address: mach_vm_address_t, size: mach_vm_size_t) {
        MachCalls.deallocate(task: task, address: address, size: size)
    }
}
