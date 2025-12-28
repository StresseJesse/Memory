//
//  Untitled.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/25/25.
//

import Darwin.Mach

@inline(__always)
public func withIntegerBuffer<T, R>(
    of value: inout T,
    count: mach_msg_type_number_t,
    _ body: (UnsafeMutablePointer<integer_t>) -> R
) -> R {
    return withUnsafeMutablePointer(to: &value) { p in
        p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ip in
            body(ip)
        }
    }
}
