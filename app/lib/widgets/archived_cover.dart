import 'package:flutter/material.dart';

import '../data/covers/cover_repository.dart';
import 'entrance_fade.dart';

/// Renders a title's archived cover with the bearer header attached (the serve
/// route is guarded and `Image.network` doesn't use Dio), gently fading the
/// image in as it decodes. Falls back to [placeholder] while unarchived or on
/// error, so the grid/detail layout is identical with or without a cover.
class ArchivedCover extends StatelessWidget {
  const ArchivedCover({
    super.key,
    required this.coverState,
    required this.mangaId,
    required this.placeholder,
    this.fit = BoxFit.cover,
  });

  final String coverState;
  final String mangaId;
  final Widget placeholder;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final url = CoverRepository.coverUrl(coverState, mangaId);
    if (url == null) return placeholder;
    return Image.network(
      url,
      headers: CoverRepository.authHeaders,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => placeholder,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          curve: kEntranceCurve,
          child: child,
        );
      },
    );
  }
}
