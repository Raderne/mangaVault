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
