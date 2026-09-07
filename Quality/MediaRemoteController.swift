//
//  MediaRemoteController.swift
//  RateSync
//
//  Created by Vincent Neo on 1/5/22.
//

import Cocoa
import OSLog
import MediaRemoteAdapter

class MediaRemoteController {
    
    private let controller: MediaController
    // MediaRemote emits 2-5x duplicate bursts per track change; suppress
    // those so delivery is immediate without re-triggering the pipeline.
    private var lastDeliveredTrack: TrackInfo?
    private var lastDeliveredAt: Date?
    
    init(outputDevices: OutputDevices) {
        
        let controller = MediaController()
        self.controller = controller
        controller.startListening()
        
        controller.onTrackInfoReceived = { [weak outputDevices] trackInfo in
            guard let trackInfo else {
                self.lastDeliveredTrack = nil
                self.lastDeliveredAt = nil
                outputDevices?.clearNowPlayingTrack()
                return
            }
            guard self.isMonitored(trackInfo) else {
                self.lastDeliveredTrack = nil
                self.lastDeliveredAt = nil
                outputDevices?.clearNowPlayingTrack()
                return
            }
            Logger.switching.info("track \(trackInfo.payload.uniqueIdentifier) \(trackInfo.payload.title ?? "nil")")
            let receivedAt = Date()
            guard !Self.shouldSuppressDuplicate(
                previous: self.lastDeliveredTrack,
                current: trackInfo,
                lastDeliveredAt: self.lastDeliveredAt,
                now: receivedAt
            ) else { return }
            self.lastDeliveredTrack = trackInfo
            self.lastDeliveredAt = receivedAt
            outputDevices?.trackDidChange(trackInfo, eventDate: receivedAt)
        }
        
    }

    /// `TrackInfo` is not `Equatable`; compare the identity fields and the
    /// MediaRemote snapshot timestamp. The timestamp distinguishes a replay
    /// of the same metadata from a burst of the same callback payload.
    static func shouldSuppressDuplicate(
        previous: TrackInfo?,
        current: TrackInfo,
        lastDeliveredAt: Date?,
        now: Date
    ) -> Bool {
        TrackEventIdentity.shouldSuppressDuplicate(
            previous: previous.map(Self.eventIdentity),
            current: Self.eventIdentity(current),
            lastDeliveredAt: lastDeliveredAt,
            now: now
        )
    }

    private static func eventIdentity(_ trackInfo: TrackInfo) -> TrackEventIdentity {
        let payload = trackInfo.payload
        return TrackEventIdentity(
            title: payload.title,
            artist: payload.artist,
            album: payload.album,
            artworkDataBase64: payload.artworkDataBase64,
            bundleIdentifier: payload.bundleIdentifier,
            processID: payload.PID.map(Int.init),
            timestampEpochMicros: payload.timestampEpochMicros
        )
    }

    /// Filters Now Playing events by the user-selected monitoring source.
    /// `monitoredBundleIdentifier == nil` means monitor every app.
    /// Falls back to resolving the bundle id from the event's PID when the
    /// adapter did not include one (its PID lookup can race).
    private func isMonitored(_ trackInfo: TrackInfo) -> Bool {
        guard let monitored = Defaults.shared.monitoredBundleIdentifier else { return true }
        if trackInfo.payload.bundleIdentifier == monitored {
            return true
        }
        guard let pid = trackInfo.payload.PID, pid > 0,
              let app = NSRunningApplication(processIdentifier: pid) else {
            return false
        }
        return app.bundleIdentifier == monitored
    }
    
    deinit {
        controller.stopListening()
    }
    
}
