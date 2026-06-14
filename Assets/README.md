# Assets Directory

This directory contains source assets for ClamGUI that are used during development and build processes.

## Purpose

This is **NOT** an Xcode asset catalog. It serves as a source directory for:
- Images and logos (for documentation, website, app icon source files)
- ClamAV configuration templates
- Default configuration files
- Documentation assets
- Build script resources
- GUI asset source files (SVG, PNG source files, etc.)

## Directory Structure

```
Assets/
├── images/          # Raster images (PNG, JPG, etc.)
├── logos/           # Logo files (SVG, AI, PSD source files)
├── configs/         # ClamAV configuration templates
├── templates/       # Other templates (launchd plists, etc.)
└── docs/            # Documentation assets (diagrams, screenshots)
```

## Usage

Assets from this directory may be:
1. Copied into the Xcode project during build
2. Embedded in the app bundle by build scripts
3. Used for generating default configurations
4. Referenced in documentation

## Note to Developers

- Keep source files here (e.g., `.svg`, `.psd`, `.ai`)
- Exported/compiled assets go into `ClamGUI/Assets.xcassets`
- Configuration templates should have `.template` extension
- Large binary files should be documented in this README
