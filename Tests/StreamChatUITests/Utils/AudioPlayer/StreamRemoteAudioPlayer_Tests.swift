//
// Copyright © 2023 Stream.io Inc. All rights reserved.
//

import AVFoundation
import Foundation
@testable import StreamChatUI
import XCTest

final class StreamRemoteAudioPlayer_Tests: XCTestCase {
    private var audioPlayerDelegate: StubAudioPlayerDelegate!
    private var syncDebouncer: SyncDebouncer!
    private var assetPropertyLoader: MockAssetPropertyLoader!
    private var notificationCenter: MockNotificationCenter!
    private var spyPlayer: SpyAVPlayer!
    private var subject: StreamRemoteAudioPlayer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        audioPlayerDelegate = .init()
        syncDebouncer = .init()
        assetPropertyLoader = .init()
        notificationCenter = .init()
        spyPlayer = .init()
        subject = .init(
            debouncer: syncDebouncer,
            assetPropertyLoader: assetPropertyLoader,
            notificationCenter: notificationCenter,
            player: spyPlayer
        )
    }

    override func tearDownWithError() throws {
        subject = nil
        spyPlayer = nil
        notificationCenter = nil
        assetPropertyLoader = nil
        syncDebouncer = nil
        audioPlayerDelegate = nil
        try super.tearDownWithError()
    }

    // MARK: - init

    func test_init_addPeriodicTimeObserverWasCalledOnThePlayerWithExpectedInterval() {
        let expectedInterval = CMTime(
            seconds: 0.1,
            preferredTimescale: CMTimeScale(NSEC_PER_SEC)
        )

        XCTAssertEqual(
            spyPlayer.addPeriodicTimeObserverWasCalledWith?.interval,
            expectedInterval
        )
    }

    func test_init_addObserverWasCalledOnTheNotificationCenterWithExpectedValues() {
        XCTAssertEqual(
            notificationCenter.addObserverWasCalledWith?.name,
            NSNotification.Name.AVPlayerItemDidPlayToEndTime
        )

        XCTAssertEqual(
            notificationCenter.addObserverWasCalledWith?.obj as? AVPlayer,
            spyPlayer
        )
    }

    // MARK: - deinit

    func test_deinit_removeTimeObserverWasCalledOnPlayer() {
        subject = nil

        XCTAssertNotNil(spyPlayer.removeTimeObserverWasCalledWithObserver)
    }

    // MARK: - loadAsset

    func test_loadAsset_whenURLIsNil_willCallPauseUpdateTheContextReplaceCurrentItemButWillNotCallLoadProperty() {
        subject.loadAsset(from: nil, delegate: audioPlayerDelegate)

        XCTAssertTrue(spyPlayer.pauseWasCalled)
        XCTAssertEqual(subject.context, .init(
            duration: 0,
            currentTime: 0,
            state: .stopped,
            rate: .zero,
            isSeeking: false
        ))
        XCTAssertTrue(spyPlayer.replaceCurrentItemWasCalled)
        XCTAssertNil(spyPlayer.replaceCurrentItemWasCalledWithItem)
        XCTAssertNil(subject.delegate)
    }

    func test_loadAsset_whenURLIsNotNil_assetLoadSucceeds_willCallPauseUpdateTheContextReplaceCurrentItemLoadPropertyAndPlay() {
        let url = URL(string: "http://getstream.io")!
        subject.play()
        spyPlayer.playWasCalled = false
        assetPropertyLoader.loadPropertyResult = .success(TimeInterval(100))
        let expectedContext = AudioPlaybackContext(
            duration: 100,
            currentTime: 0,
            state: .playing,
            rate: .zero,
            isSeeking: false
        )

        subject.loadAsset(from: url, delegate: audioPlayerDelegate)

        XCTAssertTrue(spyPlayer.pauseWasCalled)
        XCTAssertEqual(subject.context, expectedContext)
        XCTAssertTrue(spyPlayer.replaceCurrentItemWasCalled)
        XCTAssertEqual((spyPlayer.replaceCurrentItemWasCalledWithItem?.asset as? AVURLAsset)?.url, url)
        XCTAssertTrue(subject.delegate === audioPlayerDelegate)
        XCTAssertEqual(assetPropertyLoader.loadPropertyWasCalledWith?.property, .duration)
        XCTAssertEqual(assetPropertyLoader.loadPropertyWasCalledWith?.asset.url, url)
        XCTAssertTrue(spyPlayer.playWasCalled)
        XCTAssertTrue((audioPlayerDelegate.didUpdateContextWasCalled?.player as? StreamRemoteAudioPlayer) === subject)
        XCTAssertEqual(audioPlayerDelegate.didUpdateContextWasCalled?.context, expectedContext)
    }

    func test_loadAsset_whenURLIsNotNil_assetLoadFail_swillCallPauseUpdateTheContextReplaceCurrentItemLoadPropertyAndPlay() {
        let url = URL(string: "http://getstream.io")!
        subject.play()
        spyPlayer.playWasCalled = false
        assetPropertyLoader.loadPropertyResult = .failure(NSError())

        subject.loadAsset(from: url, delegate: audioPlayerDelegate)

        XCTAssertTrue(spyPlayer.pauseWasCalled)
        XCTAssertEqual(subject.context, .init(
            duration: 0,
            currentTime: 0,
            state: .notLoaded,
            rate: .zero,
            isSeeking: false
        ))
        XCTAssertTrue(spyPlayer.replaceCurrentItemWasCalled)
        XCTAssertNil(spyPlayer.replaceCurrentItemWasCalledWithItem)
        XCTAssertTrue(subject.delegate === audioPlayerDelegate)
        XCTAssertEqual(assetPropertyLoader.loadPropertyWasCalledWith?.property, .duration)
        XCTAssertEqual(assetPropertyLoader.loadPropertyWasCalledWith?.asset.url, url)
        XCTAssertFalse(spyPlayer.playWasCalled)
    }

    // MARK: - play

    func test_play_callsPlayOnPlayerAndUpdatesContextAndDelegate() {
        let url = URL(string: "http://getstream.io")!
        assetPropertyLoader.loadPropertyResult = .success(TimeInterval(100))
        subject.loadAsset(from: url, delegate: audioPlayerDelegate)
        spyPlayer.pause()
        spyPlayer.playWasCalled = false

        subject.play()

        XCTAssertEqual(audioPlayerDelegate.didUpdateContextWasCalled?.context.state, .playing)
        XCTAssertTrue(spyPlayer.playWasCalled)
    }

    // MARK: - pause

    func test_pause_callsPauseOnPlayerAndUpdatesContextAndDelegate() {
        let url = URL(string: "http://getstream.io")!
        assetPropertyLoader.loadPropertyResult = .success(TimeInterval(100))
        subject.loadAsset(from: url, delegate: audioPlayerDelegate)

        subject.pause()

        XCTAssertEqual(audioPlayerDelegate.didUpdateContextWasCalled?.context.state, .paused)
        XCTAssertTrue(spyPlayer.pauseWasCalled)
    }

    // MARK: - stop

    func test_stop_callsPauseOnPlayerAndUpdatesContextAndDelegate() {
        let url = URL(string: "http://getstream.io")!
        assetPropertyLoader.loadPropertyResult = .success(TimeInterval(100))
        subject.loadAsset(from: url, delegate: audioPlayerDelegate)

        subject.stop()

        XCTAssertEqual(audioPlayerDelegate.didUpdateContextWasCalled?.context.state, .stopped)
        XCTAssertEqual(audioPlayerDelegate.didUpdateContextWasCalled?.context.duration, TimeInterval(100))
        XCTAssertEqual(audioPlayerDelegate.didUpdateContextWasCalled?.context.currentTime, 0)
        XCTAssertEqual(audioPlayerDelegate.didUpdateContextWasCalled?.context.rate, .zero)
        XCTAssertFalse(audioPlayerDelegate.didUpdateContextWasCalled?.context.isSeeking ?? true)
        XCTAssertTrue(spyPlayer.pauseWasCalled)
    }

    // MARK: - updateRate

    func test_updateRate_updatesPlayerRate() {
        let url = URL(string: "http://getstream.io")!
        assetPropertyLoader.loadPropertyResult = .success(TimeInterval(100))
        subject.loadAsset(from: url, delegate: audioPlayerDelegate)

        // Rate is 0 as the player is not actually playing
        subject.updateRate() // This call will change the rate to 0.5
        spyPlayer.addPeriodicTimeObserverWasCalledWith?.block(.zero) // Used to simulate the player's rate update
        XCTAssertEqual(spyPlayer.rateWasUpdatedTo, 0.5)

        subject.updateRate() // This call will change the rate to 1
        spyPlayer.addPeriodicTimeObserverWasCalledWith?.block(.zero) // Used to simulate the player's rate update
        XCTAssertEqual(spyPlayer.rateWasUpdatedTo, 1)

        subject.updateRate() // This call will change the rate to 2
        spyPlayer.addPeriodicTimeObserverWasCalledWith?.block(.zero) // Used to simulate the player's rate update
        XCTAssertEqual(spyPlayer.rateWasUpdatedTo, 2)

        subject.updateRate() // This call will change the rate to 0.5
        spyPlayer.addPeriodicTimeObserverWasCalledWith?.block(.zero) // Used to simulate the player's rate update
        XCTAssertEqual(spyPlayer.rateWasUpdatedTo, 0.5)
    }

    // MARK: - seek(to:)

    func test_seek_willCallPauseAndUpdateTheContextAsExpectedDebounceWillBeCalled() {
        subject = .init(
            debouncer: Debouncer(interval: 1),
            assetPropertyLoader: assetPropertyLoader,
            notificationCenter: notificationCenter,
            player: spyPlayer
        )

        let url = URL(string: "http://getstream.io")!
        assetPropertyLoader.loadPropertyResult = .success(TimeInterval(100))
        subject.loadAsset(from: url, delegate: audioPlayerDelegate)

        subject.seek(to: 50)

        XCTAssertTrue(spyPlayer.playWasCalled)
        XCTAssertEqual(audioPlayerDelegate.didUpdateContextWasCalled?.context.state, .paused)
        XCTAssertEqual(audioPlayerDelegate.didUpdateContextWasCalled?.context.currentTime, 50)
        XCTAssertTrue(audioPlayerDelegate.didUpdateContextWasCalled?.context.isSeeking ?? false)
    }

    func test_seek_seekWasCalledAndTheRequestWasExecuted_seekWasCalledOnPlayerAndContextWasUpdatedSuccessfully() {
        let url = URL(string: "http://getstream.io")!
        assetPropertyLoader.loadPropertyResult = .success(TimeInterval(100))
        subject.loadAsset(from: url, delegate: audioPlayerDelegate)

        subject.seek(to: 50)

        XCTAssertTrue(spyPlayer.playWasCalled)
        XCTAssertEqual(audioPlayerDelegate.didUpdateContextWasCalled?.context.state, .playing)
        XCTAssertFalse(audioPlayerDelegate.didUpdateContextWasCalled?.context.isSeeking ?? true)
        XCTAssertTrue(syncDebouncer.debounceWasCalled)
        XCTAssertEqual(spyPlayer.seekWasCalledWith?.time, CMTimeMakeWithSeconds(50, preferredTimescale: CMTimeScale(NSEC_PER_SEC)))
        XCTAssertEqual(spyPlayer.seekWasCalledWith?.toleranceBefore, .zero)
        XCTAssertEqual(spyPlayer.seekWasCalledWith?.toleranceAfter, .zero)
    }
}

