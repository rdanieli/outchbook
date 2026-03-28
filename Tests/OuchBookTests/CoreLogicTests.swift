import Foundation
import Testing
@testable import OuchBook

private final class ImpactProfileRecorder: @unchecked Sendable {
    var profile: ImpactProfile?
}

private final class FakeAccelerometerProvider: AccelerometerProvider, @unchecked Sendable {
    let availability: AccelerometerAvailability = .available(.appleSiliconHID)
    private var handler: ((AccelerometerReading) -> Void)?

    func start(_ handler: @escaping (AccelerometerReading) -> Void) throws {
        self.handler = handler
    }

    func stop() {}

    func emit(_ reading: AccelerometerReading) {
        handler?(reading)
    }
}

private final class FakeSleepMonitor: SleepMonitor, @unchecked Sendable {
    private var handler: (() -> Void)?

    func start(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func stop() {}

    func emitSleep() {
        handler?()
    }
}

private final class FakeAudioPlayer: AudioPlayerControlling, @unchecked Sendable {
    let url: URL
    var volume: Float = 0
    var enableRate = false
    var rate: Float = 1
    private(set) var prepareToPlayCalls = 0
    private(set) var playCalls = 0

    init(url: URL) {
        self.url = url
    }

    func prepareToPlay() -> Bool {
        prepareToPlayCalls += 1
        return true
    }

    @discardableResult
    func play() -> Bool {
        playCalls += 1
        return true
    }
}

private final class FakeAudioPlayerFactory: AudioPlayerFactory, @unchecked Sendable {
    private(set) var createdPlayers: [URL: FakeAudioPlayer] = [:]

    func makePlayer(for url: URL) throws -> any AudioPlayerControlling {
        let player = FakeAudioPlayer(url: url)
        createdPlayers[url] = player
        return player
    }
}

private final class FakePlaybackEngine: ScreamPlaybackControlling, @unchecked Sendable {
    private(set) var preloadedFileNames: [[String]] = []
    private(set) var playedProfiles: [ImpactProfile] = []

    func preload(fileNames: [String]) {
        preloadedFileNames.append(fileNames)
    }

    @discardableResult
    func play(_ profile: ImpactProfile) -> Bool {
        playedProfiles.append(profile)
        return true
    }
}

private final class FakeCoreRuntime: OuchBookCoreControlling, @unchecked Sendable {
    private(set) var startCalls = 0
    private(set) var stopCalls = 0
    var startError: Error?

    func start() throws {
        startCalls += 1
        if let startError {
            throw startError
        }
    }

    func stop() {
        stopCalls += 1
    }
}

private final class InMemoryAppPreferences: AppPreferencesStoring, @unchecked Sendable {
    var boolValues: [String: Bool] = [:]
    var doubleValues: [String: Double] = [:]

    func containsValue(forKey key: String) -> Bool {
        boolValues[key] != nil || doubleValues[key] != nil
    }

    func bool(forKey key: String) -> Bool {
        boolValues[key] ?? false
    }

    func double(forKey key: String) -> Double {
        doubleValues[key] ?? 0
    }

    func set(_ value: Bool, forKey key: String) {
        boolValues[key] = value
    }

    func set(_ value: Double, forKey key: String) {
        doubleValues[key] = value
    }
}

private final class FakeLaunchAtLoginManager: LaunchAtLoginManaging, @unchecked Sendable {
    var isEnabled = false
    private(set) var enableCalls = 0
    private(set) var disableCalls = 0

