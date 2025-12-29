//
//  ThreadSelector.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/25/25.
//

import Darwin.Mach

public enum ThreadSelector {
  
    /// Picks a thread we can successfully read state from (robust).
    /// Does NOT suspend/resume; caller can do that.
    public static func selectWorkerThread(task: mach_port_t) -> thread_act_t? {
        var threads: thread_act_array_t?
        var count: mach_msg_type_number_t = 0

        let kr = task_threads(task, &threads, &count)
        guard kr == KERN_SUCCESS, let list = threads, count > 0 else {
            print("[ThreadSelector] task_threads failed: \(kr)")
            return nil
        }

        defer {
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

        for i in 0..<Int(count) {
            let t = list[i]

            switch arch {
            case .arm64:
                guard let st: ThreadStateArm = getThreadState(ThreadStateArm.self, thread: t) else {
                    continue
                }
                // basic plausibility (adjust field names if yours differ)
                if st.pc == 0 || st.sp == 0 { continue }

                print("[ThreadSelector] selected thread index \(i) (arm64) pc=\(String(format:"%#llx", st.pc)) sp=\(String(format:"%#llx", st.sp))")
                return t

            case .x86_64:
                guard let st: ThreadStateX86 = getThreadState(ThreadStateX86.self, thread: t) else {
                    continue
                }
                if st.pc == 0 || st.sp == 0 { continue }

                print("[ThreadSelector] selected thread index \(i) (x86_64) pc=\(String(format:"%#llx", st.pc)) sp=\(String(format:"%#llx", st.sp))")
                return t
            }
        }

        print("[ThreadSelector] no suitable thread found (count=\(count), arch=\(arch))")
        return nil
    }
//    static func selectWorkerThread(task: mach_port_t) -> thread_act_t? {
//        var threads: thread_act_array_t?
//        var count: mach_msg_type_number_t = 0
//        guard task_threads(task, &threads, &count) == KERN_SUCCESS,
//              let threads else { return nil }
//        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(count) * vm_size_t(MemoryLayout<thread_act_t>.stride)) }
//
//        let selfThread = mach_thread_self()
//        defer { mach_port_deallocate(mach_task_self_, selfThread) }
//
//        // Prefer: WAITING/RUNNING and state-get succeeds
//        var best: thread_act_t? = nil
//
//        for i in 0..<Int(count) {
//            let t = threads[i]
//            if t == selfThread { continue }
//
//            // (Optional) read thread_basic_info to avoid dead/suspended threads
//            var info = thread_basic_info()
//            var infoCount = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
//            let krInfo = withUnsafeMutablePointer(to: &info) {
//                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
//                    thread_info(t, thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
//                }
//            }
//            if krInfo == KERN_SUCCESS {
//                // Accept WAITING or RUNNING (this is the key change)
//                if info.run_state != TH_STATE_RUNNING && info.run_state != TH_STATE_WAITING {
//                    continue
//                }
//                if (info.flags & TH_FLAGS_SWAPPED) != 0 { continue }
//                // If you have a “suspended” filter today, loosen it.
//            }
//
//            // Must be able to read/set state for this thread
//            guard let arch = detectTargetArch(task: task) else { return nil }
//
//            switch arch {
//            case .arm64:
//                guard let st: ThreadStateArm = getThreadState(ThreadStateArm.self, thread: t) else { continue }
//                if st.pc == 0 || st.sp == 0 { continue }
//                best = t
//
//            case .x86_64:
//                guard let st: ThreadStateX86 = getThreadState(ThreadStateX86.self, thread: t) else { continue }
//                if st.pc == 0 || st.sp == 0 { continue }
//                best = t
//            }
//
//            if best != nil { break }
//        }
//
//        return best
//    }

//    /// Picks a thread we can successfully read state from (robust).
//    /// Prefers non-current thread, and avoids threads where thread_get_state fails.
//    public static func selectWorkerThread(task: mach_port_t) -> thread_act_t? {
//        var threads: thread_act_array_t?
//        var count: mach_msg_type_number_t = 0
//
//        let kr = task_threads(task, &threads, &count)
//        guard kr == KERN_SUCCESS, let list = threads, count > 0 else {
//            print("[ThreadSelector] task_threads failed: \(kr)")
//            return nil
//        }
//
//        defer {
//            // task_threads allocates memory in our task; free it
//            vm_deallocate(
//                mach_task_self_,
//                vm_address_t(UInt(bitPattern: list)),
//                vm_size_t(count) * vm_size_t(MemoryLayout<thread_act_t>.stride)
//            )
//        }
//
//        guard let arch = detectTargetArch(task: task) else {
//            print("[ThreadSelector] detectTargetArch failed")
//            return nil
//        }
//
//        // Iterate all threads and pick first we can read state from
//        for i in 0..<Int(count) {
//            let t = list[i]
//
//            // Don’t pick the thread we’re currently on (rare but safe)
//            if t == mach_thread_self() { continue }
//
//            thread_suspend(t)
//            defer { thread_resume(t) }
//
//            switch arch {
//            case .arm64:
//                if let _: ThreadStateArm = getThreadState(ThreadStateArm.self, thread: t) {
//                    print("[ThreadSelector] selected thread index \(i) (arm64)")
//                    return t
//                }
//            case .x86_64:
//                if let _: ThreadStateX86 = getThreadState(ThreadStateX86.self, thread: t) {
//                    print("[ThreadSelector] selected thread index \(i) (x86_64)")
//                    return t
//                }
//            }
//        }
//
//        print("[ThreadSelector] no suitable thread found")
//        return nil
//    }
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
