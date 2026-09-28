import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { promptAction, font } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { drainOpenUris } from '../open/PendingFiles';

const DOMAIN: number = 0x0A25;
const TAG: string = 'TauriBridge';

/** Must match the upstream release this fork tracks (package.json). */
export const PHOTOSUITE_VERSION: string = '0.9.14';

const IMAGE_SUFFIXES: string[] = [
  'psd', 'psb', 'png', 'apng', 'jpg', 'jpeg', 'webp', 'avif',
  'tif', 'tiff', 'gif', 'bmp', 'tga', 'exr', 'svg', 'pdf',
  'ps', 'eps', 'ai', 'sketch', 'fig', 'xcf', 'dng', 'cr2', 'nef', 'arw'
];

interface BridgeEnvelope {
  id: string;
  cmd: string;
  args: Record<string, Object> | null;
  options: Record<string, Object> | null;
}

class BytesMarker {
  __bytesB64: string = '';
}

class OpenFileEntry {
  name: string = '';
  path: string = '';
}

class PrinterList {
  printers: Object[] = [];
  warning: string = '';
}

class SystemFontEntry {
  family: string = '';
  slant: string = '';
  weight: number = 400;
  stretch: string = '';
  postscript_name: string | null = null;
  path: string | null = null;
}

class UserResourceEntry {
  name: string = '';
  path: string = '';
  size: number = 0;
}

const B64_CHARS: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function base64Encode(bytes: Uint8Array): string {
  let out: string = '';
  let i: number = 0;
  while (i < bytes.length) {
    const b0: number = bytes[i++];
    const b1: number = i < bytes.length ? bytes[i++] : -1;
    const b2: number = i < bytes.length ? bytes[i++] : -1;
    const n: number = (b0 << 16) | ((b1 < 0 ? 0 : b1) << 8) | (b2 < 0 ? 0 : b2);
    out += B64_CHARS.charAt((n >> 18) & 63);
    out += B64_CHARS.charAt((n >> 12) & 63);
    out += b1 < 0 ? '=' : B64_CHARS.charAt((n >> 6) & 63);
    out += b2 < 0 ? '=' : B64_CHARS.charAt(n & 63);
  }
  return out;
}

function base64CharValue(code: number): number {
  if (code >= 65 && code <= 90) {
    return code - 65;
  }
  if (code >= 97 && code <= 122) {
    return code - 97 + 26;
  }
  if (code >= 48 && code <= 57) {
    return code - 48 + 52;
  }
  if (code === 43) {
    return 62;
  }
  if (code === 47) {
    return 63;
  }
  return -1;
}

function base64Decode(b64: string): Uint8Array {
  const clean: string = b64.replace(/\s/g, '');
  const out: number[] = [];
  let i: number = 0;
  while (i < clean.length) {
    const c0: number = base64CharValue(clean.charCodeAt(i++));
    const c1: number = base64CharValue(clean.charCodeAt(i++));
    const ch2: string = clean.charAt(i++);
    const ch3: string = clean.charAt(i++);
    if (c0 < 0 || c1 < 0) {
      break;
    }
    const v2: number = ch2 === '=' ? 0 : base64CharValue(ch2.charCodeAt(0));
    const v3: number = ch3 === '=' ? 0 : base64CharValue(ch3.charCodeAt(0));
    const n: number = (c0 << 18) | (c1 << 12) | ((v2 < 0 ? 0 : v2) << 6) | (v3 < 0 ? 0 : v3);
    out.push((n >> 16) & 255);
    if (ch2 !== '=') {
      out.push((n >> 8) & 255);
    }
    if (ch3 !== '=') {
      out.push(n & 255);
    }
  }
  const bytes: Uint8Array = new Uint8Array(out.length);
  for (let k: number = 0; k < out.length; k++) {
    bytes[k] = out[k];
  }
  return bytes;
}

function escapeJsSingleQuoted(value: string): string {
  return value.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, '\\n')
    .replace(/\r/g, '\\r').replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
}

