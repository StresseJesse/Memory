//
//  RemoteBuffer.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/24/25.
//

import Darwin.Mach

public final class RemoteBuffer {
    public let pointer: UnsafeRawPointer
    public let count: mach_msg_type_number_t

    public init?(
        task: mach_port_t,
        address: mach_vm_address_t,
        size: mach_vm_size_t
    ) {
        var data: vm_offset_t = 0
        var count: mach_msg_type_number_t = 0

        let kr = MachCalls.read(
            task: task,
            address: address,
            size: size,
            data: &data,
            count: &count
        )

        guard kr == KERN_SUCCESS,
              count > 0,
              let ptr = UnsafeRawPointer(bitPattern: UInt(data))
        else {
            if data != 0 {
                MachCalls.deallocate(
                    task: mach_task_self_,
                    address: mach_vm_address_t(data),
                    size: mach_vm_size_t(count)
                )
            }
            return nil
        }

        self.pointer = ptr
        self.count = count
    }

    deinit {
        MachCalls.deallocate(
            task: mach_task_self_,
            address: mach_vm_address_t(UInt(bitPattern: pointer)),
            size: mach_vm_size_t(count)
        )
    }

    public func bytes() -> UnsafeBufferPointer<UInt8> {
        UnsafeBufferPointer(
            start: pointer.assumingMemoryBound(to: UInt8.self),
            count: Int(count)
        )
    }
}
