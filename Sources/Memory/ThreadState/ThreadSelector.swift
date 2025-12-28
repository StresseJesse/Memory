//
//  ThreadSelector.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/25/25.
//

import Darwin.Mach

public enum ThreadSelector {

    /// Picks a thread we can successfully read state from (robust).
    /// Prefers non-current thread, and avoids threads where thread_get_state fails.
    public static func selectWorkerThread(task: mach_port_t) -> thread_act_t? {
        var threads: thread_act_array_t?
        var count: mach_msg_type_number_t = 0

        let kr = task_threads(task, &threads, &count)
        guard kr == KERN_SUCCESS, let list = threads, count > 0 else {
            print("[ThreadSelector] task_threads failed: \(kr)")
            return nil
        }

        defer {
            // task_threads allocates memory in our task; free it
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: list)),
                vm_size_t(count) * vm_size_t(MemoryLayout<thread_act_t>.stride)
            )
        }

        guard let arch = detectTargetArch(task: task) else {
            print("[ThreadSelector] detectTargetArch failed")
            return nil
        }

        // Iterate all threads and pick first we can read state from
        for i in 0..<Int(count) {
            let t = list[i]

            // Don’t pick the thread we’re currently on (rare but safe)
            if t == mach_thread_self() { continue }

            thread_suspend(t)
            defer { thread_resume(t) }

            switch arch {
            case .arm64:
                if let _: ThreadStateARM64 = getThreadState(ThreadStateARM64.self, thread: t) {
                    print("[ThreadSelector] selected thread index \(i) (arm64)")
                    return t
                }
            case .x86_64:
                if let _: ThreadStateX86_64 = getThreadState(ThreadStateX86_64.self, thread: t) {
                    print("[ThreadSelector] selected thread index \(i) (x86_64)")
                    return t
                }
            }
        }

        print("[ThreadSelector] no suitable thread found")
        return nil
    }
}


// Unclear if this code is working or not, just doing some basic
// debugging (too many changes at once)


//enum ThreadSelector {
//
//    // THREAD_BASIC_INFO expects a count in units of integer_t.
//    private static let threadBasicInfoCount: mach_msg_type_number_t =
//        mach_msg_type_number_t(
//            MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size
//        )
//
//    /// Returns a background / idle worker thread suitable for hijacking
//    static func selectWorkerThread(task: mach_port_t) -> thread_act_t? {
//        var threads: thread_act_array_t?
//        var count: mach_msg_type_number_t = 0
//
//        guard task_threads(task, &threads, &count) == KERN_SUCCESS,
//              let list = threads else { return nil }
//
//        defer {
//            vm_deallocate(
//                mach_task_self_,
//                vm_address_t(UInt(bitPattern: list)),
//                vm_size_t(count) * vm_size_t(MemoryLayout<thread_act_t>.size)
//            )
//        }
//
//        for i in 0..<Int(count) {
//            let thread = list[i]
//
//            var info = thread_basic_info_data_t()
//            var infoCount = threadBasicInfoCount
//
//            let kr = withUnsafeMutablePointer(to: &info) { infoPtr in
//                infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
//                    thread_info(
//                        thread,
//                        thread_flavor_t(THREAD_BASIC_INFO),
//                        $0,
//                        &infoCount
//                    )
//                }
//            }
//
//            guard kr == KERN_SUCCESS else { continue }
//
//            // Skip "hot" threads
//            if info.run_state == TH_STATE_RUNNING { continue }
//            if (info.flags & TH_FLAGS_SWAPPED) != 0 { continue }
//
//            return thread
//        }
//
//        return nil
//    }
//}
