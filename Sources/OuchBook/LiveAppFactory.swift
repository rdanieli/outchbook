import Foundation

@MainActor
public enum LiveAppFactory {
    private static let defaultResourceBundle = Bundle.module

    private final class StateBridge: @unchecked Sendable {
        weak var appState: AppState?
    }

    public static func makeAppState(bundle: Bundle) -> AppState {
        let provider = DefaultAccelerometerProviderFactory.makeDefault()
        let availability = provider.availability
        let playback = ScreamPlaybackEngine(bundle: bundle)
        let sleepMonitor = WorkspaceSleepMonitor()
        let bridge = StateBridge()

        let runtime = OuchBookCoreController(
            provider: provider,
            sleepMonitor: sleepMonitor,
            mapper: ImpactProfileMapper(),
            masterVolumeProvider: { [bridge] in
                bridge.appState?.masterVolume ?? 1.0
            },
            onImpactProfileChosen: { [bridge] profile in
                Task { @MainActor in
                    bridge.appState?.handleChosenProfile(profile)
                }
            }
        )

        let appState = AppState(
            runtime: runtime,
            playback: playback,
            availability: availability
        )

        bridge.appState = appState
        appState.restoreIfNeededOnLaunch()
        return appState
    }

    public static func makeAppState() -> AppState {
        makeAppState(bundle: defaultResourceBundle)
    }
}
