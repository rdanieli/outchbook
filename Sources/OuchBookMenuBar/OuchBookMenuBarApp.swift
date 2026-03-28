import AppKit
import OuchBook
import SwiftUI

final class OuchBookAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct OuchBookMenuBarApp: App {
    @NSApplicationDelegateAdaptor(OuchBookAppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState

    init() {
        _appState = StateObject(wrappedValue: LiveAppFactory.makeAppState(bundle: Self.resourceBundle))
    }

    private static var resourceBundle: Bundle {
        if
            let resourceURL = Bundle.main.resourceURL,
            let packagedBundle = Bundle(url: resourceURL.appendingPathComponent("OuchBook_OuchBook.bundle"))
        {
            return packagedBundle
        }

        return .main
    }

    var body: some Scene {
        MenuBarExtra("OuchBook", systemImage: "speaker.wave.2.fill") {
            MenuBarMenuView(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarMenuView: View {
    @ObservedObject var appState: AppState

    private var isUnsupported: Bool {
        if case .unsupported = appState.availability {
            return true
        }

        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OuchBook")
                .font(.headline)

            Text(appState.supportStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let lastErrorMessage = appState.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Enabled", isOn: Binding(
                get: { appState.isEnabled },
                set: { newValue in
                    do {
                        try appState.setEnabled(newValue)
                    } catch {
                        _ = error
                    }
                }
            ))
            .disabled(isUnsupported)

            VStack(alignment: .leading, spacing: 6) {
                Text("Volume")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { appState.masterVolume },
                        set: { appState.setMasterVolume($0) }
                    ),
                    in: 0...1
                )
            }

            Divider()

            Toggle("Launch at Login", isOn: Binding(
                get: { appState.launchAtLoginEnabled },
                set: { newValue in
                    do {
                        try appState.setLaunchAtLoginEnabled(newValue)
                    } catch {
                        _ = error
                    }
                }
            ))

            Button("About OuchBook") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(options: [
                    .applicationName: "OuchBook",
                    .applicationVersion: "0.1.0",
                ])
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 260)
    }
}
