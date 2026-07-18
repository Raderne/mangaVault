import { gunzipSync } from 'node:zlib';

import * as protobuf from 'protobufjs';

import { BACKUP_PROTO } from './backup.proto';
import { ContainerDetector } from './detect';
import type { BackupContainerKind, ParsedBackup } from './domain';
import { BackupParseError } from './errors';
import { parseLegacyJson } from './legacy-json';
import type { WireBackup } from './wire';

/** `<applicationId>_yyyy-MM-dd_HH-mm.tachibk` — group 1 is the app id. */
const TACHIBK_NAME_RE = /^(.+)_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}\.tachibk$/i;

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
        sourceApp: extractSourceApp(fileName, container),
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
      sourceApp: extractSourceApp(fileName, container),
      warnings,
    };
  }
}

function extractSourceApp(
  fileName: string,
  container: BackupContainerKind,
): string {
  const base = fileName.split(/[\\/]/).pop() ?? fileName;
  if (container === 'legacy-json') return '';
  const m = TACHIBK_NAME_RE.exec(base);
  return m ? m[1] : '';
}
