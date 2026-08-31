/**
 * Title matching for source migration.
 *
 * Ported from Mihon's `BaseSmartSearchEngine` / `SmartSourceSearchEngine`,
 * which is what its Migrate feature uses to decide that "Solo Leveling" on a
 * dead source is the same book as "Solo Leveling [Official]" on a live one.
 * The port matters: this is the difference between a migration the user can
 * accept in bulk and one they must confirm 300 times by hand.
 *
 * Pure and dependency-free — no Nest, no database, no network — so the whole
 * scoring surface is unit-testable, which is the only way to be confident about
 * a threshold that decides what gets rewritten in the vault.
 */

/**
 * Mihon's `MIN_ELIGIBLE_THRESHOLD`. Below this a candidate is not offered at
 * all; the user is asked to search or paste a url instead.
 */
export const MIN_ELIGIBLE_SIMILARITY = 0.4;

/**
 * At or above this a match is safe to pre-select for a bulk migration. Higher
 * than Mihon's bar on purpose: Mihon is picking a *reading* source and a wrong
 * guess costs a tap, whereas here a wrong guess rewrites an archived title's
 * identity. Everything between the two thresholds is offered but left for the
 * user to confirm.
 */
export const AUTO_ACCEPT_SIMILARITY = 0.85;

/** Strip bracketed asides, e.g. "Solo Leveling (Official)" -> "Solo Leveling". */
function removeTextInBrackets(text: string, readForward: boolean): string {
  const openers = readForward ? ['(', '[', '<', '{'] : [')', ']', '>', '}'];
  const closers = readForward ? [')', ']', '>', '}'] : ['(', '[', '<', '{'];
  const chars = readForward ? [...text] : [...text].reverse();

  let depth = 0;
  const kept: string[] = [];
  for (const ch of chars) {
    if (openers.includes(ch)) depth++;
    else if (closers.includes(ch)) depth = Math.max(0, depth - 1);
    else if (depth === 0) kept.push(ch);
  }
  return (readForward ? kept : kept.reverse()).join('');
}

/** `- часть 3` / `- глава 12` — Mihon strips these Russian chapter refs. */
const CHAPTER_REF = /((-\s*часть|-\s*глава)\s*\d*)/gi;
const NON_ALNUM_ASCII = /[^a-zA-Z0-9\- ]/g;
const NON_ALNUM_UNICODE = /[^\p{L}0-9\- ]/gu;
const CONSECUTIVE_SPACES = / +/g;

/**
 * Normalize a title for comparison, following Mihon's cleaner step for step —
 * including its two fallbacks, which exist because the naive version destroys
 * non-Latin titles:
 *
 *   * if stripping brackets forward leaves almost nothing, strip from the other
 *     end instead (a title that *is* a bracketed phrase);
 *   * if stripping non-ASCII leaves almost nothing, keep any Unicode letter (a
 *     title with no Latin characters at all).
 */
export function normalizeTitle(title: string): string {
  const lower = title.toLowerCase();

  let cleaned = removeTextInBrackets(lower, true);
  if (cleaned.length <= 5) cleaned = removeTextInBrackets(lower, false);

  cleaned = cleaned.replace(CHAPTER_REF, '');

  let stripped = cleaned.replace(NON_ALNUM_ASCII, ' ');
  if (stripped.trim().length <= 5) {
    stripped = cleaned.replace(NON_ALNUM_UNICODE, ' ');
  }

  // One guard Mihon does not have. A title that is *entirely* bracketed —
  // "(Oshi no Ko)" — survives neither stripping direction, and Mihon reduces it
  // to the empty string, which scores 0 against everything and so can never be
  // migrated. Falling back to the unbracketed original is strictly better: the
  // brackets were the whole title, so they were never an aside to remove.
  if (stripped.trim().length === 0) {
    stripped = lower.replace(NON_ALNUM_UNICODE, ' ');
  }

  return stripped
    .split(' - ')
    .join(' ')
    .replace(CONSECUTIVE_SPACES, ' ')
    .trim();
}

/** Levenshtein distance, iterative with a single row of state. */
function levenshtein(a: string, b: string): number {
  if (a === b) return 0;
  if (a.length === 0) return b.length;
  if (b.length === 0) return a.length;

  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  let curr = new Array<number>(b.length + 1);

  for (let i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      curr[j] = Math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
    }
    [prev, curr] = [curr, prev];
  }
  return prev[b.length];
}

