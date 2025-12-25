//
//  RemotePointer.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/24/25.
//

import Darwin.Mach

public struct RemotePointer<T> {
    public let address: mach_vm_address_t
    public let task: mach_port_t

    public init(_ address: mach_vm_address_t, task: mach_port_t) {
        self.address = address
        self.task = task
    }

    public func read() -> T? {
        RemoteMemory(task: task).read(at: address)
    }

    public func write(_ value: T) -> Bool {
        RemoteMemory(task: task).write(value: value, to: address)
    }

    public var raw: mach_vm_address_t { address }
}
