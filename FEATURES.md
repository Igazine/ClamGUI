# ClamGUI Feature Specification

This document outlines the features and requirements for ClamGUI.

---

## Status Legend

- ✅ **Implemented** - Feature is complete and working
- 🚧 **In Progress** - Feature is being developed
- ⏳ **Planned** - Feature is scheduled for future development
- 💡 **Requested** - Feature has been requested but not scheduled
- ❌ **Not Planned** - Feature will not be implemented

---

## Core Features

### 1. ClamAV Integration

| Feature | Status | Notes |
|---------|--------|-------|
| Connect to clamd via Unix socket | ✅ | Custom socket at `~/Library/Application Support/ClamGUI/clamd.sock` |
| Custom clamd configuration | ✅ | Config at `~/Library/Application Support/ClamGUI/clamd.conf` |
| Start/Stop clamd daemon | ✅ | Via launchd (user or root mode) |
| Sudo/Admin mode for daemon | ✅ | Optional elevated privileges |
| Virus definition updates | ⏳ | freshclam integration planned |
| Multiple clamd instances support | ❌ | Only ClamGUI's daemon is used |
| Analyze clamd's socket commands | ✅ | Documented in Assets/docs/CLAMD_COMMANDS.md with correct INSTREAM protocol |
| Implement streaming scan | 💡 | For files >2GB using INSTREAM socket command. Check "man clamd" for details |

### 2. Scanning Features

| Feature | Status | Notes |
|---------|--------|-------|
| Single file scan | ✅ | Drag-drop or file picker |
| Directory scan | 💡 | Requested |
| Watchdog (folder monitoring) | ✅ | FSEvents-based monitoring |
| Quarantine infected files | ✅ | Settings toggle + auto-quarantine + manual actions |
| Scan progress indicator | ✅ | Percentage during file upload |
| Scan history/log | 🚧 | Database implemented, Watchdog UI pending |
| Store scanned file paths in local db | ✅ | SQLite with hashed paths, creation/mod dates |
| Disallow scanning of system directories | ✅ | ScanPathValidator prevents /System, /Library, etc. |
| Threat actions | ✅ | Quarantine, Open in Finder, Open in Terminal |

### 3. User Interface

| Feature | Status | Notes |
|---------|--------|-------|
| Main window (tabbed) | ✅ | 4 tabs implemented |
| Menu bar icon | ✅ | With quick actions menu |
| Scan File tab | ✅ | File selection and scanning |
| Watchdog tab | ✅ | Directory monitoring UI |
| Settings tab | ✅ | Configuration options |
| About tab | ✅ | App info and links |
| Dark mode support | ⏳ | macOS system integration |
| Custom app icon | 💡 | Placeholder needed |

### 4. Notifications & Alerts

| Feature | Status | Notes |
|---------|--------|-------|
| Threat detection notification | ✅ | macOS UserNotifications |
| Scan complete notification | ✅ | Success/failure alerts |
| Sudo warning dialog | ✅ | Before elevated daemon start |
| ClamAV not installed overlay | ✅ | Blocks UI until resolved |
| Daemon not running overlay | ✅ | With start options |
| Outdated definitions alert | 💡 | Planned |

### 5. Settings & Configuration

| Feature | Status | Notes |
|---------|--------|-------|
| Watch directory setting | ✅ | For Watchdog tab |
| Auto-scan on file added | ✅ | Toggle in Settings |
| Notifications toggle | ✅ | Enable/disable alerts |
| Start at login | ✅ | Via AppleScript |
| Menu bar icon toggle | ✅ | Show/hide option |
| Sudo mode preference | ✅ | Remember user choice |
| Scan archives recursively | ✅ | Toggle option |

### 6. Application Management

| Feature | Status | Notes |
|---------|--------|-------|
| Built-in app updater | ✅ | GitHub releases check |
| launchd integration | ✅ | User and system daemons |
| Background operation | ✅ | Menu bar only mode |
| Window close ≠ quit | ✅ | App stays running |

---

## Technical Requirements

### System Requirements

- [x] macOS 13.0 or later
- [x] Apple Silicon (ARM64) support
- [x] Intel (x86_64) support
- [x] Sandboxed app (with exceptions)

### Dependencies

- [x] ClamAV (clamd daemon)
- [x] Homebrew installation support
- [ ] freshclam (virus definition updates)

### Security

- [x] Sudo authentication for elevated daemon
- [x] Warning dialogs for privileged operations
- [x] Socket permissions (600 mode)
- [ ] Code signing
- [ ] Notarization for distribution

---

## Known Issues

| Issue | Severity | Workaround |
|-------|----------|------------|
| None currently | - | - |

---

## Future Enhancements

### High Priority
- [ ] Custom app icon design
- [ ] freshclam integration (in-app updates)
- [ ] Scan scheduling
- [ ] Quarantine management

### Medium Priority
- [ ] Multiple directory watchdog
- [ ] Scan statistics/charts
- [ ] Custom scan profiles
- [ ] Export scan reports

### Low Priority
- [ ] Touch Bar support
- [ ] Shortcuts app integration
- [ ] Widget for macOS Sonoma+

---

## GitHub Integration

- [ ] Repository URL: TBD
- [ ] CI/CD pipeline: ✅ (GitHub Actions)
- [ ] Release automation: ✅
- [ ] Notarization workflow: ✅ (configured)

---

## File Locations

### Application
````
/Applications/ClamGUI.app
```

### User Data
```
~/Library/Application Support/ClamGUI/
├── clamd.conf          # Custom daemon config
├── clamd.sock          # Unix domain socket
├── clamd.log           # Daemon log file
└── clamd-launchd.log   # launchd output log
```

### System Files (sudo mode)
```
/Library/LaunchDaemons/com.clamgui.clamd.root.plist
/var/log/clamgui/
```

### Configuration Templates
```
<Volumes/Work/gemini/qwen/Assets/configs/>
├── clamd.conf
├── clamd.conf.template
└── freshclam.conf.template
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2024-04 | Initial development |

---

## Notes

- Add new feature requests as rows in the appropriate table
- Update status using the legend above
- Technical details and implementation notes go in the "Notes" column
- For complex features, create separate detailed specification documents and link them here
