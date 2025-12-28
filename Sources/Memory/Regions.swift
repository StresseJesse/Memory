import Foundation
import Darwin.Mach
import AppKit

enum MemError: Error {
    case noPID
    case noTaskPort
}
/// Lazily iterates over VM regions in a task.
public struct Regions: Sequence, IteratorProtocol {

    public let port: mach_port_t
    private var nextAddress: mach_vm_address_t = 1
    private var filter: ((Region) -> Bool)?

    public init(port: mach_port_t, filter: ((Region) -> Bool)? = nil) {
        self.port = port
        self.filter = filter
        print("Regions initialized")
    }
    
    public init(name: String) throws {
        guard let app = NSWorkspace.shared.runningApplications
                .first(where: { $0.localizedName?.lowercased() == name.lowercased() }) else { throw MemError.noPID }
        let pid = app.processIdentifier

        var port: mach_port_t = mach_port_t(MACH_PORT_NULL)
        let kr = task_for_pid(mach_task_self_, pid, &port)
        guard kr == KERN_SUCCESS else {
            print("task_for_pid(\(pid)) failed: \(kr)")
            throw MemError.noTaskPort
        }
        self.init(port: port)
        
    }

    public mutating func next() -> Region? {
        guard port != MACH_PORT_NULL else { return nil }

        while true {
            guard let (regionAddress, regionSize, info) =
                    MachCalls.regionInfo(task: port, address: nextAddress)
            else { return nil }

            nextAddress = regionAddress + regionSize

            let region = Region(address: regionAddress,
                                size: regionSize,
                                info: info,
                                task: port)

            if let filter = filter {
                if filter(region) { return region }
            } else {
                return region
            }
        }
    }

    // MARK: - Filtered Iterators

    /// Only regions with read permissions
    public func filterReadable() -> Regions {
        Regions(port: port) { $0.isReadable }
    }

    /// Only regions with execute permissions
    public func filterExecutable() -> Regions {
        Regions(port: port) { $0.isExecutable }
    }

    /// Only regions that are both readable and executable
    public func filterReadableExecutable() -> Regions {
        Regions(port: port) { $0.isReadable && $0.isExecutable }
    }

    // MARK: - Main Executable Lookup

    /// Returns the region corresponding to the main executable in the task.
    public func mainExecutable() -> Region? {
        guard let mainBase = ProcessImages.shared
                .mainExecutableBase(task: port)
        else { return nil }

        for region in self {
            print("checking region at \(region.address)")
            guard region.isReadable,
                  region.isExecutable else {
                print("isReadable: \(region.isReadable), isExecutable: \(region.isExecutable)")
                continue }

            // Exact match or containing region
            if region.address == mainBase ||
               (mainBase >= region.address && mainBase < region.address + region.size) {
                return region
            }
        }

        return nil
    }
}
