import Foundation

/// Carries data over from the app's former name (Clipboard) to SimpleClipboard.
/// Every step only fills in what is missing, so running it again is harmless.
public enum LegacyMigration {
    /// Moves `legacy` to `current` when only `legacy` exists and holds one of `markers`. Returns whether it moved.
    /// "Clipboard" is a common name: without a marker of the old app's data, the folder may be another app's or the
    /// user's own, and taking it over would let the first save delete what is in its images/.
    @discardableResult
    public static func moveDirectory(
        from legacy: URL, to current: URL, recognisedBy markers: [String], fileManager: FileManager = .default
    ) throws -> Bool {
        guard markers.contains(where: { fileManager.fileExists(atPath: legacy.appendingPathComponent($0).path) }),
              !fileManager.fileExists(atPath: current.path) else {
            return false
        }
        try fileManager.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: legacy, to: current)
        return true
    }

    /// Copies each of `keys` that `current` does not have yet.
    public static func copyDefaults(keys: [String], from legacy: UserDefaults, to current: UserDefaults) {
        for key in keys where current.object(forKey: key) == nil {
            if let value = legacy.object(forKey: key) {
                current.set(value, forKey: key)
            }
        }
    }
}