function argString(args: Record<string, Object> | null, key: string, fallback: string): string {
  if (args === null) {
    return fallback;
  }
  const value: Object | undefined = args[key];
  if (typeof value === 'string') {
    return value as string;
  }
  return fallback;
}

function argBoolean(args: Record<string, Object> | null, key: string, fallback: boolean): boolean {
  if (args === null) {
    return fallback;
  }
  const value: Object | undefined = args[key];
  if (typeof value === 'boolean') {
    return value as boolean;
  }
  return fallback;
}

function sanitizeStoreFileName(name: string): string {
  const base: string = name.lastIndexOf('/') >= 0 ? name.substring(name.lastIndexOf('/') + 1) : name;
  if (base.length === 0 || base.length > 128 || !/^[A-Za-z0-9._-]+$/.test(base)) {
    throw new Error('invalid store file name');
  }
  return base;
}

function sanitizeResourceName(name: string): string {
  if (name.length === 0 || name.length > 128 || name.indexOf('/') >= 0 ||
    name.indexOf('\\') >= 0 || name.indexOf('..') >= 0) {
    throw new Error('invalid resource name');
  }
  return name;
}

function baseNameOfUri(uri: string): string {
  const clean: string = uri.split('?')[0];
  const slash: number = clean.lastIndexOf('/');
  const base: string = slash >= 0 ? clean.substring(slash + 1) : clean;
  try {
    return decodeURIComponent(base);
  } catch (e) {
    return base;
  }
}

function percentDecodePath(encoded: string): string {
  const bytes: number[] = [];
  let i: number = 0;
  while (i < encoded.length) {
    if (encoded.charAt(i) === '%') {
      const hex: string = encoded.substring(i + 1, i + 3);
      if (hex.length !== 2) {
        throw new Error('truncated percent-escape in path');
      }
      const value: number = parseInt(hex, 16);
      if (isNaN(value)) {
        throw new Error('bad percent-escape %' + hex);
      }
      bytes.push(value);
      i += 3;
    } else {
      bytes.push(encoded.charCodeAt(i));
      i += 1;
    }
  }
  const arr: Uint8Array = new Uint8Array(bytes.length);
  for (let k: number = 0; k < bytes.length; k++) {
    arr[k] = bytes[k];
  }
  return new util.TextDecoder('utf-8', { fatal: true }).decodeWithStream(arr, { stream: false });
}

/**
 * ArkTS host for the upstream PhotoSuite web frontend.
 *
 * The page calls window.nativeBridge.postMessage(JSON.stringify({id, cmd, args,
 * options})); each call is routed to a native handler and answered by invoking
 * window.__harmonyResolve(id, ok, payloadJson) in the page.
 *
 * Command names intentionally match the desktop src-tauri command set
 * (open_files, save_file, list_system_fonts, …) so upstream src/ runs 1-to-1.
 */
export class NativeBridge {
  private context: common.UIAbilityContext;
  private controller: webview.WebviewController | undefined = undefined;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  setController(controller: webview.WebviewController): void {
    this.controller = controller;
  }

  /**
   * Entry point called from JavaScript. Must stay synchronous and non-throwing;
   * all work continues asynchronously and answers via __harmonyResolve.
   */
  postMessage(envelope: string): void {
    let msg: BridgeEnvelope;
    try {
      msg = JSON.parse(envelope) as BridgeEnvelope;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Dropping malformed bridge envelope.');
      return;
    }
    if (msg === null || typeof msg.id !== 'string' || typeof msg.cmd !== 'string') {
      hilog.warn(DOMAIN, TAG, 'Dropping bridge envelope with missing id/cmd.');
      return;
    }
    hilog.info(DOMAIN, TAG, 'invoke %{public}s', msg.cmd);
    this.route(msg.cmd, msg.args, msg.options).then((result: Object | null) => {
      this.answer(msg.id, true, result);
    }).catch((err: Error) => {
      const message: string = err instanceof Error ? err.message : String(err);
      this.answer(msg.id, false, message);
    });
  }

