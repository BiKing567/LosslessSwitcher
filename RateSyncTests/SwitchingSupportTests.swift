import Foundation
import XCTest

final class SwitchingSupportTests: XCTestCase {
    func testResolvesAudioQueueProfileForKnownBundleIdentifier() {
        // Given
        let netEaseMusicBundleIdentifier = "com.netease.163music"

        // When
        let profile = PlayerProfile.profile(for: netEaseMusicBundleIdentifier)

        // Then
        XCTAssertEqual(profile?.processName, "NeteaseMusic")
        XCTAssertEqual(profile?.formatDetection, .audioQueueLogs)
    }

    func testFreshAudioQueueCandidateDoesNotWaitTwelveSecondsAfterExistingResult() {
        let policy = RateSwitchingPolicy.gatePolicy(for: .audioQueueLog)

        XCTAssertEqual(
            policy.lockedOverride,
            policy.stability,
            accuracy: 0.001,
            "fresh AudioQueue evidence should use the short stability window even after a prior result"
        )
    }

    func testStaleAudioQueueCandidateKeepsConservativePersistenceWindow() {
        let policy = RateSwitchingPolicy.gatePolicy(for: .staleAudioQueueLog)

        XCTAssertEqual(
            policy.lockedOverride,
            12.0,
            accuracy: 0.001,
            "stale AudioQueue evidence must not bypass the long persistence guard"
        )
    }

    func testMediaRemoteOnlyAcceptsUnverifiedFormatWithoutExpectedPID() {
        XCTAssertTrue(
            RateSwitchingPolicy.shouldAcceptUnverifiedMediaRemoteFormat(expectedPID: nil)
        )
        XCTAssertFalse(
            RateSwitchingPolicy.shouldAcceptUnverifiedMediaRemoteFormat(expectedPID: 42)
        )
    }

    func testAppleMusicParserPrefersDolbyAtmosFormatOverNearbyLossless44_1Log() {
        let entries = [
            AppleMusicLogEntry(
                date: Date(timeIntervalSince1970: 106),
                message: "ACAppleLosslessDecoder.cpp:680 Input format: 2 ch, 44100 Hz, alac (0x00000001) from 16-bit source"
            ),
            AppleMusicLogEntry(
                date: Date(timeIntervalSince1970: 107),
                message: "play> cm>> mediaFormatinfo '<private>' , asbdFormatID = qlac, lossless, asbdSampleRate = 44.1 kHz, is not rendering spatial audio"
            ),
            AppleMusicLogEntry(
                date: Date(timeIntervalSince1970: 105),
                message: "play> cm>> mediaFormatinfo '<private>' , asbdFormatID = qaac, sdFormatID = aac, stereo (lossy), asbdSampleRate = 48.0 kHz, is binaural, is rendering spatial audio, 16 original channels, original is Atmos"
            )
        ]

        let stat = AppleMusicFormatParser.parse(entries).first

        XCTAssertEqual(stat?.sampleRate, 48_000)
        XCTAssertTrue(stat?.isDolbyAtmos == true)
    }

    func testAppleMusicParserRecognizesQc3DolbyAtmosMarker() {
        let entries = [
            AppleMusicLogEntry(
                date: Date(timeIntervalSince1970: 305),
                message: "play> cm>> mediaFormatinfo '<private>' , asbdFormatID = qc+3, sdFormatID = ec+3, Dolby Atmos, asbdNumChannels = 16, asbdSampleRate = 48.0 kHz, is not rendering spatial audio, is Atmos"
            )
        ]

        let stat = AppleMusicFormatParser.parse(entries).first

        XCTAssertEqual(stat?.sampleRate, 48_000)
        XCTAssertTrue(stat?.isDolbyAtmos == true)
    }

    func testAppleMusicParserUsesHighLevelLosslessFormatBeforeDecoderLog() {
        let entries = [
            AppleMusicLogEntry(
                date: Date(timeIntervalSince1970: 205),
                message: "ACAppleLosslessDecoder.cpp:680 Input format: 2 ch, 44100 Hz, alac (0x00000001) from 16-bit source"
            ),
            AppleMusicLogEntry(
                date: Date(timeIntervalSince1970: 204),
                message: "play> cm>> mediaFormatinfo '<private>' , audioCapabilities: 0x0 -> 0x4, asbdFormatID = qlac, lossless, asbdNumChannels = 2, asbdSampleRate = 48.0 kHz, is not rendering spatial audio"
            )
        ]

        let stat = AppleMusicFormatParser.parse(entries).first

        XCTAssertEqual(stat?.sampleRate, 48_000)
        XCTAssertFalse(stat?.isDolbyAtmos == true)
    }

    func testAppleMusicHighLevelFormatUsesShortEvidenceGate() {
        let policy = RateSwitchingPolicy.gatePolicy(for: .appleMusicFormatLog)

        XCTAssertEqual(policy.boundary, 1.0, accuracy: 0.001)
        XCTAssertEqual(policy.stability, 0.6, accuracy: 0.001)
        XCTAssertEqual(policy.lockedOverride, 2.0, accuracy: 0.001)
    }

