import Foundation

/// iCloud sync over the ubiquitous key-value store.
///
/// The choice of store is a size decision, not a taste one. Key-value sync gives
/// you 1 MB and no server code, which is exactly enough for a few hundred people
/// of text and nowhere near enough for their photos. So photos and avatars are
/// stripped before upload and re-attached from the local copy on the way back
/// down — they stay on the device that took them, and the settings page says so
/// rather than implying otherwise.
///
/// Conflict resolution is last-writer-wins on the whole snapshot, compared on a
/// timestamp. For an app one person uses on their own phone and their own iPad,
/// a merge algorithm would be more code than the problem deserves.
enum CloudSync {

    private static let key = "metwho.snapshot"
    private static let stampKey = "metwho.snapshot.updatedAt"

    static var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    static func push(_ data: Data, at stamp: Date) {
        let store = NSUbiquitousKeyValueStore.default
        // over the limit the write is silently dropped, which would look like
        // sync "just not working" forever; better to skip and stay honest
        guard data.count < 900_000 else { return }
        store.set(data, forKey: key)
        store.set(stamp.timeIntervalSince1970, forKey: stampKey)
        store.synchronize()
    }

    /// The remote snapshot, but only when it is genuinely newer than ours.
    static func pull(newerThan local: Date) -> Data? {
        let store = NSUbiquitousKeyValueStore.default
        let remote = Date(timeIntervalSince1970: store.double(forKey: stampKey))
        guard remote > local.addingTimeInterval(1), let data = store.data(forKey: key) else { return nil }
        return data
    }

    static func start(onRemoteChange: @escaping () -> Void) {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { _ in onRemoteChange() }
        NSUbiquitousKeyValueStore.default.synchronize()
    }
}
