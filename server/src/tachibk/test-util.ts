import { gzipSync } from 'node:zlib';

import * as protobuf from 'protobufjs';

import { BACKUP_PROTO } from './backup.proto';

/**
 * Test helper: encode a plain-object Backup into wire bytes using the very same
 * schema the parser uses, so specs exercise a genuine protobuf round-trip.
 */
const root = protobuf.parse(BACKUP_PROTO, { keepCase: true }).root;
const BackupType = root.lookupType('mangavault.tachibk.Backup');

export function encodeBackup(backup: Record<string, unknown>): Uint8Array {
  // fromObject (unlike verify) accepts int64 fields as decimal strings.
  const msg = BackupType.fromObject(backup);
  return BackupType.encode(msg).finish();
}

export function encodeBackupGzip(backup: Record<string, unknown>): Uint8Array {
  return gzipSync(encodeBackup(backup));
}
