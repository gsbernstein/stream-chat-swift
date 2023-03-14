//
// Copyright © 2023 Stream.io Inc. All rights reserved.
//

import AVFoundation
import Foundation
import StreamChat

/// A protocol describing an object that can be manage the playback of an audio file or stream.
public protocol AudioPlaying: AnyObject {
    static func build() -> AudioPlaying

    /// Instructs the player to load the asset from the provided URL and prepare it for streaming.
    /// - Parameters:
    /// - url: The URL where the asset will be streamed from. If nil then the player will simply clear
    /// up the current playback queue.
    /// - delegate: The delegate that will be informed for changes on the asset's playback.
    func loadAsset(
        from url: URL?,
        delegate: AudioPlayingDelegate
    )

    /// Being the loaded asset's playback. If non has been loaded the action has no effect
    func play()

    /// Pauses the loaded asset's playback. If non has been loaded or the playback hasn't started yet
    /// the action has no effect.
    func pause()

    /// Stop the loaded asset's playback. If non has been loaded or the playback hasn't started yet
    /// the action has no effect.
    func stop()

    /// Updates the loaded asset's playback rate to the next available one. For more information see
    /// ``AudioPlaybackRate``
    func updateRate()

    /// Performs as seek at the loaded asset's timeline at the provided time
    /// - Parameters:
    /// - time: The time to seek at
    func seek(
        to time: TimeInterval
    )
}

/// An implementation of ``AudioPlaying`` that can be used to stream audio files from a URL
final class StreamRemoteAudioPlayer: AudioPlaying {
    // MARK: - Properties

    /// Describes the state of the player and provides information about its metadata
    @Atomic private(set) var context: AudioPlaybackContext = .notLoaded

    /// The player that will be used for the playback of the audio files
    private let player: AVPlayer

    /// The debouncer is being used during `` seek(to time: TimeInterval)`` to provide a
    /// interactive UI updates while keeping actual seek requests to minimum.
    private let debouncer: Debouncing

    /// The assetPropertyLoader is being used during the loading of an asset with non-nil URL, to provide
    /// async information about the asset's properties. Currently, we are only loading the `duration`
    /// property.
    private let assetPropertyLoader: AssetPropertyLoading

    /// An observer that acts as a mediator between the AVPlayer and StreamAudioPlayer for playback
    /// updates.
    private let playerObserver: AudioPlayerObserving

    /// The delegate which should get informed when the player's context gets updated
    private(set) weak var delegate: AudioPlayingDelegate? {
        didSet { delegate?.audioPlayer(self, didUpdateContext: context) }
    }

    // MARK: - Lifecycle

    static func build() -> AudioPlaying {
        StreamRemoteAudioPlayer(
            debouncer: Debouncer(interval: 0.1),
            assetPropertyLoader: StreamAssetPropertyLoader(),
            playerObserver: StreamPlayerObserver(),
            player: .init()
        )
    }

    init(
        debouncer: Debouncing,
        assetPropertyLoader: AssetPropertyLoading,
        playerObserver: AudioPlayerObserving,
        player: AVPlayer
    ) {
        self.debouncer = debouncer
        self.assetPropertyLoader = assetPropertyLoader
        self.playerObserver = playerObserver
        self.player = player

        setUp()
    }

    // MARK: - Helpers

    /// Creates a new AVPlayer instance and registers the periodicTimer and the playbackFinishedObserver
    private func setUp() {
        let player = self.player
        let interval = CMTime(
            seconds: 0.1,
            preferredTimescale: CMTimeScale(NSEC_PER_SEC)
        )

        playerObserver.addPeriodicTimeObserver(
            player,
            forInterval: interval,
            queue: nil
        ) { [weak self] in
            guard
                let self = self,
                self.context.isSeeking == false
            else {
                return
            }

            self.updateContext { value in
                let currentTime = player.currentTime().seconds
                value.currentTime = currentTime.isFinite && !currentTime.isNaN
                    ? TimeInterval(currentTime)
                    : .zero

                value.isSeeking = false

                value.state = player.rate != 0
                    ? .playing
                    : player.timeControlStatus == .paused ? .paused : .stopped

                value.rate = .init(rawValue: player.rate) ?? .zero
            }
        }

        playerObserver.addTimeControlStatusObserver(player) { [weak self] newValue in
            guard
                let self = self,
                let newValue = newValue
            else {
                return
            }

            let currentPlaybackState = self.context.state
            self.updateContext { value in
                switch (newValue, currentPlaybackState) {
                case (.paused, .playing), (.paused, .stopped), (.paused, .loading):
                    value.state = .paused
                case (.playing, .paused), (.playing, .stopped), (.playing, .loading):
                    value.state = .playing
                default:
                    log.debug("\(type(of: self)): No action for transition \(currentPlaybackState) -> \(newValue)")
                }
            }
        }

        playerObserver.addStoppedPlaybackObserver(queue: nil) { [weak self] playerItem in
            guard
                let self = self,
                let playerItemURL = (playerItem.asset as? AVURLAsset)?.url,
                let currentItemURL = (player.currentItem?.asset as? AVURLAsset)?.url,
                playerItemURL == currentItemURL
            else {
                return
            }
            self._context.mutate { value in
                value.state = .stopped
                value.currentTime = 0
            }

            self.delegate?.audioPlayer(self, didUpdateContext: self.context)
        }
    }

