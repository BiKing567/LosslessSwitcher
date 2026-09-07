import Foundation

struct TrackEventIdentity: Equatable {
    let title: String?
    let artist: String?
    let album: String?
    let artworkDataBase64: String?
    let bundleIdentifier: String?
    let processID: Int?
    let timestampEpochMicros: Double?

    private static let duplicateWindow: TimeInterval = 0.5

    static func shouldSuppressDuplicate(
        previous: TrackEventIdentity?,
        current: TrackEventIdentity,
        lastDeliveredAt: Date?,
        now: Date
    ) -> Bool {
        guard let previous,
              previous.title == current.title,
              previous.artist == current.artist,
              previous.album == current.album,
              previous.artworkDataBase64 == current.artworkDataBase64,
              previous.bundleIdentifier == current.bundleIdentifier,
              previous.processID == current.processID else {
            return false
        }

        if let previousTimestamp = previous.timestampEpochMicros,
           let currentTimestamp = current.timestampEpochMicros {
            return previousTimestamp == currentTimestamp
        }

        guard let lastDeliveredAt else { return true }
        return now.timeIntervalSince(lastDeliveredAt) <= duplicateWindow
    }
}
