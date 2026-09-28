# PhotoSuite for HarmonyOS

HarmonyOS platform port of [PhotoSuite](https://github.com/eolix/photosuite)
(`upstream@efc54dd`), targeting **HarmonyOS 6.1.1 (API 24)** on tablet / 2in1.

Upstream `src/` is kept **1-to-1** at the repo root — no upstream web file is
modified. The desktop Tauri host (`src-tauri/`, officially desktop/mobile only
with no HarmonyOS target) is replaced by a native ArkTS host that serves the
unmodified web UI in a `Web` component and answers the exact same
`window.__TAURI__.core.invoke` command set.

## Layout

- `src/`, `src-tauri/`, `tests/`, `docs/` — upstream fork, 1-to-1
- `harmony/` — this platform shell:
  - `AppScope/` — bundle `app.photosuite.harmony`, v0.9.14 (versionCode 9014)
  - `entry/src/main/ets/pages/Index.ets` — full-screen `Web` loading the UI
  - `entry/src/main/ets/bridge/TauriShim.ets` — `window.__TAURI__` bootstrap
    injected before upstream module scripts run
  - `entry/src/main/ets/bridge/TauriBridge.ets` — `nativeBridge` proxy:
    file open/save via `DocumentViewPicker`, JSON-file stores
    (`settings.json`, thumbnail caches), text clipboard, confirm/info dialogs,
    system-font listing, bundled notices, graceful no-print/no-native-menu
  - `entry/src/main/resources/rawfile/` — **generated** by
    `scripts/sync-www.sh` from `src/` (+ notices/license); gitignored
  - `scripts/sync-www.sh` — sync the web tree into the HAP

## Bridge command coverage

All desktop commands are answered: `open_files`, `read_file_raw`,
`read_file_bytes`, `read_file_base64`, `pick_save_path`, `save_file`,
`get_app_version`, `read_third_party_notices`, `take_pending_open_files`,
`list_system_fonts`, `confirm_dialog`, `photosuite_install_native_menu`
(accepted; the in-page HTML menu stays since the UA is not macOS),
`photosuite_emit_menu_action`, `photosuite_exit_app`, `list_printers`
(empty + warning, as on printer-less desktops), `submit_print_job`
(unavailable error), `ensure_plugins_directory`,
`discover_sidebar_plugins_command` (empty), `ensure_resources_directory`,
`list_user_resources`, `user_resource_path`, `delete_user_resource`,
`push_recent_thumbnail`, `compact_recent_thumbnails`,
`plugin:shell|open` (openLink), `plugin:dialog|message`,
`plugin:clipboard-manager|write_image` (skipped, logged),
`__store_read` / `__store_write` / `__clipboard_write_text` /
`__clipboard_read_text` (shim internals).

Known limitations vs desktop: image clipboard copy/paste falls back to
in-app buffers, printing is unavailable, the system-font catalog lists
families without readable paths. Everything else — editor, layers, filters,
WASM codecs, stores, dialogs — runs unmodified.

## Prerequisites

- HarmonyOS Command Line Tools 6.1.1 (hvigor 6.24.2, ohpm 6.1.2, SDK API 24)
- JDK 17 (`brew install openjdk@17`), Node (upstream needs v25+ for tooling)
- `~/.npmrc` containing `@ohos:registry=https://repo.harmonyos.com/npm/`

## Build (unsigned debug HAP)

```bash
export PATH="$HOME/Developer/command-line-tools/bin:/opt/homebrew/opt/openjdk@17/bin:$HOME/Developer/command-line-tools/tool/node/bin:$PATH"
export DEVECO_SDK_HOME="$HOME/Developer/command-line-tools/sdk"
export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
cd harmony
ohpm install
sh scripts/sync-www.sh
hvigorw assembleApp --mode debug
# outputs harmony/build/outputs/default/*.app + entry HAP
```

Upstream suite (from repo root): `npm install && npm test` (1715 tests).

## Emulator (2in1, HarmonyOS 6.1.1)

Image download is geo-gated to the Chinese mainland since DevEco 6.1.0 Beta1;
the locale/timezone exports below are enough, no proxy software needed:

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
# once hdc lists 127.0.0.1:5555:
hdc list targets
hdc -t 127.0.0.1:5555 install <entry-default-unsigned.hap>
hdc -t 127.0.0.1:5555 shell aa start -b app.photosuite.harmony -a EntryAbility
```

## Screenshots (2in1 emulator, 3120x2080)

![Start screen](docs/screenshots/start-screen.jpeg)

## Test report

See [`docs/TEST-REPORT.md`](docs/TEST-REPORT.md): upstream suite 1715/1715,
clean `hvigorw assembleApp`, emulator install + launch with full boot-invoke
trace, OS file-open pipeline result, and the input limits of this emulator
session.

## License

GPL-3.0-only, same as upstream (`LICENSE` at repo root).
