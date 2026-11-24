/// Which changes of the pasteboard are read. The pasteboard only says how many times it has changed, so the count
/// seen last is kept, and a change is one that moved it.
public struct PasteboardChanges: Sendable {
    private var lastChangeCount: Int

    /// `changeCount`: the pasteboard's when watching starts. What it holds then is not a copy to read.
    public init(changeCount: Int) {
        lastChangeCount = changeCount
    }

    /// Whether the pasteboard, now at `changeCount`, holds a copy to read. The count is taken before the pause is
    /// looked at: a copy made while paused is passed over for good, and not read when the pause ends. `isPaused`
    /// is only asked when there is a change.
    public mutating func hasCopyToRead(changeCount: Int, isPaused: () -> Bool) -> Bool {
        guard changeCount != lastChangeCount else {
            return false
        }
        lastChangeCount = changeCount
        return !isPaused()
    }
}