extension StreamRemoteAudioPlayer_Tests {
    private class SpyAVPlayer: AVPlayer {
        private(set) var addPeriodicTimeObserverWasCalledWith: (interval: CMTime, block: (CMTime) -> Void)?

        private(set) var removeTimeObserverWasCalledWithObserver: Any?

        var playWasCalled = false

        private(set) var pauseWasCalled = false

        private(set) var replaceCurrentItemWasCalled = false
        private(set) var replaceCurrentItemWasCalledWithItem: AVPlayerItem?

        private(set) var rateWasUpdatedTo: Float?

        private(set) var seekWasCalledWith: (time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime)?

        override var rate: Float {
            didSet { rateWasUpdatedTo = rate }
        }

        override func addPeriodicTimeObserver(
            forInterval interval: CMTime,
            queue: DispatchQueue?,
            using block: @escaping (CMTime) -> Void
        ) -> Any {
            addPeriodicTimeObserverWasCalledWith = (interval, block)
            return super.addPeriodicTimeObserver(
                forInterval: interval,
                queue: queue,
                using: block
            )
        }

        override func removeTimeObserver(
            _ observer: Any
        ) {
            removeTimeObserverWasCalledWithObserver = observer
            super.removeTimeObserver(observer)
        }

        override func play() {
            playWasCalled = true
            super.play()
        }

