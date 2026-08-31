import {
  AUTO_ACCEPT_SIMILARITY,
  MIN_ELIGIBLE_SIMILARITY,
  normalizeTitle,
  rankCandidates,
  scoreCandidate,
  titleSimilarity,
} from './title-match';

describe('normalizeTitle', () => {
  it('lowercases and drops bracketed asides', () => {
    expect(normalizeTitle('Solo Leveling (Official)')).toBe('solo leveling');
    expect(normalizeTitle('Omniscient Reader [Webtoon]')).toBe(
      'omniscient reader',
    );
  });

  it('strips punctuation and collapses separators', () => {
    expect(normalizeTitle('Re:Zero - Starting Life!')).toBe(
      're zero starting life',
    );
  });

  it('keeps a title that is entirely bracketed', () => {
    // Neither stripping direction survives this, so the empty-result guard
    // falls back to the unbracketed original rather than erasing the title.
    expect(normalizeTitle('(Oshi no Ko)')).toBe('oshi no ko');
  });

  it('keeps non-Latin titles instead of erasing them', () => {
    // The ASCII strip would leave an empty string; the Unicode fallback saves it.
    expect(normalizeTitle('葬送のフリーレン')).toBe('葬送のフリーレン');
    expect(normalizeTitle('나 혼자만 레벨업')).toBe('나 혼자만 레벨업');
  });

  it('removes Russian chapter references', () => {
    expect(normalizeTitle('Наруто - глава 12')).not.toMatch(/глава/);
  });
});

describe('titleSimilarity', () => {
  it('is 1 for titles that normalize to the same string', () => {
    expect(titleSimilarity('Solo Leveling', 'solo leveling (official)')).toBe(1);
  });

  it('rates a real-world rename above the auto-accept bar', () => {
    expect(
      titleSimilarity('Tower of God', 'Tower of God [Official]'),
    ).toBeGreaterThanOrEqual(AUTO_ACCEPT_SIMILARITY);
  });

  it('rates two different books below the eligibility bar', () => {
    expect(titleSimilarity('Solo Leveling', 'Berserk')).toBeLessThan(
      MIN_ELIGIBLE_SIMILARITY,
    );
  });

  it('is symmetric', () => {
    expect(titleSimilarity('One Piece', 'One Punch Man')).toBeCloseTo(
      titleSimilarity('One Punch Man', 'One Piece'),
      10,
    );
  });

  it('is 0 when either side normalizes to nothing', () => {
    expect(titleSimilarity('', 'One Piece')).toBe(0);
    expect(titleSimilarity('()', 'One Piece')).toBe(0);
  });
});

describe('scoreCandidate', () => {
  const from = { title: 'Solo Leveling', author: 'Chugong', chapterCount: 200 };

  it('rewards a matching author', () => {
    // Not an exact title match, or the clamp at 1 would hide the bonus.
    const title = 'Solo Leveling Side Story';
    const same = scoreCandidate(from, {
      sourceId: '2',
      url: '/a',
      title,
      author: 'Chugong',
    });
    const unknown = scoreCandidate(from, {
      sourceId: '2',
      url: '/a',
      title,
      author: null,
    });

    expect(same.score).toBeGreaterThan(unknown.score);
    expect(same.reasons).toContain('same author');
  });

  it('cannot push a score above 1', () => {
    const perfect = scoreCandidate(from, {
      sourceId: '2',
      url: '/a',
      title: 'Solo Leveling',
      author: 'Chugong',
      chapterCount: 200,
    });
    expect(perfect.similarity).toBe(1);
    expect(perfect.score).toBe(1);
  });

  it('penalises a clearly different author', () => {
    const scored = scoreCandidate(from, {
      sourceId: '2',
      url: '/a',
      title: 'Solo Leveling',
      author: 'Someone Else',
    });
    expect(scored.reasons).toContain('different author');
    expect(scored.score).toBeLessThan(scored.similarity + 0.001);
  });

  it('never lets corroboration promote a poor title match', () => {
    const scored = scoreCandidate(from, {
      sourceId: '2',
      url: '/a',
      title: 'Berserk',
      author: 'Chugong',
      chapterCount: 200,
    });
    expect(scored.score).toBeLessThan(MIN_ELIGIBLE_SIMILARITY);
  });

  it('keeps the score inside [0, 1]', () => {
    const scored = scoreCandidate(from, {
      sourceId: '2',
      url: '/a',
      title: 'Solo Leveling',
      author: 'Chugong',
      chapterCount: 200,
    });
    expect(scored.score).toBeLessThanOrEqual(1);
    expect(scored.score).toBeGreaterThanOrEqual(0);
  });
});

describe('rankCandidates', () => {
  const from = {
    sourceId: '111',
    url: '/dead/solo-leveling',
    title: 'Solo Leveling',
    author: 'Chugong',
    chapterCount: 200,
  };

  it('sorts best-first and drops ineligible candidates', () => {
    const ranked = rankCandidates(from, [
      { sourceId: '222', url: '/b', title: 'Berserk' },
      { sourceId: '222', url: '/c', title: 'Solo Leveling: Ragnarok' },
      { sourceId: '333', url: '/d', title: 'Solo Leveling' },
    ]);

    expect(ranked.map((c) => c.url)).toEqual(['/d', '/c']);
    expect(ranked[0].score).toBeGreaterThanOrEqual(ranked[1].score);
  });

  it('never offers the title its own row back', () => {
    const ranked = rankCandidates(from, [
      { sourceId: '111', url: '/dead/solo-leveling', title: 'Solo Leveling' },
    ]);
    expect(ranked).toEqual([]);
  });

  it('offers the same url on a different source', () => {
    const ranked = rankCandidates(from, [
      { sourceId: '999', url: '/dead/solo-leveling', title: 'Solo Leveling' },
    ]);
    expect(ranked).toHaveLength(1);
  });

  it('returns nothing when there is nothing plausible', () => {
    expect(
      rankCandidates(from, [{ sourceId: '2', url: '/x', title: 'Vagabond' }]),
    ).toEqual([]);
  });
});
