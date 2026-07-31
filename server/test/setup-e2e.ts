/**
 * Runs before every e2e suite (wired via `setupFiles` in jest-e2e.json).
 *
 * The server archives covers on its own after an import and after a restart
 * that interrupted a run. Both scan the *whole* library and download every
 * missing cover from the real internet — which an e2e booting `AppModule`
 * against the local database would otherwise do for hundreds of real titles.
 *
 * Automatic runs are therefore off in e2e. The explicit
 * `POST /covers/archive-missing` is unaffected (no suite calls it), and the
 * covers suite drives the job machinery through `CoverJobStore` directly.
 */
process.env.COVER_AUTO_ARCHIVE = 'false';