    func setEnabled(_ enabled: Bool) throws {
        isEnabled = enabled
        if enabled {
            enableCalls += 1
        } else {
            disableCalls += 1
        }
    }
}

@Test func motionWindowBufferEvictsReadingsOutsideConfiguredWindow() throws {
    let buffer = MotionWindowBuffer(windowDuration: 0.300)

    buffer.append(.init(timestamp: 0.000, x: 0.1, y: 0.0, z: 0.0))
    buffer.append(.init(timestamp: 0.100, x: 0.4, y: 0.0, z: 0.0))
    buffer.append(.init(timestamp: 0.310, x: 0.8, y: 0.0, z: 0.0))

    #expect(buffer.readings.count == 2)
    #expect(buffer.readings.map(\.timestamp) == [0.100, 0.310])
}

@Test func motionWindowBufferReturnsPeakMagnitudeWithinWindow() throws {
    let buffer = MotionWindowBuffer(windowDuration: 0.300)

    buffer.append(.init(timestamp: 1.000, x: 0.2, y: 0.1, z: 0.0))
    buffer.append(.init(timestamp: 1.100, x: 0.3, y: 0.4, z: 0.0))
    buffer.append(.init(timestamp: 1.150, x: 1.2, y: 0.0, z: 0.0))

    #expect(buffer.peakMagnitude() == 1.2)
}

@Test func impactProfileMapperChoosesAudioTierAndScalesPlayback() throws {
    let mapper = ImpactProfileMapper(
        softThreshold: 0.8,
        aggressiveThreshold: 1.8
    )

    let soft = mapper.profile(forPeakMagnitude: 0.5, masterVolume: 0.6)
    #expect(soft.tier == .gentle)
    #expect(soft.fileName == "ow-soft.mp3")
    #expect(soft.volume == 0.18)
    #expect(soft.pitchMultiplier == 0.95)

    let normal = mapper.profile(forPeakMagnitude: 1.0, masterVolume: 0.6)
    #expect(normal.tier == .normal)
    #expect(normal.fileName == "ow.mp3")
    #expect(normal.volume == 0.36)
    #expect(normal.pitchMultiplier == 1.1)

    let aggressive = mapper.profile(forPeakMagnitude: 2.4, masterVolume: 0.6)
    #expect(aggressive.tier == .aggressive)
    #expect(aggressive.fileName == "ouch-scream.mp3")
    #expect(aggressive.volume == 0.6)
    #expect(aggressive.pitchMultiplier == 1.35)
}

@Test func lidCloseImpactAnalyzerUsesRecentPeakToChooseProfile() throws {
    let buffer = MotionWindowBuffer(windowDuration: 0.300)
    let analyzer = LidCloseImpactAnalyzer(
        buffer: buffer,
        mapper: ImpactProfileMapper(
            softThreshold: 0.8,
            aggressiveThreshold: 1.8
        )
    )

    buffer.append(.init(timestamp: 2.000, x: 0.1, y: 0.0, z: 0.0))
    buffer.append(.init(timestamp: 2.150, x: 1.1, y: 0.0, z: 0.0))
    buffer.append(.init(timestamp: 2.400, x: 0.3, y: 0.0, z: 0.0))

    let profile = analyzer.profileForLidClose(masterVolume: 0.5)

    #expect(profile.tier == .normal)
    #expect(profile.fileName == "ow.mp3")
    #expect(profile.volume == 0.3)
}

@Test func appleSiliconReportDecoderExtractsXYZFromHIDPayload() throws {
    let bytes: [UInt8] = [
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x01, 0x00,
        0x00, 0x00, 0xFE, 0xFF,
        0x00, 0x80, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
    ]

    let reading = try #require(AppleSiliconAccelerometerReportDecoder.decode(bytes, timestamp: 10.0))

    #expect(reading.timestamp == 10.0)
    #expect(reading.x == 1.0)
    #expect(reading.y == -2.0)
    #expect(reading.z == 0.5)
}

@Test func accelerometerBackendResolverPrefersAppleSiliconHIDOnlyOnAppleSilicon() throws {
    #expect(AccelerometerBackendResolver.backend(for: .appleSilicon) == .appleSiliconHID)
    #expect(AccelerometerBackendResolver.backend(for: .intel) == .unsupported)
    #expect(AccelerometerBackendResolver.backend(for: .unknown) == .unsupported)
}

@Test func sleepEventCoordinatorEmitsProfileChosenFromBufferedImpact() throws {
    let buffer = MotionWindowBuffer(windowDuration: 0.300)
    buffer.append(.init(timestamp: 4.000, x: 0.1, y: 0.0, z: 0.0))
    buffer.append(.init(timestamp: 4.100, x: 2.0, y: 0.0, z: 0.0))

    let analyzer = LidCloseImpactAnalyzer(
        buffer: buffer,
        mapper: ImpactProfileMapper(
            softThreshold: 0.8,
            aggressiveThreshold: 1.8
        )
    )

    let recorder = ImpactProfileRecorder()
    let coordinator = SleepEventCoordinator(analyzer: analyzer) { profile in
        recorder.profile = profile
    }

    coordinator.handleSleep(masterVolume: 0.4)

    #expect(recorder.profile?.tier == .aggressive)
    #expect(recorder.profile?.volume == 0.4)
    #expect(recorder.profile?.fileName == "ouch-scream.mp3")
}

@Test func ouchBookCoreControllerMapsSleepEventFromBufferedSamples() throws {
    let provider = FakeAccelerometerProvider()
    let sleepMonitor = FakeSleepMonitor()
    let recorder = ImpactProfileRecorder()

    let controller = OuchBookCoreController(
        provider: provider,
        sleepMonitor: sleepMonitor,
        mapper: ImpactProfileMapper(
            softThreshold: 0.8,
            aggressiveThreshold: 1.8
        ),
        masterVolumeProvider: { 0.5 },
        onImpactProfileChosen: { profile in
            recorder.profile = profile
        }
    )

    try controller.start()
    provider.emit(.init(timestamp: 8.000, x: 0.2, y: 0.0, z: 0.0))
    provider.emit(.init(timestamp: 8.120, x: 2.1, y: 0.0, z: 0.0))
    sleepMonitor.emitSleep()

    #expect(recorder.profile?.tier == .aggressive)
    #expect(recorder.profile?.volume == 0.5)
    #expect(recorder.profile?.fileName == "ouch-scream.mp3")
}

@Test func screamPlaybackEnginePreloadsAndCachesResolvedPlayers() throws {
    let factory = FakeAudioPlayerFactory()
    let softURL = URL(fileURLWithPath: "/tmp/ow-soft.mp3")
    let normalURL = URL(fileURLWithPath: "/tmp/ow.mp3")

    let engine = ScreamPlaybackEngine(
        resourceResolver: { fileName -> URL? in
            switch fileName {
            case "ow-soft.mp3":
                return softURL
            case "ow.mp3":
                return normalURL
            default:
                return nil
            }
        },
        playerFactory: factory
    )

    engine.preload(fileNames: ["ow-soft.mp3", "ow.mp3", "ow-soft.mp3"])

    #expect(factory.createdPlayers.count == 2)
    #expect(factory.createdPlayers[softURL]?.prepareToPlayCalls == 1)
    #expect(factory.createdPlayers[normalURL]?.prepareToPlayCalls == 1)
}

@Test func screamPlaybackEngineConfiguresVolumeAndRateBeforePlaying() throws {
    let factory = FakeAudioPlayerFactory()
    let screamURL = URL(fileURLWithPath: "/tmp/ouch-scream.mp3")
    let engine = ScreamPlaybackEngine(
        resourceResolver: { fileName -> URL? in
            fileName == "ouch-scream.mp3" ? screamURL : nil
        },
        playerFactory: factory
    )

    let didPlay = engine.play(
        ImpactProfile(
            tier: .aggressive,
            fileName: "ouch-scream.mp3",
            volume: 0.75,
            pitchMultiplier: 1.25
        )
    )

    let player = try #require(factory.createdPlayers[screamURL])
    #expect(didPlay == true)
    #expect(player.enableRate == true)
    #expect(player.volume == 0.75)
    #expect(player.rate == 1.25)
    #expect(player.playCalls == 1)
}

@Test func screamPlaybackEngineSkipsPlaybackWhenResourceIsMissing() throws {
    let engine = ScreamPlaybackEngine(
        resourceResolver: { _ -> URL? in nil },
        playerFactory: FakeAudioPlayerFactory()
    )

    let didPlay = engine.play(
        ImpactProfile(
            tier: .gentle,
            fileName: "missing.mp3",
            volume: 0.2,
            pitchMultiplier: 1.0
        )
    )

    #expect(didPlay == false)
}

@MainActor
@Test func appStateEnableStartsRuntimeAndPreloadsAudioCatalog() throws {
    let runtime = FakeCoreRuntime()
    let playback = FakePlaybackEngine()
    let appState = AppState(runtime: runtime, playback: playback)

    try appState.setEnabled(true)

    #expect(appState.isEnabled == true)
    #expect(runtime.startCalls == 1)
    #expect(playback.preloadedFileNames == [["ow-soft.mp3", "ow.mp3", "ouch-scream.mp3"]])
}

@MainActor
@Test func appStateDisableStopsRuntime() throws {
    let runtime = FakeCoreRuntime()
    let playback = FakePlaybackEngine()
    let appState = AppState(runtime: runtime, playback: playback)

    try appState.setEnabled(true)
    try appState.setEnabled(false)

    #expect(appState.isEnabled == false)
    #expect(runtime.stopCalls == 1)
}

@MainActor
@Test func appStateDoesNotStayEnabledWhenRuntimeStartFails() throws {
    enum SampleError: Error {
        case failed
    }

    let runtime = FakeCoreRuntime()
    runtime.startError = SampleError.failed

    let appState = AppState(
        runtime: runtime,
        playback: FakePlaybackEngine()
    )

    #expect(throws: SampleError.self) {
        try appState.setEnabled(true)
    }
    #expect(appState.isEnabled == false)
}

