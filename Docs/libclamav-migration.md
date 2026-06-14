# libclamav Migration Notes

ClamGUI currently talks to a locally running `clamd` daemon over a Unix domain
socket. That works, but it requires users to install and configure ClamAV first.
The target architecture is to embed `libclamav` and make the default scanner a
native in-process engine.

## Licensing

`libclamav` is licensed under GNU GPL v2. The ClamAV documentation states that
software linking against `libclamav` must be GPL compliant. ClamGUI is therefore
licensed as GPL-2.0-only before adding an embedded scanner backend.

Sources:

- https://docs.clamav.net/manual/Development/libclamav.html
- https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt

## Native Swift Integration

Swift can call C APIs directly once a Clang module is available. The cleanest
native shape for this app is:

1. Add a small C module, for example `CClamAV`, exposing `clamav.h` through a
   `module.modulemap`.
2. Add a Swift wrapper, for example `LibClamAVScanner`, that owns the opaque
   `cl_engine` pointer and exposes async Swift methods.
3. Hide C pointers, C strings, and scan-option bitfields behind Swift value
   types that match the existing `ClamAVManager.ScanResult` API.
4. Keep the existing daemon/socket implementation as a legacy backend behind
   the same scanner protocol, but do not expose it in the normal UI.

Swift.org documents this pattern for C/C++ libraries: Swift does not import
arbitrary headers directly; it imports a module described by a module map.

Source:

- https://www.swift.org/documentation/articles/wrapping-c-cpp-library-in-swift.html

The current implementation uses `dlopen`/`dlsym` as an intermediate step. This
keeps the Xcode target buildable on machines that do not have Homebrew ClamAV
headers installed, while still calling the native C API in-process. The runtime
loader searches the app bundle's private frameworks directory first, then common
Homebrew development paths. Production packaging should bundle `libclamav` and
its non-system dependencies in the app rather than relying on Homebrew paths.
If a bundled `libclamav` is present but cannot be loaded, ClamGUI treats that as
a runtime error instead of falling back to Homebrew, because fallback would hide
broken release packaging.

## libclamav Lifecycle

The in-process scanner should be long-lived. Loading signatures and compiling
the engine is expensive and should happen once per database version.

Required lifecycle:

1. Call `cl_init(CL_INIT_DEFAULT)`.
2. Create an engine with `cl_engine_new()`.
3. Load signatures with `cl_load(databasePath, engine, &signatureCount, CL_DB_STDOPT)`.
4. Compile with `cl_engine_compile(engine)`.
5. Scan files with `cl_scanfile_ex()` and read the `cl_verdict_t` output.
6. Free the engine with `cl_engine_free()` on shutdown or reload.

The ClamAV docs also note that `libclamav` is thread-safe. ClamGUI should still
serialize engine reloads and protect the engine pointer behind an actor or a
dedicated queue so scans cannot race a reload/free.

The current native wrapper uses `cl_scanfile_ex()`. This matters because the
newer API returns scan success or failure separately from the malware verdict;
callers must check `cl_verdict_t`, not only the return code.

## Signature Databases

Embedding `libclamav` does not remove the need for signature databases. The app
must manage official database files itself.

Expected app-owned layout:

```text
~/Library/Application Support/ClamGUI/
├── Database/
│   ├── daily.cvd or daily.cld
│   ├── main.cvd or main.cld
│   └── bytecode.cvd or bytecode.cld
├── Quarantine/
└── scan_results.db
```

ClamAV documents that FreshClam downloads and updates official virus signature
databases. We can either bundle and call a `freshclam` helper, use `libfreshclam`
if it is practical to package, or implement database download/update logic in
Swift. The first native milestone should assume an existing app-owned database
directory, then add update management after scanning is stable.

Current implementation:

- `SignatureDatabaseManager` owns `~/Library/Application Support/ClamGUI/Database`.
- It writes an app-local `freshclam.conf` and runs `freshclam` against that
  database directory.
- Development builds discover `freshclam` in the app bundle first, then common
  Homebrew paths. Production packaging still needs to bundle the helper.
- `LibClamAVScanner` loads signatures from the app-owned database directory.
  It must not fall back to `cl_retdbdir()` or any host ClamAV database path.
- Settings surfaces the database status and update action, while daemon controls
  remain hidden when the native scanner is active.

Source:

- https://docs.clamav.net/manual/Usage/SignatureManagement.html

## macOS Packaging Implications

Homebrew's `libclamav` on this machine links against:

- `libclammspack`
- OpenSSL
- `pcre2`
- `json-c`
- system `zlib`, `bzip2`, `libxml2`, `libiconv`, CoreFoundation

For distribution, ClamGUI should not link against `/opt/homebrew` paths. Build
automation needs to produce a universal macOS bundle with embedded dylibs or a
static library where license-compatible and technically practical. The app must
also make the complete corresponding source available for GPL compliance.

Current development packaging:

```bash
Scripts/package-clamav-runtime.sh /path/to/ClamGUI.app /opt/homebrew
```

The script copies `libclamav`, `freshclam`, and non-system Homebrew dylib
dependencies into the app bundle, then rewrites Homebrew install names to
bundle-relative `@loader_path` references and ad-hoc signs the modified Mach-O
files. This is enough to validate the app-bundled runtime shape on one
architecture, but release automation still needs a reproducible universal build
of ClamAV and its dependencies.

## Proposed Code Architecture

Introduce a scanner boundary before importing `libclamav`:

```swift
protocol MalwareScanner: Sendable {
    func prepare() async throws
    func scanFile(at path: String) async -> ClamAVManager.ScanResult
    func reloadSignatures() async throws
    func shutdown() async
}
```

Then implement:

- `LibClamAVScanner`: default in-process scanner.
- `ClamdScanner`: legacy socket backend using the existing daemon logic.
- `ScanEngineManager`: owns selected backend and presents the existing UI-facing
  scanning API.

This keeps Watchdog, manual scanning, quarantine, notifications, and scan
history mostly unchanged while replacing the transport underneath.

## First Implementation Milestones

1. Add the C module map and a minimal Swift wrapper against the locally installed
   Homebrew `libclamav` for development only.
2. Add a `MalwareScanner` protocol and route manual scan through it.
3. Load only the app-owned signature database directory instead of
   `cl_retdbdir()` or any global host database.
4. Convert Watchdog queue execution to use `MalwareScanner`.
5. Add signature update management.
6. Add build scripts for vendored universal `libclamav`, `freshclam`, and
   dependency dylibs.
