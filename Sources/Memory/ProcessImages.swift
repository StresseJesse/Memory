//
//  ProcessImages.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/25/25.
//

// Process/ProcessImages.swift
import Darwin
import MachO

// Process/ProcessImages.swift
import Darwin
import MachO
import os

final class ProcessImages: @unchecked Sendable {

    static let shared = ProcessImages()

    private var cachedMainAddress: mach_vm_address_t?
    private let queue = DispatchQueue(label: "process.images.cache")

    private init() {}

    func mainExecutableBase(task: mach_port_t) -> mach_vm_address_t? {
        queue.sync {
            if let cached = cachedMainAddress {
                return cached
            }

            guard let header = _dyld_get_image_header(0) else {
                return nil
            }

            let slide = _dyld_get_image_vmaddr_slide(0)

            let base = mach_vm_address_t(
                UInt(bitPattern: header) + UInt(slide)
            )

            cachedMainAddress = base
            return base
        }
    }
}

