import type { BackupContainerKind } from './domain';

/**
 * Sniffs container framing from the first bytes of a backup file, following
 * Mihon's BackupDecoder rules:
 *  - `0x1f 0x8b` (gzip magic)      => gunzip, then protobuf  (`gzip-proto`)
 *  - first non-space byte is `{`   => legacy Tachiyomi JSON  (`legacy-json`)
 *  - anything else                 => raw protobuf           (`raw-proto`)
 */
export class ContainerDetector {
  detect(head: Uint8Array): BackupContainerKind {
    if (head.length >= 2 && head[0] === 0x1f && head[1] === 0x8b) {
      return 'gzip-proto';
    }
    // Skip leading whitespace / UTF-8 BOM before the JSON sniff.
    let i = 0;
    if (
      head.length >= 3 &&
      head[0] === 0xef &&
      head[1] === 0xbb &&
      head[2] === 0xbf
    ) {
      i = 3;
    }
    while (
      i < head.length &&
      (head[i] === 0x20 ||
        head[i] === 0x09 ||
        head[i] === 0x0a ||
        head[i] === 0x0d)
    ) {
      i++;
    }
    if (i < head.length && head[i] === 0x7b /* { */) {
      return 'legacy-json';
    }
    return 'raw-proto';
  }
}
