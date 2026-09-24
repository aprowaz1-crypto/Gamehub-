# PROGRESS.md

## Done
- [x] Phase 0: Surveyed Madeira codebase (README, ARCHITECTURE_ANALYSIS.md, CONTRIBUTING.md, STEAM_CEF_HANDOFF.md, build/, scripts/, patches/, app/)
- [x] Phase 0: Written PLAN.md with components, build order, toolchains, risks, milestones
- [x] Phase 0: Received user answers and new requirements
- [x] Phase 0: Updated PLAN.md with memory/entitlement, device tiers, Steam memory-aware strategy, cover art, iOS 17.4+ decisions
- [x] Phase 0: Added iOS 27 JIT section (universal protocol, Madeira delta, Phase 2 gate, fallback options)
- [x] Phase 0: Fixed section numbering in PLAN.md

## Next
- [ ] Phase 0: User approves PLAN.md
- [ ] Phase 0: Create repo structure (.gitmodules, .github/workflows skeleton, launcher Swift package skeleton)
- [ ] Phase 0: First commit -> push -> CI run -> verify workflow syntax

## Blockers
- Waiting for user approval of updated PLAN.md before Phase 1
- JIT on iOS 27 is risk #1; must verify universal protocol on device before Phase 2

## Decisions
- Base on Madeira (GPL-3.0-or-later), fork submodules to Gamehub- org
- Launcher is a Swift package building for iOS + iOS Simulator against MockCore
- Free Apple ID only; increased-memory-limit via GetMoreRam / iRAM+ (free)
- Extended Virtual Addressing not required; add only if Madeira demonstrably needs it
- Steam Phase 5, memory-aware per tier (4/6/8 GB RAM)
- Covers: Steam public CDN by AppID + custom local images, never committed, optional SteamGridDB with user API key
- Device tiers: 4 GB / 6 GB / 8 GB+ with measured memory budgets; 6 GB primary tier (author's iPhone 14 Plus A15)
- Embed increased-memory-limit in entitlements; verify in CI (codesign -d --entitlements) and on device
- Log os_proc_available_memory() and phys_footprint at multiple points; show in Self-test and FPS overlay
- Min iOS: 17.4+ for now; check if lower target realistic after Phase 0
- JIT is risk #1 on iOS 27; Phase 2 self-test proves JIT before anything else
- Madeira must migrate to stikdebug:// URL scheme, add TXM detection, pre-allocate all regions before detach
- Fallback options if JIT fails on iOS 27: fewer features, other device/iOS, wait for StikDebug support, or do not ship