    func testAppleMusicEvidenceWindowRetainsDelayedDolbyFormat() {
        let atmosphericDate = Date(timeIntervalSince1970: 100)
        let losslessDate = Date(timeIntervalSince1970: 107)
        let queryDate = Date(timeIntervalSince1970: 110)
        let entries = [
            AppleMusicLogEntry(
                date: atmosphericDate,
                message: "asbdFormatID = qaac, asbdSampleRate = 48.0 kHz, original is Atmos"
            ),
            AppleMusicLogEntry(
                date: losslessDate,
                message: "asbdFormatID = qlac, lossless, asbdSampleRate = 44.1 kHz, is not rendering spatial audio"
            )
        ].filter { $0.date >= queryDate.addingTimeInterval(-AppleMusicFormatParser.logWindowSeconds) }

        let stat = AppleMusicFormatParser.parse(entries).first

        XCTAssertEqual(stat?.sampleRate, 48_000)
        XCTAssertTrue(stat?.isDolbyAtmos == true)
    }

    func testAppleMusicKnownFormatBlocksScriptFallbackAndKeepsAtmosEvidence() {
        XCTAssertFalse(AppleMusicFormatPolicy.shouldUseAppleScriptFallback(hasKnownFormat: true))
        XCTAssertTrue(AppleMusicFormatPolicy.shouldUseAppleScriptFallback(hasKnownFormat: false))
        XCTAssertFalse(
            AppleMusicFormatPolicy.shouldUseAppleScriptFallback(
                hasKnownFormat: false,
                hasAttemptedFallback: true
            )
        )
        XCTAssertFalse(
            AppleMusicFormatPolicy.shouldReplaceCachedFormat(
                currentIsDolbyAtmos: true,
                incomingIsDolbyAtmos: false
            )
        )
        XCTAssertTrue(
            AppleMusicFormatPolicy.shouldReplaceCachedFormat(
                currentIsDolbyAtmos: false,
                incomingIsDolbyAtmos: true
            )
        )
    }

    func testResolvesPresetRateForSpotify() {
        // Given
        let spotifyBundleIdentifier = "com.spotify.client"

        // When
        let profile = PlayerProfile.profile(for: spotifyBundleIdentifier)

        // Then
        XCTAssertEqual(profile?.fallbackSampleRate, 44_100)
    }

    func testResolvesBundleIdentifierForKnownProcessName() {
        // Given
        let processName = "Music"

        // When
        let bundleIdentifier = PlayerProfile.bundleIdentifier(forProcessName: processName)

        // Then
        XCTAssertEqual(bundleIdentifier, "com.apple.Music")
    }

    func testMonitoringSourcesExposeTheirLocalizationKeys() {
        XCTAssertEqual(
            PlayerProfile.monitoringSources.map(\.localizationKey),
            ["Apple Music", "Spotify", "NetEase Music", "QQ Music"]
        )
    }

    func testCompletesOneShotCallbackOnlyOnce() {
        // Given
        var values = [Int]()
        let completion = OneShotCompletion<Int> { values.append($0) }

        // When
        completion.complete(1)
        completion.complete(2)

        // Then
        XCTAssertEqual(values, [1])
    }

    func testCompletesOneShotCallbackOnceWhenCallsRace() {
        // Given
        let callbackExpectation = expectation(description: "callback")
        let completion = OneShotCompletion<Int> { _ in callbackExpectation.fulfill() }
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "OneShotCompletionTests", attributes: .concurrent)

        // When
        for value in 0..<100 {
            group.enter()
            queue.async {
                completion.complete(value)
                group.leave()
            }
        }