/**
 * Normalized Levenshtein similarity in [0, 1], on cleaned titles.
 *
 * 1 is identical after normalization; 0 shares nothing. This is Mihon's
 * `NormalizedLevenshtein.similarity`, which is what makes the thresholds above
 * mean the same thing they do there.
 */
export function titleSimilarity(a: string, b: string): number {
  const left = normalizeTitle(a);
  const right = normalizeTitle(b);
  if (left.length === 0 || right.length === 0) return 0;
  if (left === right) return 1;
  const longest = Math.max(left.length, right.length);
  return 1 - levenshtein(left, right) / longest;
}

/** A thing we might migrate a title to, before it has been scored. */
export interface MatchCandidate {
  sourceId: string;
  url: string;
  title: string;
  /**
   * Other names the same work is published under.
   *
   * Not a nicety — without it the matcher misses obvious hits. MangaDex, for
   * one, frequently returns a romanized original as the primary title ("The
   * Greatest Estate Developer" comes back as "Yeokdaegeum Yeongji Seolgyesa")
   * and keeps the name the user's backup actually uses in its alternates.
   * Scoring against the primary title alone would report the book as missing.
   */
  altTitles?: string[];
  author?: string | null;
  thumbnailUrl?: string | null;
  chapterCount?: number | null;
}

export interface ScoredCandidate extends MatchCandidate {
  /** Title similarity in [0, 1]. */
  similarity: number;
  /** Similarity plus corroboration; what the ranking and thresholds use. */
  score: number;
  /** Why the score differs from raw similarity — shown in the review list. */
  reasons: string[];
}

export interface ScoreInput {
  title: string;
  author?: string | null;
  chapterCount?: number | null;
}

/**
 * Score a candidate against the vault title being migrated.
 *
 * Similarity carries the decision; the corroborating signals only nudge it, and
 * only ever by enough to break a tie between near-identical titles — never
 * enough to promote a poor title match. A same-author bonus is the strongest of
 * them because a shared author across two sources is rarely a coincidence.
 */
export function scoreCandidate(
  from: ScoreInput,
  candidate: MatchCandidate,
): ScoredCandidate {
  const reasons: string[] = [];

  // Best of the primary title and every alternate. A work published under a
  // romanized original and an English name is one work, and which of them a
  // source calls "the" title is arbitrary.
  const primary = titleSimilarity(from.title, candidate.title);
  let similarity = primary;
  for (const alt of candidate.altTitles ?? []) {
    const score = titleSimilarity(from.title, alt);
    if (score > similarity) similarity = score;
  }
  if (similarity > primary + 0.05) {
    reasons.push('matched an alternative title');
  }

  let score = similarity;

  const fromAuthor = (from.author ?? '').trim().toLowerCase();
  const toAuthor = (candidate.author ?? '').trim().toLowerCase();
  if (fromAuthor && toAuthor) {
    if (fromAuthor === toAuthor) {
      score += 0.05;
      reasons.push('same author');
    } else if (titleSimilarity(fromAuthor, toAuthor) < 0.5) {
      score -= 0.05;
      reasons.push('different author');
    }
  }

  const fromChapters = from.chapterCount ?? 0;
  const toChapters = candidate.chapterCount ?? 0;
  if (fromChapters > 0 && toChapters > 0) {
    const ratio =
      Math.min(fromChapters, toChapters) / Math.max(fromChapters, toChapters);
    if (ratio >= 0.9) {
      score += 0.03;
      reasons.push('similar chapter count');
    } else if (ratio < 0.5) {
      score -= 0.03;
      reasons.push(`${toChapters} chapters vs ${fromChapters}`);
    }
  }

  return {
    ...candidate,
    similarity,
    score: Math.max(0, Math.min(1, score)),
    reasons,
  };
}

/**
 * Rank candidates best-first, dropping anything under the eligibility bar.
 *
 * A candidate on the same source as the title being migrated is never offered —
 * migrating a title onto itself is the one outcome that is certainly wrong.
 * Mihon applies the same guard.
 */
export function rankCandidates(
  from: ScoreInput & { sourceId: string; url: string },
  candidates: readonly MatchCandidate[],
): ScoredCandidate[] {
  return candidates
    .filter((c) => !(c.sourceId === from.sourceId && c.url === from.url))
    .map((c) => scoreCandidate(from, c))
    .filter((c) => c.score >= MIN_ELIGIBLE_SIMILARITY)
    .sort((a, b) => b.score - a.score);
}