    /// Provides thread-safe updates for the player's context and makes sure to forward any updates
    /// to the the delegate
    private func updateContext(
        _ newContextProvider: (inout AudioPlaybackContext) -> Void
    ) {
        _context.mutate { value in
            newContextProvider(&value)
        }
        delegate?.audioPlayer(self, didUpdateContext: context)
    }

    /// It's used by the assetPropertyLoader to provide information when the propertyLoading has been
    /// completed.
    private func handleDurationLoading(
        _ result: Result<TimeInterval, Error>,
        asset: AVURLAsset
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.handleDurationLoading(result, asset: asset)
            }
            return
        }

        switch result {
        /// If the assetPropertyLoaded managed to successfully load the asset's duration information
        /// we update the context with the new information.
        case let .success(duration):
            player.replaceCurrentItem(with: .init(asset: asset))
            updateContext { value in
                value.duration = duration
                value.currentTime = 0
                value.rate = .zero
                value.isSeeking = false
            }

            player.play()

        /// If the assetPropertyLoaded failed to load the asset's duration information we update the
        /// context with the notLoaded state in order and we log a debug error message
        case let .failure(error):
            updateContext { value in
                value.duration = 0
                value.currentTime = 0
                value.rate = .zero
                value.state = .notLoaded
                value.isSeeking = false
            }
            log.debug(error.localizedDescription)
        }
    }

    /// Once a seek task has been executed (and not debounced) we are performing the seek task
    /// on the player in order to progress the playback.
    private func executeSeek(
        to time: TimeInterval
    ) {
        guard
            Thread.isMainThread
        else {
            DispatchQueue.main.async { [weak self] in
                self?.executeSeek(to: time)
            }
            return
        }

        guard
            context.isSeeking,
            let currentItem = player.currentItem
        else {
            return
        }

        let currentTimescale = currentItem.currentTime().timescale
        player.seek(
            to: CMTimeMakeWithSeconds(
                time,
                preferredTimescale: currentTimescale
            ),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )

        updateContext { value in value.isSeeking = false }
        play()
    }

    // MARK: - AudioPlaying

    func loadAsset(
        from url: URL?,
        delegate: AudioPlayingDelegate
    ) {
        if let url = url,
           let currentItem = player.currentItem?.asset as? AVURLAsset,
           url == currentItem.url {
            /// If the currentItem is paused, we want to continue the playback
            /// Otherwise, no action is required
            if context.state == .paused {
                player.play()
            }

            return
        }

        /// We call stop to update the currently set delegate that the playback has been stopped
        /// and then we remove the current item from the player's queue.
        stop()
        player.replaceCurrentItem(with: nil)

        if let url = url {
            self.delegate = delegate
            updateContext { $0.state = .loading }
            let asset = AVURLAsset(url: url)

            assetPropertyLoader.loadProperty(
                .duration,
                of: asset,
                onSuccessTransformer: { TimeInterval($0.duration.seconds) },
                completion: { [weak self] in self?.handleDurationLoading($0, asset: asset) }
            )
        }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func stop() {
        /// As the AVPlayer doesn't provide an API to actually stop the playback, we are simulating it
        /// by calling pause
        player.pause()

        updateContext { value in
            value = .init(
                duration: value.duration,
                currentTime: 0,
                state: .stopped,
                rate: .zero,
                isSeeking: false
            )
        }
    }

    func updateRate() {
        /// The allowed rates that the user can toggle on the player are defined on the
        /// ``AudioPlaybackRate`` and the player uses them to toggle between them by using the
        /// ``AudioPlaybackRate.next`` variable
        player.rate = context.rate.next.rawValue
    }

    func seek(
        to time: TimeInterval
    ) {
        player.pause()
        updateContext { value in
            value.currentTime = time
            value.state = .paused
            value.isSeeking = true
        }

        debouncer.debounce { [weak self] in self?.executeSeek(to: time) }
    }
}
