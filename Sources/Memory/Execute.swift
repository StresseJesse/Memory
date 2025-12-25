//
//  Execute.swift
//  Memory
//
//  Created by Jesse Ramsey on 12/25/25.
//

import Darwin.Mach

public enum RemoteExecute {

    public static func executeAndReturn(
        task: mach_port_t,
        function address: mach_vm_address_t,
        arguments: [UInt64] = []
    ) -> UInt64? {

        guard let thread = ThreadSelector.selectWorkerThread(task: task)
        else { return nil }

        // 1. Capture original state
        var original = ThreadState()
        var count = THREAD_STATE_COUNT

        guard Mach.getThreadState(
            thread,
            into: &original.raw,
            count: &count
        ) == KERN_SUCCESS else { return nil }

        var state = original

        // 2. Setup call
        state.pc = UInt64(address)

        if arguments.count > 0 { state.arg0 = arguments[0] }
        if arguments.count > 1 { state.arg1 = arguments[1] }
        if arguments.count > 2 { state.arg2 = arguments[2] }
        if arguments.count > 3 { state.arg3 = arguments[3] }

        #if arch(arm64)
        state.lr = original.pc     // clean return
        #elseif arch(x86_64)
        state.sp -= 8
        var ret = original.pc
        MachCalls.write(
            task: task,
            address: mach_vm_address_t(state.sp),
            buffer: &ret,
            count: 8
        )
        #endif

        // 3. Inject state
        guard Mach.setThreadState(
            thread,
            from: &state.raw,
            count: THREAD_STATE_COUNT
        ) == KERN_SUCCESS else { return nil }

        // 4. Resume and wait briefly
        thread_resume(thread)
        usleep(5000)
        thread_suspend(thread)

        // 5. Read final state
        var final = ThreadState()
        count = THREAD_STATE_COUNT

        guard Mach.getThreadState(
            thread,
            into: &final.raw,
            count: &count
        ) == KERN_SUCCESS else { return nil }

        // 6. Restore original state
        var restore = original
        _ = Mach.setThreadState(
            thread,
            from: &restore.raw,
            count: THREAD_STATE_COUNT
        )

        thread_resume(thread)

        return final.retVal
    }
}