@MainActor
@Test func appStateRoutesChosenImpactProfileToPlaybackEngine() throws {
    let runtime = FakeCoreRuntime()
    let playback = FakePlaybackEngine()
    let appState = AppState(runtime: runtime, playback: playback)

    appState.handleChosenProfile(
        ImpactProfile(
            tier: .normal,
            fileName: "ow.mp3",
            volume: 0.4,
            pitchMultiplier: 1.1
        )
    )

    #expect(playback.playedProfiles.count == 1)
    #expect(playback.playedProfiles.first?.fileName == "ow.mp3")
}

@MainActor
@Test func appStateExposesReadableUnsupportedHardwareStatus() throws {
    let appState = AppState(
        runtime: FakeCoreRuntime(),
        playback: FakePlaybackEngine(),
        availability: .unsupported("No supported accelerometer backend.")
    )

    #expect(appState.supportStatusText == "No supported accelerometer backend.")
}

@MainActor
@Test func appStateExposesReadyStatusWhenAccelerometerIsAvailable() throws {
    let appState = AppState(
        runtime: FakeCoreRuntime(),
        playback: FakePlaybackEngine(),
        availability: .available(.appleSiliconHID)
    )

    #expect(appState.supportStatusText == "Accelerometer ready.")
}

@MainActor
@Test func appStateLoadsPersistedVolumeAndLaunchAtLoginSettings() throws {
    let preferences = InMemoryAppPreferences()
    preferences.doubleValues[AppState.PreferenceKeys.masterVolume] = 0.42
    preferences.boolValues[AppState.PreferenceKeys.launchAtLoginEnabled] = true

    let launchManager = FakeLaunchAtLoginManager()
    let appState = AppState(
        runtime: FakeCoreRuntime(),
        playback: FakePlaybackEngine(),
        availability: .available(.appleSiliconHID),
        preferences: preferences,
        launchAtLoginManager: launchManager
    )

    #expect(appState.masterVolume == 0.42)
    #expect(appState.launchAtLoginEnabled == true)
}

