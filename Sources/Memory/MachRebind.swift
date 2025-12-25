//
//  Untitled.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/25/25.
//

import Darwin.Mach

@inline(__always)
func withIntegerBuffer<T, R>(
    of value: inout T,
    count: mach_msg_type_number_t,
    _ body: (UnsafeMutablePointer<integer_t>) -> R
) -> R {
    withUnsafeMutablePointer(to: &value) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            body($0)
        }
    }
}
