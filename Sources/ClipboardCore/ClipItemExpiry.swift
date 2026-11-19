import Foundation

extension ClipItem {
    /// Same boundary as the store's purge, which only runs every `Config.purgeInterval`.
    public func isExpired(at date: Date) -> Bool {
        expiresAt.map { $0 <= date } ?? false
    }
}
