//
//  ThreadStateFactory.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/27/25.
//


import Darwin.Mach

public enum ThreadStateBox {
    case arm64(ThreadStateArm)
    case x86_64(ThreadStateX86)
}

public func makeThreadState(for task: mach_port_t) -> ThreadStateBox? {
    switch detectTargetArch(task: task) {
    case .arm64:
        return .arm64(ThreadStateArm())
    case .x86_64:
        return .x86_64(ThreadStateX86())
    default:
        return nil
    }
}
