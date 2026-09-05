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
}