        override func pause() {
            pauseWasCalled = true
            super.pause()
        }

        override func replaceCurrentItem(
            with item: AVPlayerItem?
        ) {
            replaceCurrentItemWasCalled = true
            replaceCurrentItemWasCalledWithItem = item
            super.replaceCurrentItem(with: item)
        }

        override func seek(
            to time: CMTime,
            toleranceBefore: CMTime,
            toleranceAfter: CMTime
        ) {
            seekWasCalledWith = (time, toleranceBefore, toleranceAfter)
            super.seek(
                to: time,
                toleranceBefore: toleranceBefore,
                toleranceAfter: toleranceAfter
            )
        }
    }

    private class StubAudioPlayerDelegate: AudioPlayingDelegate {
        private(set) var didUpdateContextWasCalled: (player: AudioPlaying, context: AudioPlaybackContext)?

        func audioPlayer(
            _ audioPlayer: AudioPlaying,
            didUpdateContext context: AudioPlaybackContext
        ) {
            didUpdateContextWasCalled = (audioPlayer, context)
        }
    }

    private class SyncDebouncer: Debouncing {
        private(set) var debounceWasCalled: Bool = false

        func debounce(_ handler: @escaping Handler) {
            debounceWasCalled = true
            handler()
        }

        func cancel() { /* No-op */ }
    }

    private class MockAssetPropertyLoader: AssetPropertyLoading {
        private(set) var loadPropertyWasCalledWith: (property: AssetProperty, asset: AVURLAsset)?
        var loadPropertyResult: Result<Any, Error>?

        func loadProperty<Value>(
            _ property: AssetProperty,
            of asset: AVURLAsset,
            onSuccessTransformer: @escaping (AVURLAsset) -> Value,
            completion: @escaping (Result<Value, Error>) -> Void
        ) {
            loadPropertyWasCalledWith = (property, asset)
            completion(loadPropertyResult!.map { $0 as! Value })
        }
    }

    private class MockNotificationCenter: NotificationCenter {
        private(set) var addObserverWasCalledWith: (
            name: NSNotification.Name?,
            obj: Any?,
            block: (Notification) -> Void
        )?

        override func addObserver(
            forName name: NSNotification.Name?,
            object obj: Any?,
            queue: OperationQueue?,
            using block: @escaping (Notification) -> Void
        ) -> NSObjectProtocol {
            addObserverWasCalledWith = (name, obj, block)
            return NSObject()
        }
    }
}
