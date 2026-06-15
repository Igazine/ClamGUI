# Native libclamav Architecture Notes

ClamGUI uses an embedded `libclamav` runtime as its only scanner backend. The
app does not connect to `clamd`, start a daemon, or depend on a host ClamAV
installation at runtime.

## Licensing

`libclamav` is licensed under GNU GPL v2. The ClamAV documentation states that
software linking against `libclamav` must be GPL compliant. ClamGUI is therefore
licensed as GPL-2.0-only.

Sources:

- https://docs.clamav.net/manual/Development/libclamav.html
- https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt

## Runtime Loading

The current implementation uses `dlopen`/`dlsym` so the Xcode project remains
buildable without a compile-time ClamAV SDK dependency. At runtime, ClamGUI
searches the app bundle's private frameworks directory first. Development builds
may fall back to Homebrew library paths to support local iteration.

If a bundled `libclamav` is present but cannot be loaded, ClamGUI treats that as
a runtime error instead of falling back to Homebrew, because fallback would hide
broken release packaging.

## libclamav Lifecycle

The scanner is long-lived. Loading signatures and compiling the engine is
expensive and should happen once per database version.

Required lifecycle:

1. Call `cl_init(CL_INIT_DEFAULT)`.
2. Create an engine with `cl_engine_new()`.
3. Load signatures with `cl_load(databasePath, engine, &signatureCount, CL_DB_STDOPT)`.
4. Compile with `cl_engine_compile(engine)`.
5. Scan files with `cl_scanfile_ex()` and read the `cl_verdict_t` output.
6. Free the engine with `cl_engine_free()` on shutdown or reload.

The native wrapper owns the engine behind an actor so scans cannot race engine
reload or shutdown.

## Signature Databases

Embedding `libclamav` does not remove the need for signature databases. ClamGUI
uses app-owned database files only:

```text
~/Library/Application Support/ClamGUI/
├── Database/
│   ├── daily.cvd or daily.cld
│   ├── main.cvd or main.cld
│   └── bytecode.cvd or bytecode.cld
├── Quarantine/
└── scan_results.db
```

`LibClamAVScanner` must not fall back to `cl_retdbdir()` or any host ClamAV
database path. Missing app-managed databases should produce a clear
scanner-not-ready state.

Packaged builds carry an initial signature database under
`Contents/Resources/Database`. `SignatureDatabaseManager` bootstraps those files
into `~/Library/Application Support/ClamGUI/Database` only when the app-managed
database directory is empty. This gives clean installs a working scanner without
reintroducing host/global database fallback. It is intentionally separate from
the final database update UX.

ClamAV documents FreshClam as the official database updater. ClamGUI currently
has a `SignatureDatabaseManager` that writes an app-local `freshclam.conf` and
runs `freshclam` against the app database directory. Long-term, this can be
replaced with a native `libfreshclam` bridge.

Source:

- https://docs.clamav.net/manual/Usage/SignatureManagement.html

## macOS Packaging Implications

For distribution, ClamGUI should not link against `/opt/homebrew` paths. Build
automation needs to produce a universal macOS bundle with embedded dylibs or a
static library where license-compatible and technically practical. The app must
also make the complete corresponding source available for GPL compliance.

Current development packaging:

```bash
Scripts/package-clamav-runtime.sh /path/to/ClamGUI.app /opt/homebrew
```

The script copies `libclamav`, `freshclam`, non-system Homebrew dylib
dependencies, and local ClamAV signature database files into the app bundle,
then rewrites Homebrew install names to bundle-relative `@loader_path`
references and ad-hoc signs the modified Mach-O files. This validates the
app-bundled runtime shape for local development; release automation still needs
a reproducible universal build of ClamAV and its dependencies.
