import { gunzipSync } from 'node:zlib';

import * as protobuf from 'protobufjs';

import { BACKUP_PROTO } from './backup.proto';
import { ContainerDetector } from './detect';
import type { ParsedBackup } from './domain';
import { BackupParseError } from './errors';
import { parseLegacyJson } from './legacy-json';
import type { WireBackup } from './wire';

/**
 * `<applicationId>_<timestamp>.tachibk` — group 1 is the app id.
 *
 * Anchored on the ISO **date** rather than a fixed time format. Mihon writes
 * `_yyyy-MM-dd_HH-mm` (`BackupCreator.getFilename()`), but forks vary the tail
 * (date only, seconds, a suffix) and only the prefix identifies the producing
 * app. Non-greedy so the *first* date in the name ends the prefix.
 */
const BACKUP_NAME_RE = /^(.+?)_(?:\d{4}-\d{2}-\d{2}.*)\.(?:tachibk|json)$/i;

/** Longer than any real Android application id — a longer capture is noise. */
const MAX_SOURCE_APP_LEN = 100;

/**
 * Decodes a `.tachibk` (gzip+protobuf or raw protobuf) or legacy `.json` backup
 * into the wire model. Pure and side-effect free (no I/O) so it is unit-testable.
 *
 * Unknown protobuf fields are ignored; missing optionals stay `undefined` and
 * receive Mihon defaults later, in the normalizer.
 */
export class BackupParser {
  private readonly detector = new ContainerDetector();
  private backupType: protobuf.Type | null = null;

  private get type(): protobuf.Type {
    if (!this.backupType) {
      const root = protobuf.parse(BACKUP_PROTO, { keepCase: true }).root;
      this.backupType = root.lookupType('mangavault.tachibk.Backup');
    }
    return this.backupType;
  }

  // Async by contract (BackupParser interface, phase-2 §1) though decoding is
  // currently synchronous — leaves room for streaming/async decoders later.
  // eslint-disable-next-line @typescript-eslint/require-await
  async parse(file: Uint8Array, fileName: string): Promise<ParsedBackup> {
    const warnings: string[] = [];
    const container = this.detector.detect(file.subarray(0, 8));

    if (container === 'legacy-json') {
      const wire = parseLegacyJson(file, warnings);
      return {
        wire,
        container,
        sourceApp: extractSourceApp(fileName),
        warnings,
      };
    }

    let payload = file;
    if (container === 'gzip-proto') {
      try {
        payload = gunzipSync(file);
      } catch (cause) {
        throw new BackupParseError(
          'gunzip',
          'failed to gunzip backup',
          container,
          cause,
        );
      }
    }

    let wire: WireBackup;
    try {
      const message = this.type.decode(payload);
      wire = this.type.toObject(message, {
        longs: String, // int64 -> decimal string (JS number unsafe > 2^53)
        enums: Number,
        bytes: Array,
        defaults: false, // absent -> undefined; normalizer applies Mihon defaults
        arrays: true, // repeated fields always present as [] (never undefined)
        objects: true,
      });
    } catch (cause) {
      throw new BackupParseError(
        'protobuf',
        'failed to decode protobuf backup',
        container,
        cause,
      );
    }

    return {
      wire,
      container,
      sourceApp: extractSourceApp(fileName),
      warnings,
    };
  }
}

/**
 * The producing app's id from the backup filename, `''` when the name doesn't
 * follow the convention. `''` is the signal the import UI uses to ask the user
 * which app the backup came from, so a wrong guess is worse than none: a prefix
 * that can't be an application id is rejected rather than stored.
 */
function extractSourceApp(fileName: string): string {
  const base = (fileName.split(/[\\/]/).pop() ?? fileName).trim();
  const m = BACKUP_NAME_RE.exec(base);
  if (!m) return '';

  const app = m[1].trim().toLowerCase();
  if (!app || app.length > MAX_SOURCE_APP_LEN || /\s/.test(app)) return '';
  return app;
}
