import Foundation
import Darwin.Mach

/// Lazily iterates over VM regions in a task.
public struct Regions: Sequence, IteratorProtocol {

    private let taskPort: mach_port_t
    private var nextAddress: mach_vm_address_t = 1
    private var filter: ((Region) -> Bool)?

    public init(taskPort: mach_port_t, filter: ((Region) -> Bool)? = nil) {
        self.taskPort = taskPort
        self.filter = filter
    }

    public mutating func next() -> Region? {
        guard taskPort != MACH_PORT_NULL else { return nil }

        while true {
            guard let (regionAddress, regionSize, info) =
                    MachCalls.regionInfo(task: taskPort, address: nextAddress)
            else { return nil }

            nextAddress = regionAddress + regionSize

            let region = Region(address: regionAddress,
                                size: regionSize,
                                info: info,
                                task: taskPort)

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
        Regions(taskPort: taskPort) { $0.isReadable }
    }

    /// Only regions with execute permissions
    public func filterExecutable() -> Regions {
        Regions(taskPort: taskPort) { $0.isExecutable }
    }

    /// Only regions that are both readable and executable
    public func filterReadableExecutable() -> Regions {
        Regions(taskPort: taskPort) { $0.isReadable && $0.isExecutable }
    }

    // MARK: - Main Executable Lookup

    /// Returns the region corresponding to the main executable in the task.
    public func mainExecutable() -> Region? {
        guard let mainBase = ProcessImages.shared
                .mainExecutableBase(task: taskPort)
        else { return nil }

        for region in self {
            guard region.isReadable,
                  region.isExecutable else { continue }

            // Exact match or containing region
            if region.address == mainBase ||
               (mainBase >= region.address && mainBase < region.address + region.size) {
                return region
            }
        }

        return nil
    }
}
