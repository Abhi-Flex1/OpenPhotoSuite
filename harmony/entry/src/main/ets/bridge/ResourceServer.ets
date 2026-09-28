import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0A25;
const TAG: string = 'ResourceServer';

const SCHEME_PREFIX: string = 'resource://rawfile/';

/**
 * Serves the bundled PhotoSuite web tree (rawfile root) to the Web page
 * through onInterceptRequest.
 *
 * Two problems make this necessary while keeping upstream src/ 1-to-1:
 * 1. Upstream index.html references absolute paths ("/core/i18n/...",
 *    "/assets/..."), which resolve against the rawfile root.
 * 2. ArkWeb blocks XHR/fetch to the resource:// scheme from a null origin
 *    (CORS), which stalls boot at the synchronous languages.json load.
 *
 * Answering from the rawfile with an explicit MIME type fixes both: every
 * subresource load — scripts, styles, images, JSON, WASM — resolves locally.
 */
export class ResourceServer {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  answer(url: string): WebResourceResponse | null {
    if (!url.startsWith(SCHEME_PREFIX)) {
      return null;
    }
    let path: string = url.substring(SCHEME_PREFIX.length);
    const query: number = path.indexOf('?');
    if (query >= 0) {
      path = path.substring(0, query);
    }
    const hash: number = path.indexOf('#');
    if (hash >= 0) {
      path = path.substring(0, hash);
    }
    if (path.length === 0 || path.indexOf('..') >= 0) {
      return null;
    }
    let data: Uint8Array;
    try {
      data = this.context.resourceManager.getRawFileContentSync(path);
    } catch (e) {
      return null;
    }
    try {
      const response = new WebResourceResponse();
      response.setResponseData(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength));
      response.setResponseCode(200);
      response.setResponseMimeType(mimeTypeOf(path));
      response.setResponseEncoding('utf-8');
      return response;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Intercept answer failed for %{public}s', path);
      return null;
    }
  }
}

function mimeTypeOf(path: string): string {
  const dot: number = path.lastIndexOf('.');
  const ext: string = dot >= 0 ? path.substring(dot + 1).toLowerCase() : '';
  switch (ext) {
    case 'html':
    case 'htm':
      return 'text/html';
    case 'css':
      return 'text/css';
    case 'js':
    case 'mjs':
      return 'text/javascript';
    case 'json':
    case 'map':
      return 'application/json';
    case 'wasm':
      return 'application/wasm';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'avif':
      return 'image/avif';
    case 'svg':
      return 'image/svg+xml';
    case 'ico':
      return 'image/x-icon';
    case 'ttf':
      return 'font/ttf';
    case 'otf':
      return 'font/otf';
    case 'woff':
      return 'font/woff';
    case 'woff2':
      return 'font/woff2';
    case 'pdf':
      return 'application/pdf';
    case 'xml':
      return 'text/xml';
    case 'txt':
    case 'md':
      return 'text/plain';
    default:
      return 'application/octet-stream';
  }
}
