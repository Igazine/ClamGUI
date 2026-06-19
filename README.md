# ClamGUI

A graphical user interface for ClamAV antivirus on macOS.

## Features

- **Single File Scan**: Scan individual files for viruses and malware
- **Watchdog Mode**: Continuously monitor a directory for new files and scan them automatically
- **Menu Bar Integration**: Quick access from the macOS menu bar
- **Notifications**: Get alerted when threats are detected
- **Settings**: Configure watch directories, notifications, and scan preferences
- **Auto-Updates**: Built-in updater for ClamGUI itself

## Runtime Model

ClamGUI is a native macOS front-end around an embedded `libclamav` runtime. It
does not talk to a `clamd` daemon and does not require users to install or run
ClamAV separately.

The native scanner uses ClamGUI-managed signature databases from
`~/Library/Application Support/ClamGUI/Database`. It intentionally does not
fall back to a host ClamAV installation's database path, so packaged builds stay
self-contained and predictable.

Packaged builds include an initial signature database in
`Contents/Resources/Database`. On first launch, if the app-managed database
directory is empty, ClamGUI copies those bundled signatures into Application
Support so the scanner can run without a separate ClamAV install. Existing
app-managed databases are never overwritten by this bootstrap step.

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later
- Homebrew ClamAV for source builds. The build scripts copy its native runtime
  and signature files into the generated app; end users do not need Homebrew

## Installation

Download the latest release from the [Releases](https://github.com/Igazine/ClamGUI/releases) page.

## Usage

### Scanning a File

1. Open ClamGUI
2. Go to the "Scan File" tab
3. Drag and drop a file or click "Choose File"
4. Click "Scan File"

### Using Watchdog

1. Go to the "Watchdog" tab
2. Click "Browse" to select a directory to monitor
3. Toggle "Active" to start watching
4. New files added to the directory will be automatically scanned

## Configuration

Open the "Settings" tab to:

- Configure the watch directory
- Enable/disable notifications
- Enable auto-start at login
- Update virus definitions

## Building from Source

### Quick Start

1. Clone the repository:

   ```bash
   git clone https://github.com/Igazine/ClamGUI.git
   cd ClamGUI
   ```

2. Install the development copy of ClamAV:

   ```bash
   brew install clamav
   ```

3. Check the local toolchain and signature database:

   ```bash
   Scripts/check-development-environment.sh
   ```

   If signatures are missing, the command prints the exact `freshclam` command
   needed for the current Homebrew installation.

4. Build a runnable Debug app:

   ```bash
   Scripts/build-debug-with-clamav-runtime.sh
   ```

   The app is written to:

   ```text
   /private/tmp/clamgui-derived/Build/Products/Debug/ClamGUI.app
   ```

The scripts discover both Apple Silicon and Intel Homebrew installations. Pass
an explicit ClamAV prefix only when using a nonstandard installation:

```bash
Scripts/build-debug-with-clamav-runtime.sh /path/to/clamav/prefix
```

### Working in Xcode

Open the project normally for editing:

```bash
open ClamGUI.xcodeproj
```

Xcode can compile the Swift application without linking against ClamAV because
the native API is loaded dynamically. A plain Cmd-R build does not embed the
runtime or initial signature database. Use
`Scripts/build-debug-with-clamav-runtime.sh` whenever a self-contained,
functional scanner build is required.

For a command-line compile-only check:

```bash
xcodebuild \
  -project ClamGUI.xcodeproj \
  -scheme ClamGUI \
  -configuration Debug \
  -derivedDataPath /private/tmp/clamgui-compile-check \
  CODE_SIGNING_ALLOWED=NO \
  "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG CLAMGUI_SCRIPTED_BUILD" \
  build
```

### Runtime Packaging

To add the runtime to an existing app bundle:

```bash
Scripts/package-clamav-runtime.sh /path/to/ClamGUI.app
```

The script copies `libclamav`, `freshclam`, non-system Homebrew dylib
dependencies, and local ClamAV signature database files into the bundle. It
rewrites install names to use the app's `Contents/Frameworks` directory and
ad-hoc signs the modified runtime files for local development builds.

To verify an already packaged app bundle:

```bash
Scripts/verify-clamav-runtime.sh /path/to/ClamGUI.app
```

To produce a local Release app bundle and PKG installer with the bundled
ClamAV runtime:

```bash
Scripts/package-release-app.sh
```

This writes the following artifacts:

```text
build/Artifacts/Release/ClamGUI.app
build/Artifacts/ClamGUI.pkg
build/Artifacts/ClamGUI.pkg.sha256
```

The app and PKG are intentionally unsigned and are not notarized. Runtime dylibs
are ad-hoc signed only so macOS can load the rewritten local binaries.

The app version comes from `MARKETING_VERSION` and the build number comes from
`CURRENT_PROJECT_VERSION` in the Xcode project. The PKG automatically uses the
same app version.

To run an end-to-end native scanner smoke test against a clean file and the
EICAR antivirus test string:

```bash
Scripts/smoke-test-native-scanner.sh
```

You can also point the same smoke test at an already packaged app:

```bash
Scripts/smoke-test-native-scanner.sh build/Artifacts/Release/ClamGUI.app
```

### Publishing an Update

The built-in updater reads the latest release from
`Igazine/ClamGUI`. Tag releases with a semantic version such as `v1.0.1` and
attach both files using these exact names:

```text
ClamGUI.pkg
ClamGUI.pkg.sha256
```

ClamGUI downloads the PKG, verifies its SHA-256 checksum, and opens the verified
package in macOS Installer.

## Project Structure

```
ClamGUI/
├── ClamGUIApp.swift          # Main app entry point
├── ContentView.swift          # Main tabbed interface
├── Views/
│   ├── ScanView.swift         # Single file scan UI
│   ├── WatchdogView.swift     # Directory monitoring UI
│   ├── SettingsView.swift     # Settings configuration UI
│   └── AboutView.swift        # About screen
├── Managers/
│   ├── ClamAVManager.swift    # UI-facing scanner facade
│   ├── LibClamAVScanner.swift # Native libclamav scanner backend
│   ├── ScanEngineManager.swift # Native scanner owner
│   ├── SignatureDatabaseManager.swift # App-owned signature database updates
│   ├── SettingsManager.swift  # User preferences
│   ├── MenuBarManager.swift   # Menu bar icon and menu
│   ├── NotificationManager.swift # User notifications
│   └── UpdaterManager.swift   # App update checks
├── Scripts/
│   ├── check-development-environment.sh
│   ├── build-debug-with-clamav-runtime.sh
│   └── package-release-app.sh
└── Utilities/
    └── DirectoryWatcher.swift # File system monitoring
```

## License

GPL-2.0-only - see LICENSE file for details

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## Support

- [GitHub Issues](https://github.com/Igazine/ClamGUI/issues)
- [ClamAV Documentation](https://docs.clamav.net/)