  private answer(id: string, ok: boolean, value: Object | string | null): void {
    let payload: Object | string | null = value === undefined ? null : value;
    if (payload instanceof Uint8Array) {
      const marker: BytesMarker = new BytesMarker();
      marker.__bytesB64 = base64Encode(payload);
      payload = marker;
    }
    let json: string;
    try {
      json = JSON.stringify(payload === null ? null : payload);
    } catch (e) {
      json = 'null';
    }
    const script: string = 'window.__harmonyResolve(\'' + escapeJsSingleQuoted(id) + '\',' +
      (ok ? 'true' : 'false') + ',\'' + escapeJsSingleQuoted(json) + '\')';
    try {
      this.controller?.runJavaScript(script);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'runJavaScript answer failed.');
    }
  }

  private storesDir(): string {
    return this.context.filesDir + '/stores';
  }

  private pluginsDir(): string {
    return this.context.filesDir + '/plugins';
  }

  private resourcesDir(): string {
    return this.context.filesDir + '/resources';
  }

  private ensureDir(path: string): void {
    let exists: boolean = false;
    try {
      exists = fs.accessSync(path);
    } catch (e) {
      exists = false;
    }
    if (!exists) {
      fs.mkdirSync(path, true);
    }
  }

  private readWholeFile(path: string): Uint8Array {
    const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(path);
      const size: number = stat.size;
      const out: Uint8Array = new Uint8Array(size > 0 ? size : 0);
      let offset: number = 0;
      while (offset < out.length) {
        const chunk: ArrayBuffer = new ArrayBuffer(Math.min(65536, out.length - offset));
        const read: number = fs.readSync(file.fd, chunk, { offset: offset });
        if (read <= 0) {
          break;
        }
        out.set(new Uint8Array(chunk.slice(0, read)), offset);
        offset += read;
      }
      if (offset !== out.length) {
        return out.slice(0, offset);
      }
      return out;
    } finally {
      fs.closeSync(file);
    }
  }

  private writeWholeFile(path: string, bytes: Uint8Array): void {
    try {
      fs.unlinkSync(path);
    } catch (e) {
      // Missing file is the common case; anything else surfaces on open.
    }
    const file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    try {
      let offset: number = 0;
      while (offset < bytes.length) {
        const written: number = fs.writeSync(file.fd, bytes.buffer.slice(bytes.byteOffset + offset,
          bytes.byteOffset + bytes.length), { offset: offset });
        if (written <= 0) {
          break;
        }
        offset += written;
      }
    } finally {
      fs.closeSync(file);
    }
  }

  private async route(cmd: string, args: Record<string, Object> | null,
    options: Record<string, Object> | null): Promise<Object | null> {
    switch (cmd) {
      case 'get_app_version':
        return PHOTOSUITE_VERSION;
      case 'take_pending_open_files':
        return drainOpenUris();
      case 'read_third_party_notices':
        return this.readBundledText('THIRD-PARTY-NOTICES.md');
      case 'open_files':
        return await this.openFiles(argBoolean(args, 'imagesOnly', false));
      case 'read_file_raw':
      case 'read_file_bytes':
        return this.readWholeFile(argString(args, 'path', ''));
      case 'read_file_base64':
        return base64Encode(this.readWholeFile(argString(args, 'path', '')));
      case 'pick_save_path':
        return await this.pickSavePath(argString(args, 'defaultName', 'untitled.psd'));
      case 'save_file':
        this.saveFile(args, options);
        return null;
      case 'list_system_fonts':
        return this.listSystemFonts();
      case 'confirm_dialog':
        return await this.confirmDialog(argString(args, 'title', 'PhotoSuite'),
          argString(args, 'message', ''));
      case 'photosuite_install_native_menu':
        return null;
      case 'photosuite_emit_menu_action':
        return null;
      case 'photosuite_exit_app':
        this.context.terminateSelf();
        return null;
      case 'list_printers': {
        const printers: PrinterList = new PrinterList();
        printers.printers = [];
        printers.warning = 'printing is not available on this platform';
        return printers;
      }
      case 'submit_print_job':
        throw new Error('printing is not available on this platform');
      case 'ensure_plugins_directory':
        this.ensureDir(this.pluginsDir());
        return this.pluginsDir();
      case 'discover_sidebar_plugins_command':
        this.ensureDir(this.pluginsDir());
        return [];
      case 'ensure_resources_directory':
        this.ensureDir(this.resourcesDir());
        return this.resourcesDir();
      case 'list_user_resources':
        return this.listUserResources();
      case 'user_resource_path':
        return this.userResourcePath(argString(args, 'name', ''));
      case 'delete_user_resource':
        this.deleteUserResource(argString(args, 'name', ''));
        return null;
      case 'push_recent_thumbnail':
      case 'compact_recent_thumbnails':
        return true;
      case 'plugin:shell|open':
        this.openExternalUrl(argString(args, 'path', ''));
        return null;
      case 'plugin:dialog|message':
        this.showInfoMessage(argString(args, 'message', ''));
        return null;
      case 'plugin:clipboard-manager|write_image':
        hilog.info(DOMAIN, TAG, 'Clipboard image write is not supported on this platform; skipped.');
        return null;
      case '__store_read':
        return this.storeRead(sanitizeStoreFileName(argString(args, 'file', '')));
      case '__store_write':
        this.storeWrite(sanitizeStoreFileName(argString(args, 'file', '')),
          argString(args, 'json', '{}'));
        return true;
      case '__clipboard_write_text':
        await this.clipboardWriteText(argString(args, 'text', ''));
        return null;
      case '__clipboard_read_text':
        return await this.clipboardReadText();
      default:
        throw new Error('unknown command: ' + cmd);
    }
  }

  private readBundledText(rawfilePath: string): string {
    try {
      const data: Uint8Array = this.context.resourceManager.getRawFileContentSync(rawfilePath);
      return new util.TextDecoder('utf-8').decodeWithStream(data, { stream: false });
    } catch (e) {
      throw new Error('bundled text not found: ' + rawfilePath);
    }
  }

  private async openFiles(imagesOnly: boolean): Promise<Object> {
    void imagesOnly;
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
    let uris: Array<string>;
    try {
      uris = await documentPicker.select({ maxSelectNumber: 5 });
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      hilog.info(DOMAIN, TAG, 'Open dialog dismissed: %{public}s', message);
      return [];
    }
    const files: OpenFileEntry[] = [];
    for (const uri of uris) {
      const entry: OpenFileEntry = new OpenFileEntry();
      entry.name = baseNameOfUri(uri);
      entry.path = uri;
      files.push(entry);
    }
    return files;
  }

  private async pickSavePath(defaultName: string): Promise<string | null> {
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
    try {
      const uris: Array<string> = await documentPicker.save({
        newFileNames: [defaultName.length > 0 ? defaultName : 'untitled.psd']
      });
      if (uris.length === 0) {
        return null;
      }
      return uris[0];
    } catch (e) {
      hilog.info(DOMAIN, TAG, 'Save dialog dismissed.');
      return null;
    }
  }

  private saveFile(args: Record<string, Object> | null,
    options: Record<string, Object> | null): void {
    if (args === null) {
      throw new Error('save_file expects a binary invoke body (Uint8Array)');
    }
    const marker: Object | undefined = (args as Record<string, Object>)['__bytesB64'];
    if (typeof marker !== 'string') {
      throw new Error('save_file expects a binary invoke body (Uint8Array)');
    }
    let encodedPath: string = '';
    if (options !== null) {
      const headers: Object | undefined = options['headers'];
      if (headers !== null && typeof headers === 'object') {
        const value: Object | undefined = (headers as Record<string, Object>)['X-PhotoSuite-Path'];
        if (typeof value === 'string') {
          encodedPath = value;
        }
      }
    }
    if (encodedPath.length === 0) {
      throw new Error('missing X-PhotoSuite-Path header');
    }
    const path: string = percentDecodePath(encodedPath);
    this.writeWholeFile(path, base64Decode(marker));
  }

  private listSystemFonts(): Object {
    const entries: Object[] = [];
    try {
      const names: Array<string> = font.getSystemFontList();
      for (const fullName of names) {
        const family: string = fullName.split('-')[0].trim();
        if (family.length === 0) {
          continue;
        }
        const fontEntry: SystemFontEntry = new SystemFontEntry();
        fontEntry.family = family;
        fontEntry.slant = 'Regular';
        fontEntry.weight = 400;
        fontEntry.stretch = 'Normal';
        fontEntry.postscript_name = fullName;
        fontEntry.path = null;
        entries.push(fontEntry);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'System font query failed; using embedded fonts only.');
    }
    return entries;
  }

  private async confirmDialog(title: string, message: string): Promise<boolean> {
    try {
      const result = await promptAction.showDialog({
        title: title,
        message: message,
        buttons: [{ text: 'Cancel', color: '#9CA9A7' }, { text: 'OK', color: '#2BB8A7' }]
      });
      return result.index === 1;
    } catch (e) {
      return false;
    }
  }

  private showInfoMessage(message: string): void {
    try {
      promptAction.showToast({ message: message, duration: 2500 });
    } catch (e) {
      hilog.info(DOMAIN, TAG, 'Info message skipped.');
    }
  }

  private openExternalUrl(url: string): void {
    if (url.length === 0) {
      return;
    }
    try {
      this.context.openLink(url).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'openLink failed: %{public}s', err.message);
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'openLink unavailable.');
    }
  }

  private listUserResources(): Object[] {
    this.ensureDir(this.resourcesDir());
    const entries: Object[] = [];
    let names: Array<string>;
    try {
      names = fs.listFileSync(this.resourcesDir());
    } catch (e) {
      return entries;
    }
    for (const name of names) {
      const full: string = this.resourcesDir() + '/' + name;
      try {
        const stat = fs.statSync(full);
        if (!stat.isFile()) {
          continue;
        }
        const resource: UserResourceEntry = new UserResourceEntry();
        resource.name = name;
        resource.path = full;
        resource.size = stat.size;
        entries.push(resource);
      } catch (e) {
        continue;
      }
    }
    return entries;
  }

  private userResourcePath(name: string): string {
    const clean: string = sanitizeResourceName(name);
    this.ensureDir(this.resourcesDir());
    return this.resourcesDir() + '/' + clean;
  }

  private deleteUserResource(name: string): void {
    const path: string = this.userResourcePath(name);
    try {
      fs.unlinkSync(path);
    } catch (e) {
      throw new Error('resource not found: ' + name);
    }
  }

  private storeRead(file: string): string | null {
    this.ensureDir(this.storesDir());
    const path: string = this.storesDir() + '/' + file;
    let exists: boolean = false;
    try {
      exists = fs.accessSync(path);
    } catch (e) {
      exists = false;
    }
    if (!exists) {
      return null;
    }
    const bytes: Uint8Array = this.readWholeFile(path);
    return new util.TextDecoder('utf-8').decodeWithStream(bytes, { stream: false });
  }

  private storeWrite(file: string, json: string): void {
    this.ensureDir(this.storesDir());
    const encoder: util.TextEncoder = new util.TextEncoder();
    this.writeWholeFile(this.storesDir() + '/' + file, encoder.encodeInto(json));
  }

  private async clipboardWriteText(text: string): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createPlainTextData(text));
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Clipboard write failed.');
    }
  }

  private async clipboardReadText(): Promise<string> {
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      try {
        return data.getPrimaryText();
      } catch (e) {
        return '';
      }
    } catch (e) {
      return '';
    }
  }
}
