import type { BackupContainerKind } from './domain';

export type ParseStage = 'gunzip' | 'protobuf' | 'json';

/**
 * Thrown when a backup cannot be decoded. The parser is all-or-nothing: it
 * either returns a fully-formed ParsedBackup or throws this — it never returns
 * a partial result. Odd-but-decodable data becomes `warnings`, not errors.
 */
export class BackupParseError extends Error {
  constructor(
    readonly stage: ParseStage,
    message: string,
    readonly container?: BackupContainerKind,
    readonly cause?: unknown,
  ) {
    super(message);
    this.name = 'BackupParseError';
  }
}

export type EncodeStage = 'protobuf' | 'gzip';

/**
 * Thrown when a backup cannot be written. Kept separate from
 * {@link BackupParseError} so the export path can't accidentally be reported as
 * a corrupt *input* — an encode failure is always our bug, never the user's file.
 */
export class BackupEncodeError extends Error {
  constructor(
    readonly stage: EncodeStage,
    message: string,
    readonly cause?: unknown,
  ) {
    super(message);
    this.name = 'BackupEncodeError';
  }
}
