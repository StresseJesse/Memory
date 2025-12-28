//
//  ThreadStateProtocol.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/27/25.
//

import Darwin.Mach

/// Minimal ABI surface required by RemoteExecute.
/// This is keyed to *target task architecture*, not injector architecture.


public protocol AnyThreadState {
    init()
    static var flavor: thread_state_flavor_t { get } // ✅ Int32
    static var count: mach_msg_type_number_t { get }
}

//protocol AnyThreadState {
//    static var flavor: thread_flavor_t { get }
//    static var count: mach_msg_type_number_t { get }
//
//    var pc: UInt64 { get set }
//    var sp: UInt64 { get set }
//
//    var arg0: UInt64 { get set }
//    var arg1: UInt64 { get set }
//    var arg2: UInt64 { get set }
//    var arg3: UInt64 { get set }
//
//    var retInt: UInt64 { get }
//}

