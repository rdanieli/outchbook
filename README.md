# OuchBook

OuchBook is a macOS menu bar app that screams in pain when you close your MacBook lid.

The idea is intentionally absurd, but the app is built around a real signal path:

- continuously read recent motion data from the laptop accelerometer,
- keep a rolling 300 ms buffer of those samples,
- observe lid-close motion before the lid is fully shut,
- combine motion intensity with lid-close speed,
- map that impact to a pain tier,
- immediately play a matching scream sound.

The current implementation targets macOS 13+ and is focused on Apple Silicon laptops with a detectable accelerometer exposed through `IOKit` / `IOHID`.

## Current Status

This repository already contains a working first version of the app shell, core pipeline, and distribution website:

- macOS menu bar app with an AppKit `NSStatusItem` shell and SwiftUI content
- no Dock icon (`LSUIElement`)
- rolling motion buffer and impact analysis
- Apple Silicon HID accelerometer backend
- lid-angle based pre-close trigger path
- scream tier mapping for gentle, normal, and aggressive closes
- audio preload and playback via `AVAudioPlayer`
- persisted settings for enabled state, volume, and launch at login
- app bundle packaging script
- static marketing/distribution site in `website/`

This is still an early product build rather than a polished public release. The important architecture is in place, but there are still practical limitations and shipping work left.

## What OuchBook Does

When OuchBook is enabled:

1. It starts sampling accelerometer readings from the machine.
2. It stores only the most recent `300 ms` of readings.
3. It watches for a real lid-closing motion before the Mac reaches full closure.
4. It combines recent motion with lid closing speed.
5. It maps the result to one of three sound profiles:
   - gentle close -> soft `ow...`
   - normal close -> `OW!`
   - aggressive close -> full scream
6. It starts playback as a pre-close effect before sleep fully takes over.

## Supported Environment

### OS

- macOS 13+

### Hardware

Current implementation status:

- Apple Silicon MacBook: primary target
- Intel MacBook: currently treated as unsupported
- Desktop Macs: unsupported

### Distribution Model

The project is designed for direct distribution outside the Mac App Store.

That matters because the accelerometer approach relies on low-level hardware access patterns that are not a good fit for App Store distribution.

## Important Caveats

Before treating this as production-ready software, keep these constraints in mind:

- The current sensor integration is tuned for Apple Silicon MacBooks.
- The app is designed as a pre-close effect, not a post-sleep playback trick.
- Hardware access may behave differently across MacBook models and OS releases.
- The app bundle is ad-hoc signed for local/dev distribution. It is not notarized yet.
- The direct-download site is present in-repo, but the final PayPal checkout URL still needs to be set for public launch.

## Repository Layout

```text
.
├── Package.swift
├── README.md
├── Sources
│   ├── OuchBook
│   │   ├── AppState.swift
│   │   ├── AudioPlayback.swift
│   │   ├── CoreLogic.swift
│   │   ├── LiveAppFactory.swift
│   │   ├── Runtime.swift
│   │   ├── SystemIntegration.swift
│   │   ├── macOSIntegration.swift
│   │   └── Resources
│   │       ├── ow-soft.mp3
│   │       ├── ow.mp3
│   │       ├── tier3-agony.mp3
│   │       ├── tier3-why-distorted.mp3
│   │       ├── tier3-soul-out.mp3
│   │       └── tier3-not-again.mp3
│   └── OuchBookMenuBar
│       └── OuchBookMenuBarApp.swift
├── Support
│   └── Info.plist
├── Tests
│   └── OuchBookTests
│       └── CoreLogicTests.swift
├── scripts
│   └── build-app.sh
├── website
│   ├── index.html
│   ├── download.html
│   ├── compatibility.html
│   ├── paypal-manual-license.html
│   ├── styles.css
│   └── assets
└── dist
    └── OuchBook.app (generated output)
```

## Architecture Overview

The app is split into small layers so the hardware-specific pieces stay isolated from the app state and UI.

### 1. Core signal processing

Key file: `Sources/OuchBook/CoreLogic.swift`

This layer defines:

- `AccelerometerReading`
- `MotionWindowBuffer`
- `ImpactProfile`
- `ImpactProfileMapper`
- `LidCloseImpactAnalyzer`
- `AppleSiliconAccelerometerReportDecoder`

Responsibilities:

- represent raw motion samples,
- keep only the last `300 ms`,
- compute peak magnitude,
- map that peak to one of the three audio tiers.

### 2. Runtime orchestration

Key file: `Sources/OuchBook/Runtime.swift`

This layer defines:

- `AccelerometerProvider`
- `SleepMonitor`
- `OuchBookCoreController`

Responsibilities:

- start and stop live hardware monitoring,
- route accelerometer readings into the motion buffer,
- react to lid-close trigger events,
- produce the chosen impact profile.

### 3. macOS integrations

Key file: `Sources/OuchBook/macOSIntegration.swift`

This layer contains:

- `AppleSiliconHIDAccelerometerProvider`
- lid-angle and power-related monitors
- fallback unsupported provider behavior

Responsibilities:

- connect to Apple Silicon HID devices through `IOKit.hid`,
- read lid-angle data where available,
- expose runtime availability to the rest of the app.

### 4. Playback

Key file: `Sources/OuchBook/AudioPlayback.swift`

This layer contains:

- `ScreamPlaybackEngine`
- `AVAudioBackedPlayer`
- player factory abstractions for testing

