# ClamGUI Feature Specification

## Status Legend

- ✅ Implemented
- 🚧 In Progress
- ⏳ Planned
- 💡 Requested
- ❌ Not Planned

## Core Features

### ClamAV Integration

| Feature | Status | Notes |
|---------|--------|-------|
| Native `libclamav` scanner | ✅ | Embedded in-process scanner backend |
| App-owned signature database | ✅ | Uses `~/Library/Application Support/ClamGUI/Database` only |
| Bundled initial signature database | ✅ | Seeds clean installs from `Contents/Resources/Database` |
| Host/global database fallback | ❌ | Avoided so packaged builds stay self-contained |
| Virus definition updates | ⏳ | Current helper exists; final update UX/API should be implemented last |
| `libfreshclam` updater bridge | 💡 | Candidate replacement for spawning `freshclam` |

### Scanning Features

| Feature | Status | Notes |
|---------|--------|-------|
| Single file scan | ✅ | Drag-drop or file picker; always performs a fresh scan |
| Directory scan | 💡 | Requested |
| Watchdog folder monitoring | ✅ | FSEvents-based monitoring |
| Quarantine infected files | ✅ | Settings toggle + manual threat actions |
| Scan activity feedback | ✅ | Live libclamav layer/object progress text |
| Scan history database | ✅ | SQLite records file status and metadata |
| System path restrictions | ✅ | `ScanPathValidator` prevents restricted locations |

### User Interface

| Feature | Status | Notes |
|---------|--------|-------|
| Main tabbed window | ✅ | Scan, Watchdog, Settings, About |
| Menu bar integration | ✅ | Quick actions menu |
| Settings tab | ✅ | Watchdog, notifications, quarantine, database status |
| Custom app icon | ✅ | macOS asset catalog app icon |
| Outdated definitions feedback | ✅ | Visible status; database update remains intentionally last |

### Application Management

| Feature | Status | Notes |
|---------|--------|-------|
| Built-in app updater | ✅ | GitHub releases check |
| Background operation | ✅ | Menu bar only mode |
| Start at login | ✅ | Via AppleScript |
| Code signing | ⏳ | Needed for distribution |
| Notarization | ⏳ | Needed for distribution |

## File Locations

### Application Data

```text
~/Library/Application Support/ClamGUI/
├── Database/
├── Quarantine/
├── freshclam.conf
├── freshclam.log
└── scan_results.db
```

## Notes

- ClamGUI no longer contains a `clamd` daemon backend.
- Release packaging must embed ClamAV runtime dependencies and must not depend
  on Homebrew paths.
