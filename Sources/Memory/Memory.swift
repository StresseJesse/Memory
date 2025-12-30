//
//  RemoteMemory.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/24/25.
//

import Darwin.Mach
import Foundation

/// Represents remote memory in a target task, supporting both snapshot and direct-access modes
public final class Memory {

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

        let kr = Mach.read(task: task, address: address, size: size, data: &data, count: &dataCount)
        guard kr == KERN_SUCCESS, let rawPtr = UnsafeRawPointer(bitPattern: UInt(data)), dataCount > 0 else { return nil }

        self.pointer = rawPtr
        self.count = dataCount
        self.baseAddress = address
    }

    deinit {
        if let ptr = pointer, let count = count {
            Mach.deallocate(task: task, address: mach_vm_address_t(UInt(bitPattern: ptr)), size: mach_vm_size_t(count))
        }
    }

    // MARK: - Read

    /// Reads a single Swift value of type T from remote memory
    public func read<T>(at address: mach_vm_address_t) -> T? {
        var value = T.self   // (just to reference type; not used)

        var out = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { out.deallocate() }

        var outSize: mach_vm_size_t = 0
        let size = MemoryLayout<T>.size

        let kr = Mach.readOverwrite(
            task: task,
            remote: address,
            size: mach_vm_size_t(size),
            local: mach_vm_address_t(UInt(bitPattern: out)),
            outSize: &outSize
        )

        guard kr == KERN_SUCCESS, outSize == size else { return nil }
        return out.pointee
    }


    /// Reads a specific number of bytes from a remote address
    public func read(at address: mach_vm_address_t, numBytes: Int) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: numBytes)
        var outSize: mach_vm_size_t = 0

        let kr = buffer.withUnsafeMutableBytes { ptr -> kern_return_t in
            guard let base = ptr.baseAddress else { return KERN_INVALID_ADDRESS }
            return Mach.readOverwrite(
                task: task,
                remote: address,
                size: mach_vm_size_t(numBytes),
                local: mach_vm_address_t(UInt(bitPattern: base)),
                outSize: &outSize
            )
        }

        guard kr == KERN_SUCCESS, outSize == numBytes else { return nil }
        return buffer
    }

    // MARK: - Write / Protect / Allocate / Deallocate

    public func write(bytes: [UInt8], to address: mach_vm_address_t) -> Bool {
        return Mach.write(task: task, address: address, buffer: bytes, count: bytes.count) == KERN_SUCCESS
    }

    public func write<T>(value: T, to address: mach_vm_address_t) -> Bool {
        var val = value
        return withUnsafePointer(to: &val) { ptr in
            Mach.write(task: task, address: address, buffer: ptr, count: MemoryLayout<T>.size) == KERN_SUCCESS
        }
    }

    @discardableResult
    public func protect(address: mach_vm_address_t, size: mach_vm_size_t, newProtection: vm_prot_t) -> Bool {
        return Mach.protect(task: task, address: address, size: size, protection: newProtection) == KERN_SUCCESS
    }

    public func allocate(size: mach_vm_size_t) -> mach_vm_address_t? {
        var remoteAddress: mach_vm_address_t = 0
        let kr = Mach.allocate(task: task, size: size, address: &remoteAddress)
        return kr == KERN_SUCCESS ? remoteAddress : nil
    }
    
    // just for convenience and the ability to use MemoryLayout<T>.size
    public func allocate(size: Int) -> mach_vm_address_t? {
        return allocate(size: mach_vm_size_t(size))
    }

    public func deallocate(address: mach_vm_address_t, size: mach_vm_size_t) {
        Mach.deallocate(task: task, address: address, size: size)
    }
}
