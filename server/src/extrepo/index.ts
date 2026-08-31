/**
 * Pure extension-repository index library. Zero Nest/TypeORM imports, the same
 * rule `src/tachibk/` follows — fetching, storage and scheduling all live in
 * `modules/sources/`, so this half stays portable and unit-testable against
 * fixtures.
 *
 * Read: repo.json -> repo meta -> index url -> decode -> normalized index.
 */
export {
  parseRepoMeta,
  parseRepoIndex,
  parseIndexV2,
  parseIndexLegacy,
  detectIndexFormat,
  resolveIndexUrls,
  isPlaceholderIndex,
} from './parse';
export { generateSourceId } from './generate-id';
export { RepoIndexError } from './errors';
export type { RepoIndexStage } from './errors';
export * from './domain';
