# OpenPhotoSuite — PhotoSuite for HarmonyOS

A complete port of **[PhotoSuite](https://github.com/eolix/photosuite)** —
the desktop image editor faithfully replicating classic Adobe Photoshop with
1:1 native PSD/PSB compatibility — to **HarmonyOS 6.1.1 (API 24)** on tablet
and 2in1 devices.

The entire upstream application (`upstream@efc54dd`: editor, layers, filters,
WASM codecs, PSD/PSB engine) runs **unmodified** on HarmonyOS with the exact
same UI as the desktop original.

![Start screen on the 2in1 emulator](harmony/docs/screenshots/start-screen.jpeg)

*PhotoSuite 0.9.14 start screen on the HarmonyOS 6.1.1 2in1 emulator
(3120×2080): native menu bar, PS branding, New / Open actions, Recents —
pixel-for-pixel the desktop experience.*

## What this is

A fork of upstream PhotoSuite with a HarmonyOS platform shell added — the
same "fork it and add the platform" approach used for the emulator setup in
this project's history. Upstream `src/` is kept **1-to-1** at the repo root;
no upstream web file is modified.

Tauri officially targets desktop and mobile only — there is no HarmonyOS
target — so the desktop Rust host (`src-tauri/`) is replaced by a native
ArkTS host under `harmony/` that serves the untouched web UI in a `Web`
component and answers the exact same `window.__TAURI__` command set:

```
┌─────────────────────────────┐      ┌──────────────────────────────┐
│  upstream src/ (1-to-1)     │      │  harmony/ ArkTS host         │
│  index.html, UI, engine,    │◄────►│  LocalHttpServer (loopback)  │
│  WASM, PSD/PSB, filters     │ HTTP │  TauriShim (window.__TAURI__)│
│                             │      │  TauriBridge (native impl)   │
└─────────────────────────────┘      │  ResourceServer (fallback)   │
                                     └──────────────────────────────┘
```

Two platform problems had to be solved with zero changes to upstream files:

1. **Absolute asset paths** (`/core/i18n/…`, `/assets/…`) resolve against
   the rawfile root, so the web tree is synced to the rawfile root.
2. **ArkWeb blocks XHR/fetch and ES-module loads to `resource://`**
   (null origin, CORS), which stalls boot at the synchronous
   `languages.json` load and blocks `main.js` entirely. A minimal loopback
   HTTP server (`LocalHttpServer.ets`, 127.0.0.1, `INTERNET` permission for
   loopback only) serves the same rawfile bytes over
   `http://127.0.0.1:<port>/`, making every subresource same-origin — the
   app then boots exactly as on desktop.

## Features (all upstream, all working)

- **Layer engine**: raster/vector layers, groups, clipping and layer masks,
  blending modes, Smart Objects, history with snapshots
- **Full toolset**: marquee, lasso, wand, crop, brush, clone/healing,
  eraser, gradient, blur/sharpen, dodge/burn, pen, type, shapes, text,
  guides, rulers, zoom
- **Filters & adjustments**: filter gallery, exposure/contrast/saturation,
  presets — WASM-accelerated
- **Format support**: PSD/PSB round-trip plus PNG, JPEG, WebP, AVIF, TIFF,
  GIF, SVG, PDF, camera RAW and more, via the native file picker
- **Desktop integrations, re-hosted**: native open/save dialogs,
  persistent settings + thumbnail caches, text clipboard, confirm/info
  dialogs, system fonts, OS file-open (`want.uri` → pending queue, the
  desktop "Open With" parity)

Known deltas vs desktop: image clipboard falls back to in-app buffers,
printing reports unavailable (same UX as a printer-less desktop), system
fonts list without readable paths. Everything else runs unmodified.

## Repository layout

- `src/`, `src-tauri/`, `tests/`, `docs/`, `website/`, … — upstream fork
- `harmony/` — the HarmonyOS platform shell (`AppScope/`, `entry/` with
  `pages/Index`, `bridge/` shims, `scripts/sync-www.sh`, `docs/` with
  screenshots and test report)

## Build

Requirements: HarmonyOS Command Line Tools 6.1.1, JDK 17, Node (upstream
tooling wants v25+), and `~/.npmrc` with
`@ohos:registry=https://repo.harmonyos.com/npm/`.

```bash
# web tests (proves the fork is intact)
npm install && npm run vendor:fixlinks && npm test   # 1715/1715 pass

# HarmonyOS HAP (unsigned debug)
export PATH="$HOME/Developer/command-line-tools/bin:/opt/homebrew/opt/openjdk@17/bin:$HOME/Developer/command-line-tools/tool/node/bin:$PATH"
export DEVECO_SDK_HOME="$HOME/Developer/command-line-tools/sdk"
export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
cd harmony
ohpm install
sh scripts/sync-www.sh
hvigorw assembleApp
```

### Signed release builds

A signed HAP needs Huawei-issued materials for this bundle
(`app.photosuite.harmony`) that only come from a Huawei developer account —
they are never committed. To sign: create the app in AppGallery Connect,
issue an app certificate (`.p12`/`.cer`) and a provisioning profile
(`.p7b`), place them outside the repo, and point a `signingConfigs` entry
at them in `harmony/build-profile.json5` (see DevEco Studio → Project
Structure → Signing Configs). Pre-built HAPs are attached to GitHub
releases (see below); the current artifacts are unsigned debug builds,
which install and run on the emulator.

## Emulator (2in1, HarmonyOS 6.1.1)

Image download is geo-gated to the Chinese mainland since DevEco 6.1.0
Beta1; the locale/timezone exports below are enough — no proxy needed:

```bash
export PATH="$HOME/Developer/command-line-tools/bin:$PATH"
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
export TZ=Asia/Shanghai
Emulator -license accept
Emulator -imageList -deviceType 2in1
Emulator -install -deviceType 2in1 -osVersion "HarmonyOS 6.1.1(24)" -force
# ~2.5 GB ARM64 image
Emulator -create OpenPhotoSuite2in1 -deviceType 2in1 -osVersion "HarmonyOS 6.1.1(24)"
ln -sfn ~/Developer/command-line-tools/sdk ~/Developer/sdk
Emulator -start OpenPhotoSuite2in1
# once hdc lists 127.0.0.1:5555 (hdc lives under
# command-line-tools/sdk/default/openharmony/toolchains/):
hdc -t 127.0.0.1:5555 install <entry-*.hap>
hdc -t 127.0.0.1:5555 shell aa start -b app.photosuite.harmony -a EntryAbility
```

## Testing

[`harmony/docs/TEST-REPORT.md`](harmony/docs/TEST-REPORT.md) records the
full results: upstream suite 1715/1715, clean `hvigorw assembleApp`,
emulator install + launch with the complete boot-invoke trace, the OS
file-open pipeline result, and the input limits of the emulator session
used here.

## Releases

Pre-built HAPs are attached to [GitHub releases](../../releases) with
SHA-256 checksums.

## Attribution & license

Upstream PhotoSuite by [eolix](https://github.com/eolix/photosuite) and its
contributors; third-party notices in `THIRD-PARTY-NOTICES.md`. This port
adds only the `harmony/` shell. **GPL-3.0-only** (`LICENSE`).
