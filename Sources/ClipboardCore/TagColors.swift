/// The colours a tag can have, by the number a tag is saved with. What each number looks like is the app's
/// (`TagPalette`); which ones there are and in what order they are offered is here, where it can be tested.
public enum TagColors {
    /// The numbers in the order they are shown, which is Finder's: the grey, saved as 4 where a mint used to be,
    /// goes last. Apart from the numbers themselves, so that the tags already saved keep their colour.
    public static let order = [0, 1, 2, 3, 5, 6, 4]

    /// The colour of a new tag when `tagCount` exist: each one the next of the row, round and round.
    public static func indexForNewTag(tagCount: Int) -> Int {
        order[max(0, tagCount) % order.count]
    }
}
