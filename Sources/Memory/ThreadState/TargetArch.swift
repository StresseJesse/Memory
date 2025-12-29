//
//  TargetArch.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/27/25.
//
import MachO
import Darwin.Mach

public enum TargetArch {
    case arm64
    case x86_64
}

/// Detects architecture of the *target task* by inspecting its Mach-O header.
public func detectTargetArch(task: mach_port_t) -> TargetArch? {
    var regions = Regions(port: task)

    guard let region = regions.mainExecutable(),
          let header: mach_header_64 = region.read(at: region.address)
    else { return nil }

    switch header.cputype {
    case CPU_TYPE_ARM64:
        return .arm64
    case CPU_TYPE_X86_64:
        return .x86_64
    default:
        return nil
    }
}
