import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/import/import_models.dart';
import '../../theme/app_accents.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/entrance_fade.dart';
import '../../widgets/status_chip.dart';

/// Opacity by depth, newest first. The trailing `0` is an **exit slot**: it sits
/// below the well and is never seen, but it gives the oldest row somewhere to
/// fade *to* instead of being cut from the tree mid-opacity.
const _depthOpacity = <double>[1.0, 0.55, 0.30, 0.12, 0.0];

/// How many depths are actually on screen (the rest of [_depthOpacity] is exit).
const _visibleSlots = 4;

/// Floor on the gap between two rows entering.
///
/// The server streams one event per title — a 1,200-title backup lands ~40 a
/// second, which is faster than any transition and reads as a strobe. The
/// ticker is ambient feedback, not a log, so it samples the stream and drops
/// whatever arrives between beats. Throttling lives here rather than in the
/// controller: it is a legibility concern, not a state one.
const _admitInterval = Duration(milliseconds: 140);

/// Rows glide down slowly enough to be followed…
const _slideDuration = Duration(milliseconds: 320);

/// …but dim faster, so a row leaving the last visible depth is effectively gone
/// by the time the next beat drops it from the tree.
const _fadeDuration = Duration(milliseconds: 200);

/// The live "now importing" well: a fixed-height stack of the titles being
/// written, newest on top, each older one stepping down and dimming until it
/// vanishes. Deliberately **not** a scrolling list — the card must not grow as
/// an import runs, and 1,200 rows of history no one reads is not worth the
/// layout cost.
class ImportTicker extends StatefulWidget {
  const ImportTicker({super.key, required this.recent});

  /// Newest first, as the controller keeps it. Only the head is ever read.
  final List<MangaEvent> recent;

  @override
  State<ImportTicker> createState() => _ImportTickerState();
}

class _ImportTickerState extends State<ImportTicker> {
  /// Newest first; never longer than [_depthOpacity].
  final List<_TickerRow> _rows = [];

  /// Monotonic row identity. Titles repeat across backups and `MangaEvent`
  /// has no id, so nothing in the event itself is safe to key on — and a
  /// duplicate key would make two rows share one slot.
  int _seq = 0;

  MangaEvent? _lastAdmitted;
  MangaEvent? _pending;
  Timer? _beat;

  @override
  void initState() {
    super.initState();
    // Seed without setState: this runs before the first build.
    final head = widget.recent.isEmpty ? null : widget.recent.first;
    if (head != null) _admit(head);
  }

  @override
  void didUpdateWidget(ImportTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final head = widget.recent.isEmpty ? null : widget.recent.first;
    // Identity, not equality: every event is a fresh instance off the stream,
    // so a new head means new work even when the title text repeats.
    if (head == null || identical(head, _lastAdmitted)) return;
    _pending = head;
    _drain();
  }

  void _drain() {
    if (_beat != null) return; // a beat is in flight; it will pick this up
    final next = _pending;
    if (next == null) return;
    _pending = null;
    setState(() => _admit(next));
  }

  /// Takes a row and opens the cooldown. Every admission arms the beat,
  /// including the seed one — otherwise the second title of an import would
  /// slip in on the same frame as the first.
  void _admit(MangaEvent event) {
    _lastAdmitted = event;
    _rows.insert(0, _TickerRow(_seq++, event));
    if (_rows.length > _depthOpacity.length) {
      _rows.removeRange(_depthOpacity.length, _rows.length);
    }
    _beat = Timer(_admitInterval, () {
      _beat = null;
      if (mounted) _drain();
    });
  }

  @override
  void dispose() {
    _beat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = _TickerMetrics.of(context);
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final slide = still ? Duration.zero : _slideDuration;
    final fade = still ? Duration.zero : _fadeDuration;

    return ExcludeSemantics(
      // A screen reader announcing 1,200 titles in a row is noise, not
      // information: the phase label and the "n / total" counter beside this
      // well already carry the progress.
      child: SizedBox(
        height: metrics.wellHeight,
        child: ClipRect(
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: metrics.row,
                child: AnimatedOpacity(
                  duration: fade,
                  opacity: _rows.isEmpty ? 1 : 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Waiting for the first title…',
                      style: theme.textTheme.bodyMedium!
                          .copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
              // Reverse order so the newest row paints on top of the one it is
              // still sliding past.
              for (var depth = _rows.length - 1; depth >= 0; depth--)
                AnimatedPositioned(
                  key: ValueKey(_rows[depth].id),
                  duration: slide,
                  curve: kEntranceCurve,
                  left: 0,
                  right: 0,
                  top: depth * metrics.slot,
                  height: metrics.row,
                  child: AnimatedOpacity(
                    duration: fade,
                    curve: Curves.easeOut,
                    opacity: _depthOpacity[depth],
                    // The row keeps this State as it steps down, so the
                    // entrance plays once, on arrival — not at every depth.
                    child: EntranceFade(
                      duration: _fadeDuration,
                      beginOffset: const Offset(0, -0.35),
                      child: _TickerRowView(event: _rows[depth].event),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One title in the well: the name, and the badge for what was done with it.
class _TickerRowView extends StatelessWidget {
  const _TickerRowView({required this.event});
  final MangaEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            event.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: AppDimens.unit),
        StatusChip(
          importActionLabel(event.action),
          accent: importActionAccent(event.action),
        ),
      ],
    );
  }
}

class _TickerRow {
  const _TickerRow(this.id, this.event);
  final int id;
  final MangaEvent event;
}

/// Row and well geometry, derived from the text scale rather than hardcoded.
///
/// The well is absolutely positioned, so every height here is load-bearing: at
/// an enlarged system font a fixed constant squashes the badges — the same trap
/// the dashboard shelves hit. The theme sets an explicit `height` on both text
/// styles, so a line box is exactly `scaledFontSize * height`.
class _TickerMetrics {
  const _TickerMetrics({
    required this.row,
    required this.slot,
    required this.wellHeight,
  });

  /// Height of one title row.
  final double row;

  /// Distance between two rows' tops (row + gap).
  final double slot;

  /// Fixed height of the whole well — what keeps the card from growing.
  final double wellHeight;

  factory _TickerMetrics.of(BuildContext context) {
    const gap = AppDimens.unit;
    final scaler = MediaQuery.textScalerOf(context);
    final titleLine = (scaler.scale(14) * (20 / 14)).ceilToDouble();
    // StatusChip: labelSmall line box + 6pt padding a side + 1pt hairline a side.
    final chip = (scaler.scale(12) * (16 / 12)).ceilToDouble() + 14;
    final row = math.max(titleLine, chip);
    return _TickerMetrics(
      row: row,
      slot: row + gap,
      wellHeight: row * _visibleSlots + gap * (_visibleSlots - 1),
    );
  }
}

/// Badge text for a per-title import outcome.
String importActionLabel(String action) => switch (action) {
      'merged' => 'MERGED',
      'skipped' => 'SKIPPED',
      _ => 'NEW',
    };

/// Hue for a per-title import outcome, matching the review chips above the
/// list so a badge and the count that filters to it read as the same thing.
VaultAccent importActionAccent(String action) => switch (action) {
      'merged' => VaultAccent.cyan,
      'skipped' => VaultAccent.amber,
      _ => VaultAccent.emerald,
    };
