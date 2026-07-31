import { Logger } from '@nestjs/common';
import sharp from 'sharp';

/**
 * How covers are stored. Measured on a 2,000-title vault: 1,121 archived covers
 * took **613 MB** — JPEG averaging 661 KB and PNG averaging 1.8 MB, with a
 * 14 MB outlier — while the third already in WebP averaged 140 KB for visually
 * identical results. A phone renders these at ~600 px in the grid and ~1,100 px
 * on the details hero, so anything beyond ~1,600 px is bytes nobody ever sees.
 */
export interface CoverOptimizerOptions {
  /** Longest side kept, in pixels. Larger images are scaled down, never up. */
  maxEdge: number;
  /** WebP quality (0–100). */
  quality: number;
  /**
   * Only replace the original when the result is at most this fraction of it.
   * Stops a well-compressed 78 KB WebP being "optimised" into an 80 KB one, and
   * guarantees the operation can never make the archive bigger.
   */
  maxSizeRatio: number;
  /**
   * libwebp effort (0–6). 4 is the sweet spot: near-6 compression at a fraction
   * of the CPU, which matters when the ingest path calls this per cover.
   */
  effort: number;
}

export const DEFAULT_COVER_OPTIMIZER: CoverOptimizerOptions = {
  maxEdge: 1600,
  quality: 80,
  maxSizeRatio: 0.9,
  effort: 4,
};

/** Why a cover was left exactly as it arrived. */
export type SkipReason =
  'already-optimal' | 'no-saving' | 'undecodable' | 'encode-failed';

export interface OptimizeResult {
  /** Bytes to store: the re-encoded image, or the input when `changed` is false. */
  bytes: Buffer;
  /** Extension to store them under (`webp` only when `changed`). */
  ext: string;
  changed: boolean;
  skipReason?: SkipReason;
  /** Source dimensions/format, when the image could be read at all. */
  original?: { width: number; height: number; format: string; bytes: number };
  /** Result dimensions, when re-encoded. */
  optimized?: { width: number; height: number; bytes: number };
}

/**
 * Re-encodes archived covers to WebP within a size bound.
 *
 * **Lossy and irreversible**, so it is deliberately conservative: an image it
 * cannot decode, or cannot make meaningfully smaller, is returned untouched
 * rather than replaced. Callers store `result.bytes` under `result.ext` and can
 * treat `changed === false` as "keep what you had".
 *
 * Used from two places, which is why the profile lives here rather than in
 * either of them: the ingest path (so new covers never arrive oversized) and
 * the `covers:optimize` maintenance script (which fixes the existing archive).
 */
export class CoverOptimizer {
  private readonly logger = new Logger(CoverOptimizer.name);
  readonly options: CoverOptimizerOptions;

  constructor(options: Partial<CoverOptimizerOptions> = {}) {
    this.options = { ...DEFAULT_COVER_OPTIMIZER, ...options };
  }

  /** Dimensions and format of an image, or null when it can't be read. */
  async inspect(
    input: Buffer,
  ): Promise<{ width: number; height: number; format: string } | null> {
    try {
      const meta = await sharp(input, { animated: true }).metadata();
      // `pages` counts animation frames, so a 3-frame GIF reports 3× the height.
      const height =
        meta.pages && meta.pages > 1 && meta.pageHeight
          ? meta.pageHeight
          : (meta.height ?? 0);
      if (!meta.width || !height) return null;
      return { width: meta.width, height, format: meta.format ?? 'unknown' };
    } catch {
      return null;
    }
  }

  async optimize(input: Buffer): Promise<OptimizeResult> {
    const meta = await this.inspect(input);
    if (!meta) {
      // Never destroy something we don't understand.
      return {
        bytes: input,
        ext: '',
        changed: false,
        skipReason: 'undecodable',
      };
    }

    const original = { ...meta, bytes: input.length };
    const longest = Math.max(meta.width, meta.height);
    const withinBounds = longest <= this.options.maxEdge;

    // Already a small WebP inside the size bound: re-encoding would only lose
    // another generation of quality for nothing.
    if (meta.format === 'webp' && withinBounds) {
      return {
        bytes: input,
        ext: 'webp',
        changed: false,
        skipReason: 'already-optimal',
        original,
      };
    }

    let output: Buffer;
    try {
      // `animated` keeps every frame of an animated GIF/WebP; without it sharp
      // silently writes only the first, which would be quiet data loss.
      const pipeline = sharp(input, { animated: true });
      if (!withinBounds) {
        pipeline.resize({
          width: meta.width >= meta.height ? this.options.maxEdge : undefined,
          height: meta.height > meta.width ? this.options.maxEdge : undefined,
          fit: 'inside',
          withoutEnlargement: true,
        });
      }
      output = await pipeline
        .webp({ quality: this.options.quality, effort: this.options.effort })
        .toBuffer();
    } catch (err) {
      this.logger.debug(
        `cover re-encode failed (${meta.format} ${meta.width}x${meta.height}): ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
      return {
        bytes: input,
        ext: '',
        changed: false,
        skipReason: 'encode-failed',
        original,
      };
    }

    if (output.length > input.length * this.options.maxSizeRatio) {
      return {
        bytes: input,
        ext: '',
        changed: false,
        skipReason: 'no-saving',
        original,
      };
    }

    const after = await this.inspect(output);
    return {
      bytes: output,
      ext: 'webp',
      changed: true,
      original,
      optimized: {
        width: after?.width ?? 0,
        height: after?.height ?? 0,
        bytes: output.length,
      },
    };
  }
}
