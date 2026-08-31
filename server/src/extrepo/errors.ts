export type RepoIndexStage = 'repo-meta' | 'index-format' | 'index-parse';

/**
 * Thrown when a repository index cannot be read at all. Anything that is merely
 * *odd* becomes a warning on {@link ParsedRepoIndex} instead — one malformed
 * entry must not cost the caller the whole index.
 */
export class RepoIndexError extends Error {
  constructor(
    readonly stage: RepoIndexStage,
    message: string,
    readonly cause?: unknown,
  ) {
    super(message);
    this.name = 'RepoIndexError';
  }
}
