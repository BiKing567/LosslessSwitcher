//
//  RateSwitchingPolicy.swift
//  RateSync
//

import CoreAudioTypes
import Foundation

/// The source of a candidate format determines how much evidence is needed
/// before changing the output device.
enum RateSource {
    case mediaRemoteProbe
    case appleMusicPriority
    case appleMusicFormatLog
    case decoderLog
    case audioQueueLog
    case staleAudioQueueLog
    case preset
}

struct RateGatePolicy {
    let boundary: TimeInterval
    let stability: TimeInterval
    let lockedOverride: TimeInterval

    static let standard = RateGatePolicy(boundary: 3.5, stability: 2.0, lockedOverride: 12.0)
    static let appleMusicFormat = RateGatePolicy(boundary: 1.0, stability: 0.6, lockedOverride: 2.0)
    static let audioQueue = RateGatePolicy(boundary: 0, stability: 0.6, lockedOverride: 0.6)
}

enum RateSwitchingPolicy {
    static let maxPlausibleSampleRate: Double = 768_000
    static let maxPlausibleBitDepth: Int = 64

    static func gatePolicy(for source: RateSource) -> RateGatePolicy {
        switch source {
        case .audioQueueLog:
            return .audioQueue
        case .appleMusicFormatLog:
            return .appleMusicFormat
        case .staleAudioQueueLog, .mediaRemoteProbe, .appleMusicPriority, .decoderLog, .preset:
            return .standard
        }
    }

    static func bitDepth(reportedByMediaRemote: Int?, fallback: Int?) -> Int {
        reportedByMediaRemote ?? fallback ?? 24
    }
}

enum AppleMusicPriorityPolicy {
    static func shouldPrioritize(
        monitoredBundleIdentifier: String?,
        sourceBundleIdentifier: String?
    ) -> Bool {
        monitoredBundleIdentifier == nil
            && sourceBundleIdentifier != PlayerProfile.appleMusic.bundleIdentifier
    }
}

enum AppleMusicFormatPolicy {
    static func shouldUseAppleScriptFallback(
        hasKnownFormat: Bool,
        hasAttemptedFallback: Bool = false
    ) -> Bool {
        !hasKnownFormat && !hasAttemptedFallback
    }

    static func shouldReplaceCachedFormat(
        currentIsDolbyAtmos: Bool,
        incomingIsDolbyAtmos: Bool
    ) -> Bool {
        !currentIsDolbyAtmos || incomingIsDolbyAtmos
    }
}

/// Selects the device format closest to the format reported by the player.
/// This is deliberately stateless so the matching policy can be tested apart
/// from CoreAudio and the event-driven switching pipeline.
enum AudioFormatSelector {
    static func nearestFormat(
        sampleRate: Float64,
        bitDepth: Int32,
        supportedSampleRates: [Float64],
        formats: [AudioStreamBasicDescription],
        preferSampleRateMultiples: Bool
    ) -> AudioStreamBasicDescription? {
        guard let closestRate = supportedSampleRates.min(by: {
            abs($0 - sampleRate) < abs($1 - sampleRate)
        }) else {
            return nil
        }

        var targetRate = closestRate
        if preferSampleRateMultiples,
           closestRate != sampleRate,
           supportedSampleRates.contains(sampleRate / 2) {
            targetRate = sampleRate / 2
        }

        let formatsAtTargetRate = formats.filter { $0.mSampleRate == targetRate }
        let closestBitDepth = formatsAtTargetRate.min(by: {
            let lhsDistance = abs(Int32($0.mBitsPerChannel) - bitDepth)
            let rhsDistance = abs(Int32($1.mBitsPerChannel) - bitDepth)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return $0.mBitsPerChannel < $1.mBitsPerChannel
        })?.mBitsPerChannel

        guard let closestBitDepth else { return nil }
        return formatsAtTargetRate.first {
            $0.mSampleRate == targetRate && $0.mBitsPerChannel == closestBitDepth
        }
    }
}
