import Foundation

struct PlayerProfile: Equatable, Identifiable {
    enum FormatDetection: Equatable {
        case mediaRemoteThenLogs
        case audioQueueLogs
    }

    let bundleIdentifier: String
    let displayName: String
    let processName: String
    let formatDetection: FormatDetection
    let fallbackSampleRate: Double?

    var id: String { bundleIdentifier }

    static let appleMusic = PlayerProfile(
        bundleIdentifier: "com.apple.Music",
        displayName: "Apple Music",
        processName: "Music",
        formatDetection: .mediaRemoteThenLogs,
        fallbackSampleRate: nil
    )
    static let spotify = PlayerProfile(
        bundleIdentifier: "com.spotify.client",
        displayName: "Spotify",
        processName: "Spotify",
        formatDetection: .mediaRemoteThenLogs,
        fallbackSampleRate: 44_100
    )
    static let neteaseMusic = PlayerProfile(
        bundleIdentifier: "com.netease.163music",
        displayName: "NetEase Music",
        processName: "NeteaseMusic",
        formatDetection: .audioQueueLogs,
        fallbackSampleRate: nil
    )
    static let qqMusic = PlayerProfile(
        bundleIdentifier: "com.tencent.QQMusicMac",
        displayName: "QQ Music",
        processName: "QQMusic",
        formatDetection: .audioQueueLogs,
        fallbackSampleRate: nil
    )

    static let monitoringSources = [appleMusic, spotify, neteaseMusic, qqMusic]

    static func profile(for bundleIdentifier: String?) -> PlayerProfile? {
        monitoringSources.first { $0.bundleIdentifier == bundleIdentifier }
    }

    static func bundleIdentifier(forProcessName processName: String) -> String? {
        monitoringSources.first { $0.processName == processName }?.bundleIdentifier
    }
}
