import AppKit
import OuchBook
import SwiftUI

private func makeInstalledResourceBundle() -> Bundle {
    if
        let resourceURL = Bundle.main.resourceURL,
        let packagedBundle = Bundle(url: resourceURL.appendingPathComponent("OuchBook_OuchBook.bundle"))
    {
        return packagedBundle
    }

    return .main
}

final class OuchBookAppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let appState = LiveAppFactory.makeAppState(bundle: makeInstalledResourceBundle())
        self.appState = appState
        statusBarController = StatusBarController(appState: appState)
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    init(appState: AppState) {
        super.init()

        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 280, height: 260)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarMenuView(appState: appState)
        )

        if let button = statusItem.button {
            button.title = "OB"
            if let image = NSImage(
                systemSymbolName: "speaker.wave.2.fill",
                accessibilityDescription: "OuchBook"
            ) {
                image.isTemplate = true
                button.image = image
            }

            button.target = self
            button.action = #selector(togglePopover(_:))
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

@main
struct OuchBookMenuBarApp: App {
    @NSApplicationDelegateAdaptor(OuchBookAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
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