@MainActor
@Test func appStatePersistsMasterVolumeChanges() throws {
    let preferences = InMemoryAppPreferences()
    let appState = AppState(
        runtime: FakeCoreRuntime(),
        playback: FakePlaybackEngine(),
        preferences: preferences,
        launchAtLoginManager: FakeLaunchAtLoginManager()
    )

    appState.setMasterVolume(0.33)

    #expect(appState.masterVolume == 0.33)
    #expect(preferences.doubleValues[AppState.PreferenceKeys.masterVolume] == 0.33)
}

@MainActor
@Test func appStateUpdatesLaunchAtLoginAndPersistsChoice() throws {
    let preferences = InMemoryAppPreferences()
    let launchManager = FakeLaunchAtLoginManager()
    let appState = AppState(
        runtime: FakeCoreRuntime(),
        playback: FakePlaybackEngine(),
        preferences: preferences,
        launchAtLoginManager: launchManager
    )

    try appState.setLaunchAtLoginEnabled(true)

    #expect(appState.launchAtLoginEnabled == true)
    #expect(launchManager.enableCalls == 1)
    #expect(preferences.boolValues[AppState.PreferenceKeys.launchAtLoginEnabled] == true)
}

@MainActor
@Test func appStateRestoresPersistedEnabledStateOnLaunch() throws {
    let preferences = InMemoryAppPreferences()
    preferences.boolValues[AppState.PreferenceKeys.isEnabled] = true

    let runtime = FakeCoreRuntime()
    let playback = FakePlaybackEngine()
    let appState = AppState(
        runtime: runtime,
        playback: playback,
        preferences: preferences,
        launchAtLoginManager: FakeLaunchAtLoginManager()
    )

    appState.restoreIfNeededOnLaunch()

    #expect(runtime.startCalls == 1)
    #expect(playback.preloadedFileNames == [["ow-soft.mp3", "ow.mp3", "ouch-scream.mp3"]])
    #expect(appState.isEnabled == true)
}

@MainActor
@Test func appStateDisablesPersistedEnabledStateIfRestoreFails() throws {
    enum RestoreError: Error {
        case failed
    }

    let preferences = InMemoryAppPreferences()
    preferences.boolValues[AppState.PreferenceKeys.isEnabled] = true

    let runtime = FakeCoreRuntime()
    runtime.startError = RestoreError.failed

    let appState = AppState(
        runtime: runtime,
        playback: FakePlaybackEngine(),
        preferences: preferences,
        launchAtLoginManager: FakeLaunchAtLoginManager()
    )

    appState.restoreIfNeededOnLaunch()

    #expect(appState.isEnabled == false)
    #expect(preferences.boolValues[AppState.PreferenceKeys.isEnabled] == false)
}
