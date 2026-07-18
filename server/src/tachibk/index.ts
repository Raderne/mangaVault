/**
 * Pure `.tachibk` / legacy-JSON parsing library. Zero Nest/TypeORM imports —
 * file -> detect container -> decode wire model -> normalize to domain.
 */
export { ContainerDetector } from './detect';
export { BackupParser } from './parse';
export { BackupNormalizer } from './normalize';
export { BackupParseError } from './errors';
export type { ParseStage } from './errors';
export * from './domain';
export type {
  WireBackup,
  WireManga,
  WireChapter,
  WireHistory,
  WireTracking,
  WireCategory,
  WireSource,
} from './wire';
