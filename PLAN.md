# PLAN.md — Gamehub- iOS Launcher + Madeira Fork

## 1. Goal

Build an open-source iOS app that runs x86-64 Windows PC games on a non-jailbroken iPhone, with a console-style GameHub-inspired launcher (SwiftUI, big cover-art, one-tap play, controller-first navigation). No GameHub name, logo, assets or code.

**Base:** Fork of [Madeira](https://github.com/willfaust/Madeira) (GPL-3.0-or-later) — Wine (ARM64EC) + FEX-Emu (x86-64 → ARM64 JIT) + DXMT (D3D11 → Metal), single Mach process, wineserver as a thread. JIT via StikDebug. Sideloaded via SideStore.

**Constraint:** No Mac. Every iOS build runs in GitHub Actions on an Apple-silicon macOS runner. All communication with the user is in Ukrainian. Code, commits, docs in English.

---

## 2. Repository Layout

```
.github/workflows/   CI: build-ipa.yml, launcher-screenshot.yml
app/                 iOS app shell (SwiftUI + Metal compositor + WineProcessBridge)
  Gamehub/           Swift package / Xcode project target
  GamehubCore/       Mock core for Simulator builds (no device needed)
  GamehubUI/         SwiftUI launcher screens, shared with Simulator
  GamehubOverlay/    In-game HUD/overlay module
launcher/            Swift package: UI layer, builds for iOS + iOS Simulator
core/                Swift package: thin bridge to native libs (Wine, FEX, DXMT)
  MockCore/          Simulator-only mock for CI screenshot rendering
build/               Native build scripts (from Madeira)
  ntdll-unix/        Wine unix-side libs (*_ios.c forks)
  wineserver/        wineserver-as-thread
  win32u-unix/       win32u
  dxmt-ios/          DXMT fork with iOS patches
  fex-ios/           FEX-Emu iOS fork
  wine-pe/           Wine PE-side DLLs (ARM64EC)
  wineios-drv/       Wine display driver for iOS (UIKit + CAMetalLayer)
scripts/             Device deploy, prefix snapshot tools
patches/             iOS-specific patches for Wine/FEX/DXMT (if any not in submodules)
research/            dxmt reference, notes
docs/                 Developer docs, architecture notes
PROGRESS.md          Current status: done / next / blockers / decisions
COMPAT.md            Per-game compatibility notes
compat-db/           JSON per-game presets (resolution, FPS cap, env vars, etc.)
assets/              Placeholder covers, icons (no copyrighted art)
tests/               Unit/UI tests for launcher
LICENSE              GPL-3.0-or-later (from Madeira)
LICENSE-EXCEPTION.md Madeira Converter Exception (from Madeira)
THIRD-PARTY-NOTICES.md
CONTRIBUTING.md
STEAM_CEF_HANDOFF.md
ARCHITECTURE_ANALYSIS.md
```

**Submodules (forked, with iOS patches — do not change without asking):**
- `wine/` — willfaust/wine fork (relicensed GPL-3.0-or-later under LGPL-2.1 §3)
- `FEX/` — willfaust/FEX fork (MIT preserved, modifications GPL-3.0-or-later)
- `research/dxmt/` — willfaust/dxmt fork (MIT preserved, modifications GPL-3.0-or-later)

---

## 3. Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SwiftUI Launcher (Phase 3)                │
│  Home · Library · Game Page · Settings · Overlay             │
├─────────────────────────────────────────────────────────────┤
│                     Core Bridge (Phase 0-2)                  │
│  JIT manager (StikDebug) · Process lifecycle · Logging       │
├──────────┬──────────────────┬──────────┬────────────────────┤
│  DXMT    │ VKD3D→MoltenVK  │ MoltenVK │  ANGLE             │
│(DX11→MTL)│ (DX12→VK→MTL)   │(VK→MTL)  │(GL→MTL)            │
├──────────┴──────────────────┴──────────┴────────────────────┤
│              FEX-Emu (x86→ARM64 JIT, iOS port)              │
│  Darwin syscall handler · W^X dual-mapped JIT memory        │
├─────────────────────────────────────────────────────────────┤
│              Wine (ARM64PE, wineserver-as-thread)            │
│  ntdll · kernel32 · user32 · gdi32 · wineios.drv            │
├─────────────────────────────────────────────────────────────┤
│              iOS / Metal / Darwin Kernel                     │
│         (A15–A19, iOS 17.4+, free Apple ID sideload)        │
└─────────────────────────────────────────────────────────────┘
```

**Key invariant:** Wine DLLs run natively (ARM64EC). Only the game's x86-64 code runs through FEX-Emu JIT. This is the xtajit bridge.

---

## 4. JIT on iOS 27 — Risk #1, Must Verify First

**Status on this device:** iPhone 14 Plus, iOS 27. JIT is the single highest-risk item. If JIT cannot be made to work on iOS 27 for this app, stop here and present options before building the launcher.

### 4.1 What changed in iOS 26/27

Since iOS 26, the old blanket `get-task-allow` + attach/detach JIT no longer works. TXM (Trusted Execution Monitor) and SPTM (System Protection Trusted Monitor) require each executable memory region to be pre-approved through the debug connection before the app executes code from it. A debugger that detaches early leaves later regions permanently unexecutable.

SideStore docs state: *"iOS 26 has broken JIT once again, and 26.6 and 27 only work with a few apps."* As of June 2026, the supported apps are UTM, Amethyst, MeloNX, maciOS, DolphiniOS, Geode, Manic EMU, Flycast, MeloCafe, ARMSX2, and DukeX. **Madeira is not on that list.** This is a known-good-signal gap, not a verdict: Madeira's forks may simply need the StikDebug integration update described below.

### 4.2 StikDebug iOS 26/27 universal protocol (reference implementation)

StikDebug provides the debugger-side bridge. The app-side protocol is documented in `StikJIT/INTEGRATION.md` and implemented by reference apps:

**Universal protocol (recommended for new integrations):**
```c
// BRK #0xf00d with x16 = command
// x16 = 0: CMD_DETACH
// x16 = 1: CMD_PREPARE_REGION (x0 = address, x1 = length)
// x16 = 3: CMD_MAP_PAGE_ZERO (x0 = TEB address, x1 = size)

__attribute__((noinline, optnone, naked))
void *JIT26PrepareRegion(void* address, size_t length) {
    __asm__("mov x16, #1\nbrk #0xf00d\nret\n");
}

__attribute__((noinline, optnone, naked))
void JIT26Detach(void) {
    __asm__("mov x16, #0\nbrk #0xf00d\nret\n");
}
```

**Required order where TXM/SPTM is present:**
1. Start JIT acquisition (StikDebug attaches and waits for breakpoint calls).
2. Wait for `CS_DEBUGGED` to appear before executing any breakpoint call.
3. Allocate or request every initial RX region and call `JIT26PrepareRegion` for each one.
4. Create writable aliases and finish initializing the JIT allocator.
5. Call `JIT26Detach`.
6. Mark JIT ready only after prepare and detach calls have returned successfully.

**Critical rule:** A region introduced later cannot be prepared by a script that has already detached. All executable regions must be pre-allocated and prepared before detaching.

**Legacy protocol (do NOT build new integrations around it):**
`BRK #0x69` with RX address in x0 and length in x1. Legacy script prepares that region, advances PC, and detaches.

### 4.3 Madeira's current implementation vs what must change

Madeira's `madeira-jit.js` already handles `BRK #0xf00d` with x16 dispatch and `BRK #0x69` legacy. `JITAllocator.c` implements dual-mapped JIT memory and `jit26_prepare_region` / `jit26_detach`. `StikJITHelper.swift` opens the JIT enabler and polls for `CS_DEBUGGED`.

However, Madeira is not on the iOS 26/27 supported-apps list. The following changes are required to bring it to parity with reference apps:

| What Madeira has | What must change for iOS 27 |
|---|---|
| `stikjit://enable-jit` URL scheme | Migrate to `stikdebug://enable-jit` with `bundle-id`, `pid`, and `script-name`/`script-data` query parameters |
| No TXM detection | Add `isTXMPresent` check (app-controlled, developer-defined, not a user setting) |
| No pre-allocation guarantee | Pre-allocate ALL executable regions before detaching; reserve executable window and JIT pool at image load (`madeira_early_window_base`, `madeira_early_pool_base`) |
| Detach deferred indefinitely | Call `JIT26Detach` after Wine boot is complete and no more regions will be needed |
| No LiveContainer detection | Detect `LC_HOME_PATH` env; hide Built-in StikJIT there, require manual StikDebug with Use LiveContainer Bundle ID |
| Embedded base64 script | Keep embedded, but load from bundle resource in development |
| Single JIT method | Offer picker: Wait for Debugger / StikDebug / Built-in StikJIT (once helper is implemented) |

**URL scheme migration:**
```swift
// OLD (Madeira today):
"stikjit://enable-jit?bundle-id=\(id)&script-data=\(base64)"

// NEW (StikDebug iOS 26/27):
"stikdebug://enable-jit?bundle-id=\(id)&pid=\(getpid())"
// + &script-name=universal.js when TXM is present
// + &script-data=<base64> for custom scripts
```

**TXM detection rule:** Resolve TXM/SPTM presence before building the request. Do not treat unknown as absent. `StikDebug.isTXMPresent` is informational; the app's single script remains developer-defined.

### 4.4 Reference apps and their JIT approaches

| App | JIT approach on iOS 26/27 | Notes |
|---|---|---|
| UTM | Wait for Debugger (tethered launch through Xcode or StikDebug) | No custom script; debugger stays attached |
| MeloNX | StikDebug with `universal.js`, "Waiting for JIT" view, JIT indicator | Maps JIT pool on-launch; reports Increased Memory Limit status |
| touchHLE iOS port | Not applicable (runs old iPhone OS apps, not iOS 26 JIT) | Mentioned in passing only; no universal script to port |
| Madeira (today) | Embedded script via `stikjit://` URL, polls for CS_DEBUGGED | Needs URL scheme + TXM + pre-allocation updates |

### 4.5 Entitlements and memory — measured numbers

| Entitlement | Provisioning | How to enable | Notes |
|---|---|---|---|
| `get-task-allow` | Free dev profile | Reinstall app with free signing | Required for JIT debugger attach |
| `com.apple.developer.kernel.increased-memory-limit` | Free, via GetMoreRam / iRAM+ | GetMoreRam → Settings → Sign in → App IDs → Refresh → Select app → Add Increased Memory Limit → Reinstall via SideStore | **SideStore does NOT enable this automatically for free accounts** (SideStore issue #1616: ~3.3 GB vs ~6 GB with AltStore/Xcode on iPhone 15 Pro Max). **This step is mandatory.** |
| `com.apple.developer.kernel.extended-virtual-addressing` | Paid Developer Program only | Not required by default | Add only if Madeira demonstrably needs it. Flag clearly if added. |
| `Increased Debugging Memory Limit` | Paid path (MeloNX docs) | Not yet measured | Check whether it matters while StikDebug is attached. Report measured `os_proc_available_memory()` and `phys_footprint` with and without it. Do not add to entitlements yet. |

**Mandatory memory checklist at every relevant point:**
- Log `os_proc_available_memory()` at app launch.
- Log `phys_footprint` after Wine boot, in the launcher, and in-game (StikDebug attached / JIT on).
- Show values in Self-test and the FPS overlay.
- If available memory ceiling looks low, show a banner with exact steps: GetMoreRam / iRAM+ → Sign in → App IDs → Refresh → Add Increased Memory Limit → reinstall via SideStore. Re-check after every SideStore refresh/reinstall.

### 4.6 Phase 2 Self-test — JIT must be proven before anything else

Phase 2 is the JIT gate. No game will run without it. Self-test screen:

1. **Entitlement check:** `get-task-allow` = true, `increased-memory-limit` status, `phys_footprint`.
2. **StikDebug availability:** Can we open `stikdebug://enable-jit`? Is StikDebug installed?
3. **JIT allocation test:** Create a dual-mapped JIT region (`jit_region_create`), write ARM64 code (`mov x0, #42; ret`) to the RW view, call `jit26_prepare_region` on the RX view, execute from RX, verify result == 42.
4. **Failure mode logging:**
   - `CS_DEBUGGED` not set after StikDebug enablement → "JIT not enabled. Check StikDebug pairing, VPN, and retry."
   - `jit_region_create` failed → "Dual-mapped JIT region failed. Check memory limit and reinstall with GetMoreRam."
   - `jit26_prepare_region` returned NULL → "Debugger could not allocate RX memory. Re-roll launch or lower pool size."
   - Execution result != 42 → "JIT execution test failed. TXM may have rejected the region. Check StikDebug logs for attach errors."
   - JIT drops after initial success → "JIT lost after detach. Keep debugger attached or re-preallocate regions."
5. **Memory log:** `os_proc_available_memory()` and `phys_footprint` at every step.

**Only after JIT test passes** does the app proceed to Wine boot and game launch.

### 4.7 Fallback options if JIT cannot be made to work on iOS 27

If, after implementing the universal protocol, URL scheme migration, TXM detection, and pre-allocation guarantees, JIT still cannot be made reliable on iOS 27 for this app, stop and present these options before building the launcher:

1. **Fewer features, same device:** Build the launcher and UI shell as a non-functional mock. Defer game running until JIT is resolved. This preserves UI work but does not solve the core problem.
2. **Other device / iOS version:** Test on a device running iOS 17.4–18.x where the old attach/detach JIT still works. If the user has access to such a device, we can target that iOS version and drop iOS 26/27 support.
3. **Wait for StikDebug support:** StikDebug issue #414 ("iOS 27 support") was closed as "StikDebug works on iOS 27, other apps need to update." Track StikDebug releases and MeloNX/UTM updates for compatibility patterns. If the app is added to the supported-apps list after we implement the universal protocol, the gap is closed.
4. **Do not ship without JIT:** The app cannot run games without JIT. A launcher-only build on iOS 27 is misleading. Present the options to the user and wait for a decision.

---

## 5. Toolchains

| Component | Toolchain | Notes |
|---|---|---|
| Wine unix libs | `llvm-mingw` + `cmake` + `ninja` + iOS SDK headers | Cross-compile ARM64 Darwin |
| Wine PE DLLs | `llvm-mingw` (ARM64EC target) | EC = Emulation-Compatible |
| FEX-Emu | `cmake` + `ninja` + Clang (arm64-apple-ios) | Darwin syscall handler |
| DXMT | `cmake` + `ninja` + Xcode Metal toolchain | `-sdk iphoneos`, ARM64 CPU family |
| Launcher / App | Xcode 15+ (`xcodebuild`) | `CODE_SIGNING_ALLOWED=NO` for CI unsigned IPA |
| CI runner | `macos-14` (Apple Silicon) or `macos-15` | GitHub-hosted, 6h job limit |
| Version control | `git` + `gh` CLI | Already authenticated in environment |

**Installed in CI via `actions/setup-xcode` + Homebrew:**
```yaml
- uses: maxim-lobanov/setup-xcode@v1
  with:
    xcode-version: "15.4"
- run: brew install cmake ninja llvm-mingw
```

---

## 6. Build Order & CI Job Design

### Job Graph

```
submodules-init
    ├── wine-unix-libs       (cache: ~/.local, key: wine-unix-{hash})
    ├── wine-pe-dlls         (cache: wine-pe-{hash})
    ├── fex-ios              (cache: fex-ios-{hash})
    ├── dxmt-ios             (cache: dxmt-ios-{hash})
    └── app-launcher-only    (no native deps — builds SwiftUI with MockCore)
            │
            └── build-ipa    (needs all native artifacts above)
                    └── upload-artifact / upload-release-asset
```

### Estimated CI Times (macos-14 runner)

| Job | Estimated Time | Cache Key | Output |
|---|---|---|---|
| `submodules-init` | 2–5 min | — | — |
| `wine-unix-libs` | 25–45 min | wine-unix-{sha} | `wine-unix.tar.zst` |
| `wine-pe-dlls` | 20–40 min | wine-pe-{sha} | `wine-pe.tar.zst` |
| `fex-ios` | 30–60 min | fex-ios-{sha} | `fex-ios.tar.zst` |
| `dxmt-ios` | 20–40 min | dxmt-ios-{sha} | `dxmt-ios.tar.zst` |
| `app-launcher-only` | 3–8 min | launcher-{hash} | — |
| `build-ipa` | 10–20 min | — | `Gamehub.ipa` |
| **Total (cold)** | **~110–215 min** | | |
| **Total (warm cache)** | **~30–60 min** | | |

**Keep every job under 6h.** Native builds are the bottleneck; aggressive caching is essential.

### Native Build Scripts

Each native component has a `build/*/build.sh` that:
1. Configures with cmake for `-target arm64-apple-ios17.4`
2. Builds with ninja
3. Stages artifacts into `build/stage/`
4. CI archives `build/stage/` as a cache artifact

---

## 7. Phases & Milestones

### Phase 0: Architect (this plan)
**Goal:** Write PLAN.md, set up repo structure, CI skeleton, submodules.
- [x] Survey Madeira codebase (README, ARCHITECTURE_ANALYSIS.md, CONTRIBUTING.md, STEAM_CEF_HANDOFF.md, build/, scripts/, patches/, app/)
- [ ] Fork Madeira submodules to Gamehub- organization
- [ ] Add `.gitmodules` pointing to forked submodules
- [ ] Create `PLAN.md` (this file)
- [ ] Create `PROGRESS.md`
- [ ] Create `.github/workflows/build-ipa.yml` skeleton
- [ ] Create launcher Swift package structure (empty targets)
- [ ] First commit → push → CI run → verify workflow syntax

**Done criteria:** Green CI run that checks out submodules and builds `app-launcher-only` (SwiftUI mock core). No native artifacts yet, but the pipeline runs.

---

### Phase 1: CI — Build IPA
**Goal:** GitHub Actions builds an unsigned `.ipa` from all native chains + Swift app.

- [ ] `build-ipa.yml` with matrix/cached jobs for:
  - `wine-unix-libs`
  - `wine-pe-dlls`
  - `fex-ios`
  - `dxmt-ios`
  - `build-ipa` (xcodebuild, CODE_SIGNING_ALLOWED=NO)
- [ ] Final job zips `Payload/Gamehub.app` → `Gamehub.ipa`
- [ ] Upload IPA as artifact
- [ ] On tag push: upload IPA as Release asset
- [ ] Add PROGRESS.md tracking

**Done criteria:** A green CI run produces an unsigned `.ipa` artifact. IPA structure verified (`Payload/Gamehub.app` exists, Info.plist present).

---

### Phase 2: Baseline on Device
**Goal:** Self-test screen, JIT verification, file logging. JIT is the gate — no game will run without it.

- [ ] Self-test screen: entitlement check (`get-task-allow`, `increased-memory-limit`), StikDebug availability, dual-mapped JIT allocation test, tiny ARM64 stub execution (`mov x0, #42; ret`), `phys_footprint` and `os_proc_available_memory()` at every step
- [ ] Clear failure mode logging for each JIT step (CS_DEBUGGED missing, region creation failed, prepare failed, execution returned wrong value, JIT dropped after detach)
- [ ] File logging to app container (visible in Files app)
- [ ] "Enable JIT with StikDebug" onboarding screen with exact checklist (pairing file, LocalDevVPN, StikDebug URL)
- [ ] README checklist for running a known-playable game (e.g., Thumper)
- [ ] PROGRESS.md updated

**Done criteria:** User confirms a game from the README runs on device. Logs show JIT pool granted, FEX initialized, WineProcessBridge started. If JIT cannot be made to work on iOS 27, stop and present fallback options before building the launcher.

---

### Phase 3: Launcher (Phase 3A–3E)
**Goal:** GameHub-style SwiftUI launcher, controller-first, CI screenshot validation.

#### Phase 3A: Project Structure & Design System
- [ ] Swift package `GamehubUI` with design tokens (colors, spacing, typography)
- [ ] Dark console theme, rounded corners, focus/scale animations, haptics
- [ ] CI renders placeholder screens on Simulator as artifact baseline

#### Phase 3B: Home Screen
- [ ] Hero banner "Continue playing"
- [ ] Horizontal shelves: Recent, Installed, Favorites
- [ ] Full Library grid of cover cards
- [ ] D-pad / focus-based navigation (GameController framework)
- [ ] CI screenshot artifact

#### Phase 3C: Game Page
- [ ] Poster, big Play button, playtime, last played
- [ ] Compatibility badge + notes
- [ ] Settings, Remove
- [ ] CI screenshot artifact

#### Phase 3D: Library Management
- [ ] Import from Files (folder bookmarks)
- [ ] Auto-scan for `.exe`, detect game name
- [ ] Manual add/edit; covers from local images or public source by AppID, cached on disk

#### Phase 3E: One-Tap Play & Settings
- [ ] Default profile applied automatically, per-game override
- [ ] Settings: resolution/scale, FPS cap + overlay, FEX/Wine presets (Performance/Balanced/Stability)
- [ ] Env vars, D3D/Metal options, audio
- [ ] Presets in `compat-db/games.json`
- [ ] CI screenshot artifact for every settings screen

**Done criteria:** Every launcher screen has a CI screenshot artifact. Controller navigation verified in Simulator. User approves look and feel.

---

### Phase 4: Compatibility
**Goal:** Per-game fixes driven by logs.

- [ ] COMPAT.md template
- [ ] `compat-db/games.json` schema
- [ ] One game per task, recorded in COMPAT.md + JSON
- [ ] In-app log viewer/export

**Done criteria:** At least 3 additional games beyond baseline have entries in COMPAT.md with working presets.

---

### Phase 5 (Optional, Last): Steam CEF
**Goal:** Read STEAM_CEF_HANDOFF.md, propose options with risks/ToS, implement only after approval.

- [ ] Read and summarize STEAM_CEF_HANDOFF.md for user
- [ ] Propose options (in-process Steam CEF vs external)
- [ ] Flag ToS concerns
- [ ] If approved: implement credentials in Keychain, never logged

**Done criteria:** Steam integration is either implemented with user approval or explicitly deferred.

---

## 8. Top Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| JIT on iOS 27 (TXM/SPTM) | High | Blocking | Implement universal protocol, pre-allocate all regions, verify on device before Phase 2 |
| Free Apple ID entitlement limits | High | Blocking | GetMoreRam for `increased-memory-limit`; document `extended-virtual-addressing` requirement for paid account |
| Thermal throttling kills performance | High | Degrades UX | Show thermal warning; auto-lower settings |
| Madeira submodule drift | Medium | CI breaks | Pin submodule SHAs; own the forks |
| FEX-Emu accuracy bugs (CEF render corruption) | Medium | Breaks some games | Log-and-quarantine; per-game workarounds in compat DB |
| GitHub Actions 6h timeout | Low | Blocking | Keep native jobs under 2h; cache aggressively |
| Apple revokes SideStore certificates | Low | Distribution | Document SideStore re-sign flow |

---

## 9. Entitlements

**Requires free-user enablement via GetMoreRam / iRAM+ (free):**
- `com.apple.developer.kernel.increased-memory-limit` — raises Jetsam physical RAM ceiling

**Requires paid Apple Developer Program ($99/yr), add only if Madeira demonstrably needs it:**
- `com.apple.developer.kernel.extended-virtual-addressing` — expands VA space beyond ~64 GB. Flag clearly if added. Do not require it by default.

**Runtime workaround (no entitlement needed):**
- StikDebug `process_control_disable_memory_limit` via debugger protocol

**Implementation rules:**
- Embed `com.apple.developer.kernel.increased-memory-limit` in the app's entitlements. Use ad-hoc codesign (`codesign --force --sign - --entitlements entitlements.plist`) or `ldid` in CI before zipping the IPA so SideStore's signer preserves it. Verify in CI with `codesign -d --entitlements :- Payload/Gamehub.app` and on device with `codesign -d --entitlements :- /var/containers/Bundle/Application/.../Gamehub.app`.
- Log `os_proc_available_memory()` and `phys_footprint` (via `task_basic_info` / `phys_footprint` from `XNU task`) at launch, after Wine boot, in the launcher, and in-game (with StikDebug attached / JIT on). Show values in Self-test and the FPS overlay.
- If the available memory ceiling looks low at startup, show a banner with exact steps: GetMoreRam / iRAM+ -> Sign in -> App IDs -> Refresh -> select this app's App ID -> Add Increased Memory Limit -> reinstall via SideStore. Re-check after every SideStore refresh/reinstall.
- Never assume the limit. Degrade gracefully if it is missing: lower default resolution scale, reduce FEX cache limits, disable Steam features on 4 GB tiers (see Device Tiers).

---

## 10. Device Tiers

Target ALL iPhones and iPads with >= 4 GB RAM that can run JIT + Metal. Mark older chips as unverified; never claim a tier is supported without a measured run or a tester's log.

| Tier | RAM | Example Devices | JIT Cache Limit | Default Resolution Scale | Steam Features | Notes |
|---|---|---|---|---|---|---|
| 4 GB | 4 GB | iPhone XR/XS, iPad 8th gen | ~128 MB | 0.75x | Headless SteamCMD only | Needs measured log; full CEF client likely does not fit |
| 6 GB | 6 GB | iPhone 14/14 Plus/15, iPad Air 5th gen | ~256 MB | 0.85x | Full Steam client, memory-aware | Author's test device; target primary tier |
| 8 GB | 8 GB | iPhone 15 Pro/15 Pro Max, iPad Pro 12.9" M2/M4 | ~512 MB | 1.0x | Full Steam client | Most headroom |

**Memory budgets (rules, not guarantees — validate with measurements):**
- Default target: ~50% of physical RAM used at launch (Wine boot + FEX JIT pool + DXMT).
- With `increased-memory-limit` active: target up to ~75% of physical RAM.
- Steam/CEF: measure headroom at login-window render. If headroom < ~600 MB on 4 GB, disable full client in favor of SteamCMD headless import.

**4 GB tester checklist (exact):**
1. Install SideStore + StikDebug + Gamehub IPA.
2. Grant "Increased Memory Limit" with iRAM+ or GetMoreRam (same App ID as SideStore).
3. Launch Gamehub, go to Self-test. Send back: iOS version, device model, `os_proc_available_memory()` at launch, `phys_footprint` after Wine boot, whether the memory banner appeared.
4. Run the README's playable-game checklist. Send back: game name, average FPS, whether it reached gameplay, any in-game log lines marked `[memory]` or `[JIT-pool]`.
5. If Steam was enabled: run Steam headless import (no full client). Send back: RAM used, whether library imported.

**Older chips:** Madeira was developed on A15 (iPhone 13 Pro). Mark chips older than A12 as unverified; do not claim support without a measured run.

---

## 11. Cover Art

Covers are never committed to the repo. Downloaded files live in the app's caches directory and are evictable.

- Primary source: Steam public CDN by AppID (`https://cdn.akamai.steamstatic.com/steam/apps/<AppID>/library_600x900.jpg`).
- Secondary source: custom local images imported by the user from Files.
- Future (optional, opt-in): SteamGridDB with a user-supplied API key, stored in Keychain, never logged. No IGDB.
- Cache policy: LRU, max 500 MB, evict during low-memory warnings and at app launch if over limit. Log cache hits/misses in the FPS overlay toggle.
- Network: downloads only on WiFi (or user opt-in cellular). Show a placeholder for missing covers.

---

## 12. Steam Integration — Memory-Aware Strategy

Steam is Phase 5, after launcher and baseline compatibility are stable. Do not attempt before then.

**Tiered approach:**
- 4 GB: headless SteamCMD under emulation, importing an existing Steam library folder from Files. No full Steam client, no CEF login window. Document ToS risks (Steam EULA prohibits circumventing the client; user accepts risk).
- 6 GB: full Steam client allowed, but monitor memory at login-window render. If `phys_footprint` approaches the measured ceiling for the device, offer SteamCMD import as a lighter alternative inside the launcher.
- 8 GB: full Steam client default, with CEF login window. Measure and record headroom.

**Before implementing Phase 5:**
1. Read STEAM_CEF_HANDOFF.md and summarize the open problem families (render corruption, KERN_MEMORY_ERROR crash, CM login/network) for the user.
2. Propose options with explicit RAM budgets and ToS risks.
3. Implement only after user approval.
4. Credentials only in Keychain, never logged. No copy/paste of Steam WebHelper secrets into files or logs.

---

## 13. Licensing & Upstream Policies

- **This project:** GPL-3.0-or-later
- **Madeira forks:** Wine (GPL-3.0-or-later via LGPL-2.1 §3), FEX (MIT preserved, mods GPL-3.0), DXMT (MIT preserved, mods GPL-3.0)
- **FEX-Emu upstream:** Prohibits AI-generated contributions. Check each upstream's policy before submitting changes upstream. Do not submit AI-generated changes from this fork to FEX-Emu upstream.
- **Other projects (e.g., WiniOS):** Read for ideas only after checking license. Do not copy code.
- **No Windows DLLs, games or copyrighted art in repo.** Support only user-owned games.

---

## 14. CI Time Budget Summary

| Phase | Est. CI Time (cold) | Est. CI Time (cached) |
|---|---|---|
| Phase 0 | 5 min (skeleton only) | — |
| Phase 1 | 110–215 min | 30–60 min |
| Phase 2 | +10 min (self-test build) | — |
| Phase 3A | +5 min | — |
| Phase 3B–3E | +5–15 min per screen | — |
| Phase 4 | +10 min | — |
| Phase 5 | +20 min (if approved) | — |

---

## 15. Open Questions (resolved / pending)

**Resolved by user answers:**
- Min iOS: 17.4+ for now. We will check StikDebug and Madeira docs after Phase 0 to see if a lower target is realistic; if so, we can drop it in a follow-up without changing architecture.
- Apple account: FREE only. `increased-memory-limit` enabled via GetMoreRam / iRAM+ (free). `extended-virtual-addressing` is NOT required by default; add only if Madeira demonstrably needs it, and flag it clearly.
- Steam: YES, keep Phase 5, but memory-aware per tier. Do not postpone indefinitely.
- Covers: Steam public CDN by AppID + custom local images, cached on disk, never committed. Optional SteamGridDB with user-supplied API key later. No IGDB.
- Devices: target ALL iPhones/iPads with >= 4 GB RAM. Author's test device: iPhone 14 Plus (A15, 6 GB).

**Pending user input (non-blocking for Phase 0):**
- Exact iOS version on the test device (to match CI runner SDK selection).
- Preferred SideStore channel / install method if GetMoreRam / iRAM+ behavior differs.
- Whether to track compatibility for Apple Silicon Macs running iOS simulator (not a gameplay target, but useful for CI screenshot review).

---

## 16. PROGRESS.md Template

```markdown
# PROGRESS.md

## Done
- [ ] Phase 0: PLAN.md written, repo structure created, CI skeleton green

## Next
- [ ] Phase 1: build-ipa.yml with cached native jobs

## Blockers
- None yet

## Decisions
- Base on Madeira (GPL-3.0-or-later), fork submodules to Gamehub- org
- Launcher is a Swift package building for iOS + iOS Simulator against MockCore
- Free Apple ID path; increased-memory-limit via GetMoreRam / iRAM+ (free)
- Extended Virtual Addressing not required; add only if Madeira demonstrably needs it
- Steam Phase 5, memory-aware per tier (4/6/8 GB)
- Covers: Steam CDN + local, never committed, optional SteamGridDB opt-in
```
