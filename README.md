# ClamGUI

A graphical user interface for ClamAV antivirus on macOS.

## Features

- **Single File Scan**: Scan individual files for viruses and malware
- **Watchdog Mode**: Continuously monitor a directory for new files and scan them automatically
- **Menu Bar Integration**: Quick access from the macOS menu bar
- **Notifications**: Get alerted when threats are detected
- **Settings**: Configure watch directories, notifications, and scan preferences
- **Auto-Updates**: Built-in updater for ClamGUI itself

## Requirements

- macOS 13.0 or later
- ClamAV installed and running (clamd daemon)

## Installation

### 1. Install ClamAV

ClamGUI requires ClamAV to be installed on your system. Install it via Homebrew:

```bash
brew install clamav
```

Configure ClamAV and start the daemon:

```bash
# Edit configuration if needed
sudo nano /opt/homebrew/etc/clamav/clamd.conf

# Start the ClamAV daemon
brew services start clamav
```

### 2. Install ClamGUI

Download the latest release from the [Releases](https://github.com/clamgui/clamgui/releases) page.

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
   git clone https://github.com/clamgui/clamgui.git
   cd clamgui
   ```

2. Open the project in Xcode:
   ```bash
   open ClamGUI.xcodeproj
   ```

3. Build and run (⌘R)

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
│   ├── ClamAVManager.swift    # ClamAV daemon communication
│   ├── SettingsManager.swift  # User preferences
│   ├── MenuBarManager.swift   # Menu bar icon and menu
│   ├── NotificationManager.swift # User notifications
│   └── UpdaterManager.swift   # App update checks
└── Utilities/
    └── DirectoryWatcher.swift # File system monitoring
```

## ClamAV Socket Communication

ClamGUI connects to the ClamAV daemon (clamd) via Unix domain socket. Common socket locations:

- `/var/run/clamav/clamd.sock`
- `/usr/local/var/run/clamav/clamd.sock`
- `/opt/homebrew/var/run/clamav/clamd.sock`

The app automatically detects the socket location.

## License

MIT License - see LICENSE file for details

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## Support

- [GitHub Issues](https://github.com/clamgui/clamgui/issues)
- [ClamAV Documentation](https://docs.clamav.net/)