Responsibilities:

- preload bundled assets,
- cache players,
- set volume and playback rate,
- play the chosen scream as quickly as possible.

### 5. App state

Key file: `Sources/OuchBook/AppState.swift`

Responsibilities:

- hold UI-facing state,
- persist settings to `UserDefaults`,
- control enabled/disabled runtime state,
- manage launch-at-login preferences,
- expose human-readable support and error text.

### 6. Menu bar app shell

Key file: `Sources/OuchBookMenuBar/OuchBookMenuBarApp.swift`

Responsibilities:

- launch the app as a menu bar utility,
- hide the Dock icon,
- own the `NSStatusItem` and popover shell,
- render the menu content,
- connect the UI to `AppState`.

### 7. Static distribution site

Files:

- `website/index.html`
- `website/download.html`
- `website/compatibility.html`
- `website/paypal-manual-license.html`
- `website/styles.css`

Responsibilities:

- explain the product clearly,
- communicate compatibility and macOS limits honestly,
- document PayPal/manual-license fulfillment,
- provide install and download guidance for direct distribution.

## Menu Features

The current menu bar window includes:

- `Enabled` toggle
- `Volume` slider
- `Launch at Login` toggle
- support / unsupported status text
- error display
- `About OuchBook`
- `Quit`

## Audio Assets

OuchBook expects six bundled MP3 files:

- `ow-soft.mp3`
- `ow.mp3`
- `tier3-agony.mp3`
- `tier3-why-distorted.mp3`
- `tier3-soul-out.mp3`
- `tier3-not-again.mp3`

They live in:

- `Sources/OuchBook/Resources`

You can replace the current placeholder files with your own final assets as long as you keep the same filenames.

### Recommended asset characteristics

- short duration
- clean voice-only audio
- no music
- no background ambience
- distinct intensity between the three tiers

Suggested rough target lengths:

- `ow-soft.mp3`: `200-500 ms`
- `ow.mp3`: `150-400 ms`
- `tier3-agony.mp3`: `400-1200 ms`
- `tier3-why-distorted.mp3`: `400-1200 ms`
- `tier3-soul-out.mp3`: `400-1200 ms`
- `tier3-not-again.mp3`: `400-1200 ms`

## Build and Run

### Run tests

```bash
swift test
```

### Build the executable target

```bash
swift build
```

### Build the packaged app bundle

```bash
./scripts/build-app.sh
```

This creates:

```text
dist/OuchBook.app
```

## Static Website

The repository also includes a static distribution website in `website/`.

Key pages:

- `website/index.html`
- `website/download.html`
- `website/compatibility.html`
- `website/paypal-manual-license.html`

You can preview it locally by opening `website/index.html` in a browser or serving the folder with any static host.

`dist/` is generated by `scripts/build-app.sh` and should be treated as build output rather than source.

## Packaging

The packaging script:

- builds the `OuchBookMenuBar` release target,
- assembles a macOS `.app` bundle manually,
- copies the SwiftPM resource bundle into the app,
- applies an ad-hoc code signature.

This is intentionally lightweight and good for development/distribution experiments.

It is not yet a full release pipeline with:

- notarization
- hardened runtime tuning
- DMG generation
- auto-updates

## Launch at Login

Launch at login is implemented using:

- `ServiceManagement`
- `SMAppService`

The toggle is already wired into app state and menu UI.

Depending on the target environment, you may still need the usual final distribution validation for login item behavior.

## Testing

The project includes focused tests for the core behavior rather than broad UI automation.

Current coverage includes:

- motion window eviction
- peak magnitude extraction
- tier mapping
- HID report decoding
- runtime controller orchestration
- playback caching and configuration
- app state persistence
- app state restore-on-launch behavior
- launch-at-login state updates

Main test file:

- `Tests/OuchBookTests/CoreLogicTests.swift`

## Development Notes

### Why not CoreMotion?

CoreMotion is not the path used here because the app depends on Mac hardware sensors exposed through lower-level `IOKit` / HID behavior, not the simpler public mobile-style motion APIs.

### Why direct distribution?

This project is intended for direct distribution because the hardware access model is much easier to iterate outside the App Store.

### Why Swift Package Manager?

The repository currently uses SwiftPM for fast iteration, testing, packaging, and to keep the app and website in a lightweight single-repo setup.

## Known Limitations

- Intel support is not implemented yet.
- Some Apple Silicon sensor behavior still varies by model.
- The scream is intended as a pre-close effect and can still be cut if the lid reaches forced sleep too quickly.
- No telemetry, crash reporting, or auto-update system is included yet.
- No licensing or activation UI is implemented yet, even though the broader product plan includes it.
- The app has not yet been notarized for public distribution.

## Suggested Next Shipping Steps

If you plan to turn this into a polished downloadable product, the next practical steps are:

1. Finalize the live PayPal checkout link on the website.
2. Replace any remaining temporary branding assets with final launch branding.
3. Test lid-close behavior across more Apple Silicon MacBook models.
4. Add licensing / activation flow for your direct-download distribution model.
5. Notarize and harden the app for wider release.
6. Decide whether to keep the SwiftPM packaging flow or migrate to a full Xcode app project later.

## Verification

At the time of writing, the project has been verified with:

- `swift test`
- `swift build`
- `./scripts/build-app.sh`
- `codesign --verify --deep --strict dist/OuchBook.app`

## License

No license file has been added yet.
