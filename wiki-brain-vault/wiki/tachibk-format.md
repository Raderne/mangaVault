# .tachibk parsing (server)

Created: 2026-07-18 (M2)

Related: [[index]] · [[backend]] · [[import-pipeline]] · [[backup-apps]]

Implementation of the `.tachibk` / legacy-JSON parsing library. Pure TypeScript, **zero
Nest/TypeORM imports**, fully unit-tested. Lives in `server/src/tachibk/`. Extends the schema
reference in `docs/phase-1-data-structures.md` §1 with what was actually learned building it.

## Pipeline

`file bytes → ContainerDetector → BackupParser → (wire model) → BackupNormalizer → NormalizedBackup`

- `detect.ts` — peeks first bytes: `0x1f8b` ⇒ `gzip-proto`; first non-space byte `{` ⇒
  `legacy-json`; else `raw-proto`. Skips a UTF-8 BOM + whitespace before the JSON sniff.
- `parse.ts` — `BackupParser`: gunzip (if needed) → protobuf decode → wire object. Legacy JSON is
  delegated to `legacy-json.ts`. All-or-nothing: returns a `ParsedBackup` or throws
  `BackupParseError { stage: 'gunzip'|'protobuf'|'json' }`. Odd-but-decodable data ⇒ `warnings[]`,
  never an error.
- `normalize.ts` — `BackupNormalizer`: applies Mihon defaults, maps enums, resolves categories,
  folds history. Pure/deterministic.

## Decisions & gotchas (learned building it)

- **protobufjs, schema embedded as a string** (`backup.proto.ts`), parsed at first use with
  `protobuf.parse(...)`. No `.proto` asset file → nothing to copy into `dist/`, lib stays
  self-contained. Dependency added: `protobufjs@^7`.
- **int64 → decimal strings.** Decode via `Type.toObject(msg, { longs: String })`. Source ids and
  tracker media ids stay strings end-to-end; epoch-millis are `Number()`-ed in the normalizer
  (safe, < 2^53). Verified with an int64-max fixture.
- **`favorite` presence tracking.** proto3 can't tell absent from `false`, but Mihon defaults
  `favorite` to **true** when absent. So it is declared `optional bool` in the embedded proto →
  protobufjs tracks presence → normalizer does `favorite ?? true`. Present-`false` is preserved.
- **`toObject` options:** `{ longs: String, defaults: false, arrays: true, objects: true }`.
  `defaults:false` so absent scalars are `undefined` and the normalizer owns every default (needed
  for the favorite rule); `arrays:true` so repeated fields are always `[]`, never `undefined`.
- **Unknown fields are ignored** by the decoder (forks add higher field numbers) — never fail on
  them, per the wire-contract rule.
- **Legacy JSON is best-effort** (`legacy-json.ts`). Mihon rejects legacy JSON; we adapt the
  object-keyed shape (named/snake_case fields, optionally nested under a `manga` key) into the same
  wire model so the normalizer is format-agnostic. **Known limitation:** a bare (unquoted) 64-bit
  `source` id in JSON is already mangled by `JSON.parse` (JS number, > 2^53) before we see it — it
  only survives if the export quoted the id. We emit a warning when we detect an unsafe numeric
  source id. Protobuf is the primary path; the user's Mihon produces protobuf, not legacy JSON.
- **The filename is the only source of app identity.** The `Backup` message carries no
  producer/version field, and `backupPreferences` / `backupSourcePreferences` / `backupExtensionRepo`
  (which *could* hint at a fork) are decoded but deliberately not surfaced. So `extractSourceApp`
  parses the name, anchored on the ISO date rather than Mihon's exact time format, and returns `''`
  rather than guessing — see [[backup-apps]].
- **`PreferenceValue` (polymorphic prefs)** — decoded into the wire model but **not surfaced** to
  the domain layer in v1 (per phase-3 "low priority; don't crash"). No app preferences are imported.

## Normalization rules

- status int → `PublicationStatus` (0 unknown … 6 on_hiatus).
- `BackupManga.categories` are category **order** values (not ids) → resolved to names via
  `BackupCategory.order`.
- History folded into chapters by url: `lastReadAt = max(lastRead)`, `readDuration = sum`.
- Tracking `syncId` → `TrackerId` (1 MAL … 7 MangaUpdates, else `unknown:<id>`); `remoteId` uses
  the deprecated `mediaIdInt` only when non-zero, else the int64 `mediaId`.
- A manga missing `source`/`url` is skipped with a warning (can't form a [[import-pipeline]] key).

## Tests

`server/src/tachibk/*.spec.ts` (16 cases). Fixtures are built by `test-util.ts`, which encodes a
plain object through the **same** proto schema (real protobuf round-trip) and gzips it. Covers
container detection, gzip/raw parse, favorite presence, int64 fidelity, corrupt-gzip error staging,
status/tracker/category mapping, history folding, and legacy JSON.
