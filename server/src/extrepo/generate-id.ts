import { createHash } from 'node:crypto';

/**
 * Mihon's source-id derivation, ported from `HttpSource.generateId`:
 *
 *   key    = "${name.lowercase()}/$lang/$versionId"
 *   digest = MD5(key)
 *   id     = first 8 bytes, big-endian, sign bit cleared
 *
 * **This is a test/diagnostic helper, not a lookup.** Ids are always read from
 * the repository index verbatim. `generateId` exists in Mihon precisely so an
 * extension can *keep* an id that no longer matches its current name — running
 * it over the live keiyoushi index reproduces 2,050 of 2,156 ids, and the other
 * 106 are deliberately frozen at a pre-rename value. Recomputing an id would
 * therefore silently orphan those sources from the vault rows that use them.
 *
 * Useful for: verifying the port against known ids in tests, and guessing the
 * former identity of a source id that no repository lists any more.
 */
export function generateSourceId(
  name: string,
  lang: string,
  versionId: number,
): string {
  const key = `${name.toLowerCase()}/${lang}/${versionId}`;
  const digest = createHash('md5').update(key, 'utf8').digest();
  let value = 0n;
  for (let i = 0; i < 8; i++) {
    value = (value << 8n) | BigInt(digest[i]);
  }
  return (value & 0x7fffffffffffffffn).toString();
}
