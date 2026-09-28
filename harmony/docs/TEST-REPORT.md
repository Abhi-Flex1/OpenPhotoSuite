# Test report — PhotoSuite HarmonyOS port

Date: 2026-09-28. Emulator: 2in1, HarmonyOS 6.1.1(24) (stable Release tools
6.1.1.280; image downloaded via the locale/timezone method documented in
`harmony/README.md`). HAP: `entry-default-unsigned.hap` (unsigned debug).

## Upstream suite (fork integrity)

From the repo root, unmodified upstream sources (`src/` 1-to-1 with
`eolix/photosuite@efc54dd`):

```
npm install        # 83 packages, 0 vulnerabilities
npm run vendor:fixlinks
npm test           # tests 1715, suites 419, pass 1715, fail 0, cancelled 0
```

## Build

```
cd harmony && ohpm install && sh scripts/sync-www.sh   # 25,634 files
hvigorw assembleApp                                    # BUILD SUCCESSFUL
```

ArkTS compiles clean (19 warnings, 0 errors). Output:
`harmony/entry/build/default/outputs/default/entry-default-unsigned.hap`
(256 MB — the full web tree ships in rawfile).

## Install / launch (emulator)

```
hdc -t 127.0.0.1:5555 install entry-default-unsigned.hap   # successfully
hdc -t 127.0.0.1:5555 shell aa start -b app.photosuite.harmony -a EntryAbility
```

First paint confirmed (`OnFirstScreenPaint`). Start screen renders 1-to-1
with desktop: menu bar, PS logo, New / Open buttons, Recents, version
0.9.14 — see `docs/screenshots/start-screen.jpeg`.

## Bridge boot contract (hilog, fresh boot)

Every desktop boot invoke is answered, in order:

```
invoke list_system_fonts
invoke list_user_resources
invoke get_app_version
invoke photosuite_install_native_menu
invoke __store_read            (x2: settings + thumbnails)
invoke ensure_plugins_directory
invoke discover_sidebar_plugins_command
invoke photosuite_install_native_menu   (menu refresh)
invoke take_pending_open_files
```

No uncaught page errors after the resource-server + loopback-server fixes.
Fresh boot shows no store warnings (`__store_read` returns null for
missing files, as on a fresh desktop profile).

## OS file-open pipeline (want URI)

```
aa start -b app.photosuite.harmony -a EntryAbility \
  -U file:///data/local/tmp/ps-test.png
```

Result: `EntryAbility created` → `take_pending_open_files` returns the URI
→ frontend `pickAndReadFile` → `read_file_raw` → frontend
`openFilesByPaths failed: No such file or directory`.

The pipeline is wired end to end; the read fails only because the app
sandbox cannot read `/data/local/tmp` (OS sandbox enforcement — the same
call succeeds for picker-granted URIs, which carry a URI permission grant).
Verified code path: `PendingFiles.ets` → `take_pending_open_files` →
`file-loader.js` → `read_file_raw` → `fs.openSync`.

## Not verifiable in this emulator session

Pointer injection (`uinput -M`, `uitest uiInput click`) reports success but
moves nothing observable — even the window close button and dock icons do
not react, and there is no mouse device (`uinput -M -q` → "Mouse is
invisible"). Keyboard events reach the ArkUI Web node (AceFocus
`Node Web handle KeyEvent`) but the page never acts on them (shortcuts,
Enter, Tab, typing all inert), so interactive flows — New-document dialog,
file picker, save dialog, confirm dialog, clipboard, gallery open — could
not be driven headlessly here. They need a real device or an emulator
session with working input.

## Known limitations (documented, by design)

- Image clipboard copy/paste falls back to in-app buffers
  (`plugin:clipboard-manager|write_image` is accepted and skipped; text
  clipboard is fully wired).
- Printing reports "not available on this platform" (same UX as a
  printer-less desktop).
- System-font catalog lists families without readable paths; embedded
  fonts render normally.
- `precomputeFilterGalleryThumbnails` may lose its boot-time race and log
  a caught warning; the gallery renders lazily on first open (upstream
  best-effort path, unchanged).
