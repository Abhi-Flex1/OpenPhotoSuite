import { common } from '@kit.AbilityKit';
import { socket } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';

const DOMAIN: number = 0x0A25;
const TAG: string = 'LocalHttpServer';

const CANDIDATE_PORTS: number[] = [14321, 15321, 16321, 17321, 18321];

/**
 * Minimal loopback HTTP/1.0-style file server for the bundled web tree.
 *
 * ArkWeb blocks XHR/fetch and ES-module loads to the resource:// scheme
 * (null origin, CORS), which stalls upstream boot at the synchronous
 * languages.json load and blocks main.js entirely. Serving the same rawfile
 * bytes over http://127.0.0.1:<port>/ makes every subresource same-origin,
 * so the unmodified upstream frontend boots exactly as on desktop.
 *
 * Only GET is served, always with `Connection: close`; each connection is
 * answered once from the rawfile and closed. Only loopback clients can
 * connect (binds 127.0.0.1), and `..` path segments are rejected.
 */
export class LocalHttpServer {
  private context: common.UIAbilityContext;
  private server: socket.TCPSocketServer | undefined = undefined;
  private pending: Map<number, number[]> = new Map<number, number[]>();
  port: number = 0;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async start(): Promise<number> {
    for (const port of CANDIDATE_PORTS) {
      try {
        await this.listenOnce(port);
        this.port = port;
        hilog.info(DOMAIN, TAG, 'Serving on 127.0.0.1:%{public}d', port);
        return port;
      } catch (e) {
        const message: string = e instanceof Error ? e.message : String(e);
        hilog.info(DOMAIN, TAG, 'Port %{public}d unavailable: %{public}s', port, message);
      }
    }
    throw new Error('no loopback port available');
  }

  url(): string {
    return 'http://127.0.0.1:' + this.port.toString() + '/index.html';
  }

  private listenOnce(port: number): Promise<void> {
    const server: socket.TCPSocketServer = socket.constructTCPSocketServerInstance();
    server.on('connect', (connection: socket.TCPSocketConnection) => {
      const id: number = connection.clientId;
      this.pending.set(id, []);
      connection.on('message', (info: socket.SocketMessageInfo) => {
        this.onChunk(connection, id, info.message);
      });
      connection.on('close', () => {
        this.pending.delete(id);
      });
    });
    return server.listen({ address: '127.0.0.1', port: port }).then(() => {
      this.server = server;
    }).catch((err: Error) => {
      try {
        server.close();
      } catch (e) {
      }
      throw err;
    });
  }

  private onChunk(connection: socket.TCPSocketConnection, id: number, chunk: ArrayBuffer): void {
    const stash: number[] | undefined = this.pending.get(id);
    if (stash === undefined) {
      return;
    }
    const bytes: Uint8Array = new Uint8Array(chunk);
    for (let i: number = 0; i < bytes.length; i++) {
      stash.push(bytes[i]);
    }
    if (stash.length > 65536) {
      this.respond(connection, id, 413, 'text/plain', this.encodeText('header too large'));
      return;
    }
    const headEnd: number = findHeaderEnd(stash);
    if (headEnd < 0) {
      return;
    }
    const headBytes: Uint8Array = new Uint8Array(headEnd);
    for (let i: number = 0; i < headEnd; i++) {
      headBytes[i] = stash[i];
    }
    const head: string = new util.TextDecoder('utf-8').decodeWithStream(headBytes, { stream: false });
    const firstLineEnd: number = head.indexOf('\r\n');
    const firstLine: string = firstLineEnd >= 0 ? head.substring(0, firstLineEnd) : head;
    const parts: string[] = firstLine.split(' ');
    if (parts.length < 2 || (parts[0] !== 'GET' && parts[0] !== 'HEAD')) {
      this.respond(connection, id, 405, 'text/plain', this.encodeText('method not allowed'));
      return;
    }
    const isHead: boolean = parts[0] === 'HEAD';
    const rawTarget: string = parts[1];
    let path: string = rawTarget.split('?')[0].split('#')[0];
    try {
      path = decodeURIComponent(path);
    } catch (e) {
      this.respond(connection, id, 400, 'text/plain', this.encodeText('bad request'));
      return;
    }
    if (path.length === 0 || path.charAt(0) !== '/') {
      this.respond(connection, id, 400, 'text/plain', this.encodeText('bad request'));
      return;
    }
    let relative: string = path.substring(1);
    if (relative.length === 0) {
      relative = 'index.html';
    }
    if (relative.indexOf('..') >= 0) {
      this.respond(connection, id, 403, 'text/plain', this.encodeText('forbidden'));
      return;
    }
    let body: Uint8Array;
    try {
      body = this.context.resourceManager.getRawFileContentSync(relative);
    } catch (e) {
      this.respond(connection, id, 404, 'text/plain', this.encodeText('not found'));
      return;
    }
    this.respond(connection, id, 200, mimeTypeOf(relative), isHead ? new Uint8Array(0) : body);
  }

  private encodeText(text: string): Uint8Array {
    return new util.TextEncoder().encodeInto(text);
  }

  private respond(connection: socket.TCPSocketConnection, id: number, code: number,
    mime: string, body: Uint8Array): void {
    this.pending.delete(id);
    const reason: string = code === 200 ? 'OK' : code === 400 ? 'Bad Request' :
      code === 403 ? 'Forbidden' : code === 404 ? 'Not Found' :
      code === 405 ? 'Method Not Allowed' : 'Error';
    const header: string = 'HTTP/1.1 ' + code.toString() + ' ' + reason + '\r\n' +
      'Content-Type: ' + mime + '\r\n' +
      'Content-Length: ' + body.length.toString() + '\r\n' +
      'Connection: close\r\n\r\n';
    const headerBytes: Uint8Array = this.encodeText(header);
    const out: Uint8Array = new Uint8Array(headerBytes.length + body.length);
    out.set(headerBytes, 0);
    out.set(body, headerBytes.length);
    connection.send({ data: out.buffer.slice(out.byteOffset, out.byteOffset + out.byteLength) })
      .catch(() => {
        hilog.info(DOMAIN, TAG, 'Send failed for %{public}d', code);
      }).then(() => {
        connection.close().catch(() => {
        });
      });
  }
}

function findHeaderEnd(stash: number[]): number {
  for (let i: number = 0; i + 3 < stash.length; i++) {
    if (stash[i] === 13 && stash[i + 1] === 10 && stash[i + 2] === 13 && stash[i + 3] === 10) {
      return i;
    }
  }
  return -1;
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
