# PROGRESS.md

## Done
- [x] Phase 0: Surveyed Madeira codebase (README, ARCHITECTURE_ANALYSIS.md, CONTRIBUTING.md, STEAM_CEF_HANDOFF.md, build/, scripts/, patches/, app/)
- [x] Phase 0: Written PLAN.md with components, build order, toolchains, risks, milestones
- [x] Phase 0: Received user answers and new requirements
- [x] Phase 0: Updated PLAN.md with memory/entitlement, device tiers, Steam memory-aware strategy, cover art, iOS 17.4+ decisions
- [x] Phase 0: Added iOS 27 JIT section (universal protocol, Madeira delta, Phase 2 gate, fallback options)
- [x] Phase 0: Fixed section numbering in PLAN.md
- [x] Phase 0: First commit/push succeeded (cfe1a23)
- [x] Phase 0: Triggered CI run 36047390268
- [x] Phase 0: Merged Madeira with full history (`git merge --allow-unrelated-histories`) → 26aca44
- [x] Phase 0: Resolved README.md conflict (Madeira README kept at root; PLAN.md/docs used for project-specific docs)
- [x] Phase 0: Updated PLAN.md with source citations, unverified claims, touchHLE correction, Phase 1 build-Madeira-AS-IS strategy
- [x] Phase 0: Removed placeholder app/Gamehub* files conflicting with Madeira's app/ layout
- [x] Phase 0: Initialized submodules (FEX, wine, research/dxmt) - SHAs verified in willfaust forks
- [x] Phase 1: Updated .gitmodules (branches: ios-port-2607, madeira-lgpl, ios-port)
- [x] Phase 1: Updated build-ipa.yml to build Madeira AS IS with native chains + xcodebuild
- [x] Phase 1: Changed bundle ID to com.gamehub.app and display name to Gamehub
- [x] Phase 1: Triggered CI run 36053746800

## Next
- [ ] Phase 1: Monitor CI run 36053746800 for green build
- [ ] Phase 1: If green, verify IPA structure and entitlements
- [ ] Phase 1: Install IPA on device via SideStore and test Madeira's JIT flow
- [ ] Phase 2: Add JIT self-test if Phase 1 IPA installs successfully

## Blockers
- CI run 36053746800 in progress (do not wait)
- Wine configure/build on macOS runner unverified

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
