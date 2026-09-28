/**
 * Queue of file URIs the OS asked the app to open (cold start via want.uri
 * or warm start via onNewWant), drained by take_pending_open_files.
 * Mirrors the desktop PendingOpenFiles queue in src-tauri.
 */

const pending: string[] = [];

export function queueOpenUri(uri: string | undefined | null): void {
  if (uri === undefined || uri === null || uri.length === 0) {
    return;
  }
  pending.push(uri);
}

export function drainOpenUris(): string[] {
  return pending.splice(0, pending.length);
}
