import Combine
import Foundation

public protocol OuchBookCoreControlling: AnyObject, Sendable {
    func start() throws
    func stop()
}

public protocol ScreamPlaybackControlling: AnyObject, Sendable {
    func preload(fileNames: [String])
    func play(_ profile: ImpactProfile) -> Bool
}

extension OuchBookCoreController: OuchBookCoreControlling {}
extension ScreamPlaybackEngine: ScreamPlaybackControlling {}

@MainActor
public final class AppState: ObservableObject {
    public enum PreferenceKeys {
        public static let isEnabled = "ouchbook.isEnabled"
        public static let masterVolume = "ouchbook.masterVolume"
        public static let launchAtLoginEnabled = "ouchbook.launchAtLoginEnabled"
    }

    public static let bundledAudioFileNames = [
        "ow-soft.mp3",
        "ow.mp3",
        "ouch-scream.mp3",
    ]

    @Published public private(set) var isEnabled: Bool
    @Published public var masterVolume: Double
    @Published public private(set) var lastPlaybackSucceeded: Bool?
    @Published public private(set) var launchAtLoginEnabled: Bool
    @Published public private(set) var lastErrorMessage: String?
    public let availability: AccelerometerAvailability

    private let runtime: OuchBookCoreControlling
    private let playback: ScreamPlaybackControlling
    private let preferences: AppPreferencesStoring
    private let launchAtLoginManager: LaunchAtLoginManaging

    public init(
        runtime: OuchBookCoreControlling,
        playback: ScreamPlaybackControlling,
        availability: AccelerometerAvailability = .unsupported("Accelerometer not configured."),
        preferences: AppPreferencesStoring = UserDefaults.standard,
        launchAtLoginManager: LaunchAtLoginManaging = MainAppLaunchAtLoginManager(),
        isEnabled: Bool? = nil,
        masterVolume: Double? = nil
    ) {
        self.runtime = runtime
        self.playback = playback
        self.availability = availability
        self.preferences = preferences
        self.launchAtLoginManager = launchAtLoginManager
        self.isEnabled = isEnabled ?? preferences.bool(forKey: PreferenceKeys.isEnabled)
        if let masterVolume {
            self.masterVolume = masterVolume
        } else if preferences.containsValue(forKey: PreferenceKeys.masterVolume) {
            self.masterVolume = preferences.double(forKey: PreferenceKeys.masterVolume)
        } else {
            self.masterVolume = 1.0
        }
        if preferences.containsValue(forKey: PreferenceKeys.launchAtLoginEnabled) {
            self.launchAtLoginEnabled = preferences.bool(forKey: PreferenceKeys.launchAtLoginEnabled)
        } else {
            self.launchAtLoginEnabled = launchAtLoginManager.isEnabled
        }
        self.lastPlaybackSucceeded = nil
        self.lastErrorMessage = nil
    }

    public var supportStatusText: String {
        switch availability {
        case .available:
            "Accelerometer ready."
        case let .unsupported(message):
            message
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        guard enabled != isEnabled else {
            return
        }

        do {
            if enabled {
                playback.preload(fileNames: Self.bundledAudioFileNames)
                try runtime.start()
            } else {
                runtime.stop()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }

        isEnabled = enabled
        preferences.set(enabled, forKey: PreferenceKeys.isEnabled)
        lastErrorMessage = nil
    }

    public func handleChosenProfile(_ profile: ImpactProfile) {
        lastPlaybackSucceeded = playback.play(profile)
    }

    public func restoreIfNeededOnLaunch() {
        guard isEnabled else {
            return
        }

        do {
            playback.preload(fileNames: Self.bundledAudioFileNames)
            try runtime.start()
            lastErrorMessage = nil
        } catch {
            isEnabled = false
            preferences.set(false, forKey: PreferenceKeys.isEnabled)
            lastErrorMessage = error.localizedDescription
        }
    }

    public func setMasterVolume(_ volume: Double) {
        let clampedVolume = min(max(volume, 0), 1)
        masterVolume = clampedVolume
        preferences.set(clampedVolume, forKey: PreferenceKeys.masterVolume)
    }

    public func setLaunchAtLoginEnabled(_ enabled: Bool) throws {
        do {
            try launchAtLoginManager.setEnabled(enabled)
            launchAtLoginEnabled = enabled
            preferences.set(enabled, forKey: PreferenceKeys.launchAtLoginEnabled)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }
}
