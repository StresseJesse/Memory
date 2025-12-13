//  Memory.swift
//  Hacks
//
//  Created by Jesse Ramsey on 12/9/25.
//

import Foundation
import AppKit

// MARK: - MachRegionIterator
struct Regions: Sequence, IteratorProtocol {
    private let taskPort: mach_port_t
    private var nextAddress: mach_vm_address_t = 1
    private let infoSize: mach_msg_type_number_t
    private var filter: ((Region) -> Bool)?

    init(taskPort: mach_port_t, filter: ((Region) -> Bool)? = nil) {
        self.taskPort = taskPort
        self.infoSize = mach_msg_type_number_t(
            UInt32(MemoryLayout<vm_region_basic_info_64>.size / MemoryLayout<integer_t>.size)
        )
        self.filter = filter
    }

    mutating func next() -> Region? {
        guard taskPort != MACH_PORT_NULL else { return nil }

        while true {
            var info = vm_region_basic_info_64()
            var regionAddress = nextAddress
            var regionSize: mach_vm_size_t = 0
            var infoCount = infoSize
            var objectName: mach_port_t = 0

            let kr = withUnsafeMutablePointer(to: &info) { infoPtr in
                infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(infoSize)) {
                    mach_vm_region(taskPort,
                                   &regionAddress,
                                   &regionSize,
                                   VM_REGION_BASIC_INFO_64,
                                   vm_region_info_t($0),
                                   &infoCount,
                                   &objectName)
                }
            }

            guard kr == KERN_SUCCESS else { return nil }

            nextAddress = regionAddress + regionSize
            let region = Region(address: regionAddress,
                                    size: regionSize,
                                    info: info,
                                    taskPort: taskPort)

            if let filter = filter {
                if filter(region) {
                    return region
                }
            } else {
                return region
            }
        }
    }

    // MARK: - Lazy Filter Methods
    func filterReadable() -> Regions {
        Regions(taskPort: taskPort) { region in
            (region.info.protection & VM_PROT_READ) != 0
        }
    }

    func filterExecutable() -> Regions {
        Regions(taskPort: taskPort) { region in
            (region.info.protection & VM_PROT_EXECUTE) != 0
        }
    }
    
    func mainExecutable() -> Region? {
        for region in self.filterReadable() {
            if region.isMainExecutable {
                let arch = region.cpuType!
                print("arch: \(arch)")
                return region
            }
        }
        return nil
    }
}
