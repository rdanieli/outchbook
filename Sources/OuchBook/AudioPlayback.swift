import AVFAudio
import Foundation

public protocol AudioPlayerControlling: AnyObject, Sendable {
    var volume: Float { get set }
    var enableRate: Bool { get set }
    var rate: Float { get set }
    func prepareToPlay() -> Bool
    func play() -> Bool
}

public protocol AudioPlayerFactory: Sendable {
    func makePlayer(for url: URL) throws -> any AudioPlayerControlling
}

public struct AVAudioPlayerFactory: AudioPlayerFactory {
    public init() {}

    public func makePlayer(for url: URL) throws -> any AudioPlayerControlling {
        try AVAudioBackedPlayer(url: url)
    }
}

public final class AVAudioBackedPlayer: AudioPlayerControlling, @unchecked Sendable {
    private let player: AVAudioPlayer

    public var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    public var enableRate: Bool {
        get { player.enableRate }
        set { player.enableRate = newValue }
    }

    public var rate: Float {
        get { player.rate }
        set { player.rate = newValue }
    }

    public init(url: URL) throws {
        self.player = try AVAudioPlayer(contentsOf: url)
    }

    public func prepareToPlay() -> Bool {
        player.prepareToPlay()
    }

    public func play() -> Bool {
        player.play()
    }
}

public final class ScreamPlaybackEngine: @unchecked Sendable {
    private static let defaultResourceBundle = Bundle.module

    private let resourceResolver: @Sendable (String) -> URL?
    private let playerFactory: AudioPlayerFactory
    private var playersByFileName: [String: any AudioPlayerControlling] = [:]

    public init(
        resourceResolver: @escaping @Sendable (String) -> URL?,
        playerFactory: AudioPlayerFactory
    ) {
        self.resourceResolver = resourceResolver
        self.playerFactory = playerFactory
    }

    public convenience init(bundle: Bundle) {
        self.init(
            resourceResolver: { fileName in
                let fileURL = URL(fileURLWithPath: fileName)
                return bundle.url(forResource: fileURL.deletingPathExtension().lastPathComponent, withExtension: fileURL.pathExtension)
            },
            playerFactory: AVAudioPlayerFactory()
        )
    }

    public convenience init() {
        self.init(bundle: Self.defaultResourceBundle)
    }

    public func preload(fileNames: [String]) {
        for fileName in Set(fileNames) {
            _ = loadPlayerIfNeeded(for: fileName)
        }
    }

    @discardableResult
    public func play(_ profile: ImpactProfile) -> Bool {
        guard let player = loadPlayerIfNeeded(for: profile.fileName) else {
            return false
        }

        player.enableRate = true
        player.volume = Float(profile.volume)
        player.rate = Float(profile.pitchMultiplier)
        return player.play()
    }

    private func loadPlayerIfNeeded(for fileName: String) -> (any AudioPlayerControlling)? {
        if let cached = playersByFileName[fileName] {
            return cached
        }

        guard let url = resourceResolver(fileName) else {
            return nil
        }

        guard let player = try? playerFactory.makePlayer(for: url) else {
            return nil
        }

        _ = player.prepareToPlay()
        playersByFileName[fileName] = player
        return player
    }
}
