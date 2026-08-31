/**
 * Extension repositories MangaVault ships knowledge of.
 *
 * Seeded into `extension_repo` on boot rather than in a migration, so adding or
 * correcting one is a one-line edit here (same convention as `curated-apps.ts`).
 * Curated rows can be disabled by the user but not deleted; anything they add
 * themselves is stored with `curated = false`.
 *
 * Note that Mihon itself ships **no** default repository — the user pastes one.
 * We seed keiyoushi because it is the successor to the Tachiyomi extension repo
 * and is where essentially every source in a real `.tachibk` comes from; syncing
 * it is what turns a vault full of bare 64-bit ids into named sources.
 *
 * The url is the *base*, without the index filename: the sync appends
 * `/repo.json`, then `/index.json` or `/index.min.json`. (Mihon asks the user
 * for the full `…/index.min.json` url and strips the suffix; we store the
 * stripped form and accept either on input.)
 */
export interface CuratedRepo {
  baseUrl: string;
  name: string;
}

export const CURATED_REPOS: readonly CuratedRepo[] = [
  {
    baseUrl: 'https://raw.githubusercontent.com/keiyoushi/extensions/repo',
    name: 'Keiyoushi',
  },
];

/**
 * Normalize a repository url the way Mihon's `CreateExtensionRepo` does: accept
 * what the user is most likely to paste (a full index url, or a url with a
 * trailing slash) and reduce it to the base.
 */
export function normalizeRepoUrl(input: string): string | null {
  const raw = input.trim();
  if (!/^https:\/\//i.test(raw)) return null;
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  const path = url.pathname
    .replace(/\/(index\.min\.json|index\.json|index\.pb|repo\.json)$/i, '')
    .replace(/\/+$/, '');
  return `${url.origin}${path}`;
}