        // Then
        XCTAssertEqual(group.wait(timeout: .now() + 1), .success)
        wait(for: [callbackExpectation], timeout: 1)
    }

    func testWidgetKindKeepsExistingInstalledWidgetsCompatible() {
        XCTAssertEqual(RateSyncWidgetConfiguration.widgetKind, "RateSyncAudioFormatWidget")
    }

    func testWidgetTimelineHasFallbackRefreshForExternalFormatChanges() {
        let start = Date(timeIntervalSince1970: 1_000)

        let refresh = RateSyncWidgetConfiguration.nextRefreshDate(after: start)

        XCTAssertEqual(
            refresh.timeIntervalSince(start),
            RateSyncWidgetConfiguration.fallbackRefreshInterval,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(RateSyncWidgetConfiguration.fallbackRefreshInterval, 0)
    }

    func testWidgetNowPlayingFallbackTextIsReadable() {
        let track = SharedNowPlayingTrack(
            title: "  ",
            artist: nil,
            artworkDataBase64: nil,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(track.titleText, "Not Playing")
        XCTAssertEqual(track.artistText, "No Artist")
    }

    func testWidgetStateFallbackURLLivesInWidgetContainer() {
        let path = RateSyncWidgetConfiguration.localWidgetStateURL.path

        XCTAssertTrue(
            path.hasSuffix(
                "/Library/Containers/com.biking.RateSync.Widget/Data/Library/Application Support/RateSync/ratesync-widget-state.plist"
            )
        )
    }

    func testReplayWithSameMetadataButNewNowPlayingTimestampIsNotSuppressed() {
        let first = TrackEventIdentity(
            title: "Same Song",
            artist: "Same Artist",
            album: "Same Album",
            artworkDataBase64: nil,
            bundleIdentifier: "com.example.player",
            processID: 42,
            timestampEpochMicros: 1_000_000
        )
        let replay = TrackEventIdentity(
            title: "Same Song",
            artist: "Same Artist",
            album: "Same Album",
            artworkDataBase64: nil,
            bundleIdentifier: "com.example.player",
            processID: 42,
            timestampEpochMicros: 2_000_000
        )

        XCTAssertFalse(
            TrackEventIdentity.shouldSuppressDuplicate(
                previous: first,
                current: replay,
                lastDeliveredAt: Date(timeIntervalSince1970: 100),
                now: Date(timeIntervalSince1970: 100.1)
            )
        )
    }

    func testRepeatedCallbackWithSameNowPlayingTimestampIsSuppressed() {
        let first = TrackEventIdentity(
            title: "Same Song",
            artist: "Same Artist",
            album: "Same Album",
            artworkDataBase64: nil,
            bundleIdentifier: "com.example.player",
            processID: 42,
            timestampEpochMicros: 1_000_000
        )

        XCTAssertTrue(
            TrackEventIdentity.shouldSuppressDuplicate(
                previous: first,
                current: first,
                lastDeliveredAt: Date(timeIntervalSince1970: 100),
                now: Date(timeIntervalSince1970: 100.1)
            )
        )
    }

    func testArtworkSanitizerRejectsOversizedBase64Payload() {
        let oversizedArtwork = Data(
            repeating: 0,
            count: RateSyncWidgetConfiguration.maxArtworkDataBytes + 1
        ).base64EncodedString()

        XCTAssertNil(
            RateSyncWidgetConfiguration.sanitizedArtworkDataBase64(oversizedArtwork)
        )
    }

    func testArtworkSanitizerKeepsValidBase64Payload() {
        let artwork = Data([0x01, 0x02, 0x03]).base64EncodedString()

        XCTAssertEqual(
            RateSyncWidgetConfiguration.sanitizedArtworkDataBase64(artwork),
            artwork
        )
    }

    func testAppleMusicFallbackKeepsPollingForLaterLogEvidence() {
        XCTAssertEqual(
            AppleMusicFormatPolicy.resolution(
                hasLogEvidence: false,
                hasLogStats: false,
                hasCachedFallback: true,
                hasAttemptedFallback: true,
                isPlaying: true
            ),
            .cachedFallback
        )
        XCTAssertEqual(
            AppleMusicFormatPolicy.resolution(
                hasLogEvidence: true,
                hasLogStats: true,
                hasCachedFallback: true,
                hasAttemptedFallback: true,
                isPlaying: true
            ),
            .logEvidence
        )
    }

    func testWidgetStateMergesLatestIndependentFormatAndTrackSnapshots() {
        let older = RateSyncWidgetConfiguration.WidgetState(
            sampleRate: 44_100,
            bitDepth: 16,
            formatUpdatedAt: Date(timeIntervalSince1970: 10),
            title: "Older title",
            artist: "Older artist",
            artworkDataBase64: nil,
            trackUpdatedAt: Date(timeIntervalSince1970: 20)
        )
        let newerFormat = RateSyncWidgetConfiguration.WidgetState(
            sampleRate: 48_000,
            bitDepth: 24,
            formatUpdatedAt: Date(timeIntervalSince1970: 30),
            title: nil,
            artist: nil,
            artworkDataBase64: nil,
            trackUpdatedAt: nil
        )

        let merged = RateSyncWidgetConfiguration.mergeStates([older, newerFormat])

        XCTAssertEqual(merged?.sampleRate, 48_000)
        XCTAssertEqual(merged?.bitDepth, 24)
        XCTAssertEqual(merged?.title, "Older title")
        XCTAssertEqual(merged?.artist, "Older artist")
        XCTAssertEqual(merged?.trackUpdatedAt, Date(timeIntervalSince1970: 20))
    }

    func testWidgetPrefersLiveOutputFormatWhenPersistedStateIsStale() {
        let persisted = SharedAudioFormat(
            sampleRate: 44_100,
            bitDepth: 16,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let live = SharedAudioFormat(
            sampleRate: 48_000,
            bitDepth: 24,
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(
            RateSyncWidgetConfiguration.preferredAudioFormat(
                persisted: persisted,
                live: live
            ),
            live
        )
    }
}
