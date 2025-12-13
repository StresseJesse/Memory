//
//  Buffer.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/12/25.
//

import Foundation
import AppKit

class Buffer {
    let pointer: UnsafeRawPointer
    let dataCount: mach_msg_type_number_t

    init?(address: mach_vm_address_t,
          size: mach_vm_size_t,
          taskPort: mach_port_t) {
        var data: vm_offset_t = 0
        var dataCount: mach_msg_type_number_t = 0
        
        let kr = mach_vm_read(
            taskPort,
            address,
            size,
            &data,
            &dataCount
        )

        guard kr == KERN_SUCCESS, dataCount > 0,
            let rawPtr = UnsafeRawPointer(bitPattern: UInt(data)) else {
            // If creation fails, deallocate immediately if data was partially obtained
            if data != 0 {
                 mach_vm_deallocate(mach_task_self_,
                                    mach_vm_address_t(data),
                                    mach_vm_size_t(dataCount))
            }
            return nil
        }

        self.pointer = rawPtr
        self.dataCount = dataCount
    }

    // This is called automatically when the RemoteMemoryBuffer instance is no longer used.
    deinit {
        // Deallocate the kernel-allocated memory using mach_task_self_
        mach_vm_deallocate(
            mach_task_self_,
            mach_vm_address_t(UInt(bitPattern: pointer)),
            mach_vm_size_t(dataCount)
        )
    }
}
