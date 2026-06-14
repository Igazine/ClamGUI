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

ClamGUI is being migrated from a `clamd` socket frontend to a native macOS app
that embeds `libclamav`. The default scanner is the native in-process backend.
The older `clamd` socket backend remains in the codebase as a legacy fallback
for development and diagnostics.

## Requirements

- macOS 13.0 or later
- For current development builds: Homebrew ClamAV, used to provide `libclamav`,
  `freshclam`, and local signature updates until the release bundle embeds them

## Installation

### 1. Development Dependency

Install ClamAV via Homebrew for local development:

```bash
brew install clamav
```

You do not need to start the `clamd` daemon for the native scanner path.

### 2. Install ClamGUI

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
- Set maximum scan file size
- Enable auto-start at login
- Update virus definitions

## Building from Source

### Requirements

- Xcode 15.0 or later
- macOS 13.0 SDK

### Build Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/Igazine/ClamGUI.git
   cd ClamGUI
   ```

2. Open the project in Xcode:
   ```bash
   open ClamGUI.xcodeproj
   ```

3. Build and run (⌘R)

### Package the ClamAV Runtime

For local development, build and package the ClamAV runtime in one step:

```bash
Scripts/build-debug-with-clamav-runtime.sh
```

After a manual Xcode build, you can also copy the Homebrew ClamAV runtime into
an app bundle directly:

```bash
Scripts/package-clamav-runtime.sh /path/to/ClamGUI.app /opt/homebrew
```

The script copies `libclamav`, `freshclam`, and non-system Homebrew dylib
dependencies into the bundle and rewrites install names to use the app's
`Contents/Frameworks` directory. It also ad-hoc signs the modified runtime
files for local development builds.

To verify an already packaged app bundle:

```bash
Scripts/verify-clamav-runtime.sh /path/to/ClamGUI.app
```

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
│   ├── ClamdScanner.swift     # Legacy clamd socket backend
│   ├── ScanEngineManager.swift # Scanner backend selection
│   ├── SignatureDatabaseManager.swift # App-owned signature database updates
│   ├── SettingsManager.swift  # User preferences
│   ├── MenuBarManager.swift   # Menu bar icon and menu
│   ├── NotificationManager.swift # User notifications
│   └── UpdaterManager.swift   # App update checks
└── Utilities/
    └── DirectoryWatcher.swift # File system monitoring
```

## ClamAV Socket Communication

The legacy backend connects to the ClamAV daemon (`clamd`) via Unix domain
socket. Common socket locations:

- `/var/run/clamav/clamd.sock`
- `/usr/local/var/run/clamav/clamd.sock`
- `/opt/homebrew/var/run/clamav/clamd.sock`

The app still contains this path, but the normal scanner route is native
`libclamav`.

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
