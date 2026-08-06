/**
 * Pure `.tachibk` / legacy-JSON library. Zero Nest/TypeORM imports.
 *
 * Read:  file  -> detect container -> decode wire model -> normalize to domain.
 * Write: domain -> denormalize to wire model -> encode -> file.
 *
 * The two directions share the embedded proto schema, so they stay in lockstep.
 */
export { ContainerDetector } from './detect';
export { BackupParser } from './parse';
export { BackupNormalizer } from './normalize';
export { BackupDenormalizer } from './denormalize';
export {
  BackupEncoder,
  buildBackupFileName,
  DEFAULT_EXPORT_APP_ID,
} from './encode';
export { BackupParseError, BackupEncodeError } from './errors';
export type { ParseStage, EncodeStage } from './errors';
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
