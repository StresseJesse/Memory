//
//  ThreadStateX64.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/27/25.
//

#if arch(x86_64)
import CMach
import Darwin.Mach
#else
import Darwin.Mach
#endif

public struct ThreadStateArm: AnyThreadState {
    public var raw = arm_thread_state64_t()
    public init() {}

    public static let flavor: thread_state_flavor_t =
        thread_state_flavor_t(ARM_THREAD_STATE64)

    public static let count: mach_msg_type_number_t =
        mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size)

    // Convenience accessors (same as before)
    public var pc: UInt64 { get { raw.__pc } set { raw.__pc = newValue } }
    public var sp: UInt64 { get { raw.__sp } set { raw.__sp = newValue } }
    public var lr: UInt64 { get { raw.__lr } set { raw.__lr = newValue } }

    public var retVal: UInt64 { raw.__x.0 }

    public var arg0: UInt64 { get { raw.__x.0 } set { raw.__x.0 = newValue } }
    public var arg1: UInt64 { get { raw.__x.1 } set { raw.__x.1 = newValue } }
    public var arg2: UInt64 { get { raw.__x.2 } set { raw.__x.2 = newValue } }
    public var arg3: UInt64 { get { raw.__x.3 } set { raw.__x.3 = newValue } }
    public var arg4: UInt64 { get { raw.__x.4 } set { raw.__x.4 = newValue } }
    public var arg5: UInt64 { get { raw.__x.5 } set { raw.__x.5 = newValue } }
    public var arg6: UInt64 { get { raw.__x.6 } set { raw.__x.6 = newValue } }
    public var arg7: UInt64 { get { raw.__x.7 } set { raw.__x.7 = newValue } }
}


func dumpArm64State(task: mach_port_t) {
    var threads: thread_act_array_t?
    var count: mach_msg_type_number_t = 0
    guard task_threads(task, &threads, &count) == KERN_SUCCESS, let threads else {
        print("task_threads failed")
        return
    }
    defer {
        vm_deallocate(
            mach_task_self_,
            vm_address_t(UInt(bitPattern: threads)),
            vm_size_t(count) * vm_size_t(MemoryLayout<thread_act_t>.stride)
        )
    }

    for i in 0..<Int(count) {
        let t = threads[i]

        var s = arm_thread_state64_t()
        var n = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size)

        let kr = withUnsafeMutablePointer(to: &s) { ptr in
            ptr.withMemoryRebound(to: UInt32.self, capacity: Int(n)) { u32 in
                thread_get_state(t, thread_state_flavor_t(ARM_THREAD_STATE64), u32, &n)
            }
        }

        if kr != KERN_SUCCESS {
            print("[\(i)] thread=\(t) ARM_THREAD_STATE64 failed kr=\(kr)")
            continue
        }

        print(String(format: "[%02d] thread=%u pc=%#llx sp=%#llx lr=%#llx cpsr=%#x",
                     i, t, s.__pc, s.__sp, s.__lr, s.__cpsr))

        // x0..x7 are often the most interesting (args/temps)
        print(String(format: "     x0=%#llx x1=%#llx x2=%#llx x3=%#llx",
                     s.__x.0, s.__x.1, s.__x.2, s.__x.3))
        print(String(format: "     x4=%#llx x5=%#llx x6=%#llx x7=%#llx",
                     s.__x.4, s.__x.5, s.__x.6, s.__x.7))
    }
}
