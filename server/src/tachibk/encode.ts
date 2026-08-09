import { gzip } from 'node:zlib';
import { promisify } from 'node:util';

import * as protobuf from 'protobufjs';

import { BACKUP_PROTO } from './backup.proto';
import { BackupEncodeError } from './errors';
import type { WireBackup } from './wire';

const gzipAsync = promisify(gzip);

/** Fallback app id for a backup that isn't aimed at a specific reading app. */
export const DEFAULT_EXPORT_APP_ID = 'mangavault';

/**
 * Encodes the wire model into `.tachibk` bytes — the exact inverse of
 * {@link BackupParser}, and pure in the same way (no I/O beyond the gzip
 * transform, no Nest/TypeORM).
 *
 * Uses the **same embedded schema** the decoder parses, which is what makes
 * `encode -> parse` a genuine round-trip rather than two hand-kept-in-sync
 * writers. Field numbers are the wire contract; nothing here may reorder them.
 */
export class BackupEncoder {
  private backupType: protobuf.Type | null = null;

  private get type(): protobuf.Type {
    if (!this.backupType) {
      const root = protobuf.parse(BACKUP_PROTO, { keepCase: true }).root;
      this.backupType = root.lookupType('mangavault.tachibk.Backup');
    }
    return this.backupType;
  }

  /**
   * Wire model -> gzipped protobuf, the container Mihon writes and expects.
   *
   * gzip runs **async** (`zlib.gzip`, not `gzipSync`): a real library
   * compresses megabytes, and this is a request-path call — the sync variant
   * would park the event loop for the whole compression.
   */
  async encode(
    backup: WireBackup,
    options: { gzip?: boolean } = {},
  ): Promise<Uint8Array> {
    let payload: Uint8Array;
    try {
      // fromObject (unlike create) accepts int64 fields as decimal strings,
      // which is how every 64-bit value travels through this lib.
      const message = this.type.fromObject(backup);
      payload = this.type.encode(message).finish();
    } catch (cause) {
      throw new BackupEncodeError(
        'protobuf',
        'failed to encode protobuf backup',
        cause,
      );
    }

    if (options.gzip === false) return payload;

    try {
      return await gzipAsync(payload);
    } catch (cause) {
      throw new BackupEncodeError('gzip', 'failed to gzip backup', cause);
    }
  }
}

/**
 * `<applicationId>_yyyy-MM-dd_HH-mm.tachibk`, Mihon's own convention
 * (`BackupCreator.getFilename()`).
 *
 * Named for the app the export is *aimed at*, not for MangaVault, and that is
 * deliberate: the filename is the only carrier of app identity in the format,
 * so a file exported for Komikku and later re-imported here is attributed to
 * Komikku by the very same regex the import path already uses.
 *
 * Local time, not UTC — the user recognises the backup by when they made it.
 */
export function buildBackupFileName(
  appId: string,
  at: Date = new Date(),
): string {
  const app = appId.trim().toLowerCase() || DEFAULT_EXPORT_APP_ID;
  const p = (n: number): string => String(n).padStart(2, '0');
  const stamp =
    `${at.getFullYear()}-${p(at.getMonth() + 1)}-${p(at.getDate())}` +
    `_${p(at.getHours())}-${p(at.getMinutes())}`;
  return `${app}_${stamp}.tachibk`;
}
