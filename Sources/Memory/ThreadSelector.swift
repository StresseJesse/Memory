//
//  ThreadSelector.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/25/25.
//

import Darwin.Mach

enum ThreadSelector {

    /// Returns a background / idle worker thread suitable for hijacking
    static func selectWorkerThread(task: mach_port_t) -> thread_act_t? {
        var threads: thread_act_array_t?
        var count: mach_msg_type_number_t = 0

        guard task_threads(task, &threads, &count) == KERN_SUCCESS,
              let list = threads else { return nil }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: list)),
                vm_size_t(count) * vm_size_t(MemoryLayout<thread_act_t>.size)
            )
        }

        for i in 0..<Int(count) {
            let thread = list[i]

            var info = thread_basic_info()
            var infoCount = THREAD_BASIC_INFO_COUNT

            guard Mach.getThreadBasicInfo(
                thread,
                info: &info,
                count: &infoCount
            ) == KERN_SUCCESS else { continue }

            // Skip main / hot threads
            if info.run_state == TH_STATE_RUNNING { continue }
            if info.flags & TH_FLAGS_SWAPPED != 0 { continue }

            return thread
        }

        return nil
    }
}
