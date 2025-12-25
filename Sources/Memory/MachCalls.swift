//
//  MachCalls.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/24/25.
//

//
//  MachCalls.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/25/25.
//

import Darwin.Mach

/// Low-level wrappers around Mach VM APIs.
public enum MachCalls {

    // MARK: - Memory Read

    @inline(__always)
    public static func readOverwrite(
        task: mach_port_t,
        remote: mach_vm_address_t,
        size: mach_vm_size_t,
        local: mach_vm_address_t,
        outSize: inout mach_vm_size_t
    ) -> kern_return_t {
        mach_vm_read_overwrite(task, remote, size, local, &outSize)
    }

    @inline(__always)
    public static func read(
        task: mach_port_t,
        address: mach_vm_address_t,
        size: mach_vm_size_t,
        data: inout vm_offset_t,
        count: inout mach_msg_type_number_t
    ) -> kern_return_t {
        mach_vm_read(task, address, size, &data, &count)
    }

    // MARK: - Memory Write

    @inline(__always)
    public static func write(
        task: mach_port_t,
        address: mach_vm_address_t,
        buffer: UnsafeRawPointer,
        count: Int
    ) -> kern_return_t {
        mach_vm_write(
            task,
            address,
            vm_offset_t(UInt(bitPattern: buffer)),
            mach_msg_type_number_t(count)
        )
    }

    // MARK: - Memory Protection

    @inline(__always)
    public static func protect(
        task: mach_port_t,
        address: mach_vm_address_t,
        size: mach_vm_size_t,
        protection: vm_prot_t
    ) -> kern_return_t {
        mach_vm_protect(task, address, size, 0, protection)
    }

    // MARK: - Memory Allocation

    @inline(__always)
    public static func allocate(
        task: mach_port_t,
        size: mach_vm_size_t,
        address: inout mach_vm_address_t
    ) -> kern_return_t {
        mach_vm_allocate(task, &address, size, VM_FLAGS_ANYWHERE)
    }

    @inline(__always)
    public static func deallocate(
        task: mach_port_t,
        address: mach_vm_address_t,
        size: mach_vm_size_t
    ) {
        mach_vm_deallocate(task, address, size)
    }

    // MARK: - VM Region Info

    @inline(__always)
    public static func region(
        task: mach_port_t,
        address: inout mach_vm_address_t,
        size: inout mach_vm_size_t,
        info: UnsafeMutablePointer<vm_region_basic_info_64>,
        infoCount: inout mach_msg_type_number_t,
        objectName: inout mach_port_t
    ) -> kern_return_t {
        info.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
            mach_vm_region(
                task,
                &address,
                &size,
                VM_REGION_BASIC_INFO_64,
                vm_region_info_t($0),
                &infoCount,
                &objectName
            )
        }
    }

    /// High-level, safe wrapper returning region info as a tuple.
    /// Returns `nil` if the call fails.
    @inline(__always)
    public static func regionInfo(
        task: mach_port_t,
        address: mach_vm_address_t
    ) -> (address: mach_vm_address_t, size: mach_vm_size_t, info: vm_region_basic_info_64)? {

        var info = vm_region_basic_info_64()
        var regionAddress = address
        var regionSize: mach_vm_size_t = 0
        var infoCount = mach_msg_type_number_t(
            UInt32(MemoryLayout<vm_region_basic_info_64>.size / MemoryLayout<integer_t>.size)
        )
        var objectName: mach_port_t = 0

        let kr = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                mach_vm_region(
                    task,
                    &regionAddress,
                    &regionSize,
                    VM_REGION_BASIC_INFO_64,
                    vm_region_info_t($0),
                    &infoCount,
                    &objectName
                )
            }
        }

        guard kr == KERN_SUCCESS else { return nil }
        return (regionAddress, regionSize, info)
    }

    // MARK: - Convenience Throwing Versions

    /// Throws if mach_vm_write fails.
    @inline(__always)
    public static func writeOrThrow(
        task: mach_port_t,
        address: mach_vm_address_t,
        buffer: UnsafeRawPointer,
        count: Int
    ) throws {
        let kr = write(task: task, address: address, buffer: buffer, count: count)
        if kr != KERN_SUCCESS {
            throw MachError(kr)
        }
    }

    /// Throws if mach_vm_protect fails.
    @inline(__always)
    public static func protectOrThrow(
        task: mach_port_t,
        address: mach_vm_address_t,
        size: mach_vm_size_t,
        protection: vm_prot_t
    ) throws {
        let kr = protect(task: task, address: address, size: size, protection: protection)
        if kr != KERN_SUCCESS {
            throw MachError(kr)
        }
    }

    // MARK: - Error Helper

    public struct MachError: Error, CustomStringConvertible {
        public let code: kern_return_t
        public var description: String {
            let msg = mach_error_string(code).map { String(cString: $0) } ?? "Unknown error"
            return "MachError \(code): \(msg)"
        }
        public init(_ code: kern_return_t) { self.code = code }
    }
}
