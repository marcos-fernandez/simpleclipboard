import Foundation
import IOKit

/// The hardware UUID of this Mac. Unlike anything in the data folder, Migration Assistant and Time Machine cannot
/// copy it to another Mac, so `SyncService` uses it to tell whether sync.json was made here.
public enum MachineID {
    /// Nil when IOKit cannot give it: then nothing is decided from it.
    public static var current: String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else {
            return nil
        }
        defer {
            IOObjectRelease(service)
        }
        let property = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)
        return property?.takeRetainedValue() as? String
    }
}
