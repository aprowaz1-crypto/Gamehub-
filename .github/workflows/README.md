# Gamehub Launcher Build

This workflow builds the Gamehub launcher Swift packages.

## Jobs

- `build-launcher`: Builds `launcher/` and `core/MockCore/` Swift packages with `swift build`
- `build-ipa`: (Phase 1 skeleton - placeholder for xcodebuild once app target exists)

## Artifacts

- Launcher build logs
- IPA (when app target exists)

## Entitlements

- `get-task-allow`: true (required for JIT debugger attach)
- `com.apple.developer.kernel.increased-memory-limit`: true (embedded, verified in CI)

## Signing

- Ad-hoc signed (`codesign --force --sign -`)
- No embedded provisioning profile
- SideStore does final signing on device
