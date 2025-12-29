//
//  ThreadSelector.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/25/25.
//

import Darwin.Mach

public enum ThreadDebug {

    /// Prints a report and returns the chosen thread (if any).
    @discardableResult
    public static func pickAndReport(task: mach_port_t) -> thread_act_t? {
        print("[ThreadDebug] task=\(task)")

        if let arch = detectTargetArch(task: task) {
            print("[ThreadDebug] detected arch:", arch)
        } else {
            print("[ThreadDebug] detectTargetArch FAILED")
        }

        let t = ThreadSelector.selectWorkerThread(task: task)
        if let t {
            print("[ThreadDebug] selected worker thread:", t)
        } else {
            print("[ThreadDebug] NO WORKER THREAD FOUND")
        }
        return t
    }
}

public enum ThreadSelector {
    
    @inline(__always)
    private static func krString(_ kr: kern_return_t) -> String {
        if let c = mach_error_string(kr) { return String(cString: c) }
        return "unknown"
    }

    private static func fmt(_ v: UInt64) -> String { String(format: "%#llx", v) }

    /// Return a short per-thread label to help correlate logs.
    private static func threadLabel(_ t: thread_act_t) -> String {
        "thread=\(t)"
    }

    // MARK: - Public

    /// Picks a thread we can successfully read state from, with verbose diagnostics.
    ///
    /// Notes:
    /// - Does *not* suspend/resume threads (safer while debugging).
    /// - Logs kern_return_t + requested/returned counts when get_state fails.
    /// - Applies a minimal plausibility filter (pc/sp != 0).
    public static func selectWorkerThread(task: mach_port_t) -> thread_act_t? {
        var threads: thread_act_array_t?
        var count: mach_msg_type_number_t = 0

        let kr = task_threads(task, &threads, &count)
        guard kr == KERN_SUCCESS, let list = threads, count > 0 else {
            print("[ThreadSelector] task_threads failed: \(kr) \(krString(kr)) count=\(count)")
            return nil
        }

        defer {
            // task_threads allocates in *our* task; free it.
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

        print("[ThreadSelector] scanning \(count) threads (arch=\(arch))")

        // Prefer: not our current thread (usually irrelevant, but avoids weirdness).
        let selfThread = mach_thread_self()

        for i in 0..<Int(count) {
            let t = list[i]

            if t == selfThread {
                // Avoid selecting the current thread (rare in remote task use, but harmless).
                continue
            }

            switch arch {
            case .arm64: do {
                let r = getThreadStateDebug(ThreadStateArm.self, thread: t)
                guard r.kr == KERN_SUCCESS, let st = r.state else {
                    print("[ThreadSelector] [\(i)] \(threadLabel(t)) arm64 get_state failed: \(r.kr) \(krString(r.kr)) req=\(r.requestedCount) ret=\(r.returnedCount)")
                    continue
                }

                // Basic plausibility: non-zero PC/SP.
                // Adjust field names if yours differ.
                if st.pc == 0 || st.sp == 0 {
                    print("[ThreadSelector] [\(i)] \(threadLabel(t)) arm64 implausible pc/sp pc=\(fmt(st.pc)) sp=\(fmt(st.sp))")
                    continue
                }

                print("[ThreadSelector] SELECT [\(i)] \(threadLabel(t)) arm64 pc=\(fmt(st.pc)) sp=\(fmt(st.sp))")
                return t
            }

            case .x86_64: do {
                let r = getThreadStateDebug(ThreadStateX86.self, thread: t)
                guard r.kr == KERN_SUCCESS, let st = r.state else {
                    print("[ThreadSelector] [\(i)] \(threadLabel(t)) x86_64 get_state failed: \(r.kr) \(krString(r.kr)) req=\(r.requestedCount) ret=\(r.returnedCount)")
                    continue
                }

                // Basic plausibility: non-zero RIP/RSP.
                // Adjust field names if yours differ.
                if st.pc == 0 || st.sp == 0 {
                    print("[ThreadSelector] [\(i)] \(threadLabel(t)) x86_64 implausible pc/sp pc=\(fmt(st.pc)) sp=\(fmt(st.sp))")
                    continue
                }

                print("[ThreadSelector] SELECT [\(i)] \(threadLabel(t)) x86_64 pc=\(fmt(st.pc)) sp=\(fmt(st.sp))")
                return t
            }
            }
        }

        print("[ThreadSelector] no suitable thread found (count=\(count), arch=\(arch))")
        return nil
    }

    
  
//    /// Picks a thread we can successfully read state from (robust).
//    /// Does NOT suspend/resume; caller can do that.
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
//        for i in 0..<Int(count) {
//            let t = list[i]
//
//            switch arch {
//            case .arm64:
//                guard let st: ThreadStateArm = getThreadState(ThreadStateArm.self, thread: t) else {
//                    continue
//                }
//                // basic plausibility (adjust field names if yours differ)
//                if st.pc == 0 || st.sp == 0 { continue }
//
//                print("[ThreadSelector] selected thread index \(i) (arm64) pc=\(String(format:"%#llx", st.pc)) sp=\(String(format:"%#llx", st.sp))")
//                return t
//
//            case .x86_64:
//                guard let st: ThreadStateX86 = getThreadState(ThreadStateX86.self, thread: t) else {
//                    continue
//                }
//                if st.pc == 0 || st.sp == 0 { continue }
//
//                print("[ThreadSelector] selected thread index \(i) (x86_64) pc=\(String(format:"%#llx", st.pc)) sp=\(String(format:"%#llx", st.sp))")
//                return t
//            }
//        }
//
//        print("[ThreadSelector] no suitable thread found (count=\(count), arch=\(arch))")
//        return nil
//    }
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
