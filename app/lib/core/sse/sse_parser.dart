/// Minimal Server-Sent Events parser.
///
/// Takes a stream of already-UTF-8-decoded text chunks (as produced by
/// `byteStream.transform(utf8.decoder)`) and yields the `data:` payload of each
/// complete event. Events are separated by a blank line; only the `data` field
/// is surfaced (MangaVault's import stream sends one JSON object per event).
///
/// Pure and transport-agnostic so it is unit-testable with arbitrary chunk
/// boundaries (network reads split events anywhere).
Stream<String> parseSseData(Stream<String> chunks) async* {
  final buffer = StringBuffer();

  Iterable<String> drain(String content, {required bool flushTail}) sync* {
    // Normalize CRLF so event boundaries are always '\n\n'.
    var remaining = content.replaceAll('\r\n', '\n');
    int sep;
    while ((sep = remaining.indexOf('\n\n')) != -1) {
      final rawEvent = remaining.substring(0, sep);
      remaining = remaining.substring(sep + 2);
      final data = _extractData(rawEvent);
      if (data != null) yield data;
    }
    buffer
      ..clear()
      ..write(remaining);
    if (flushTail) {
      final data = _extractData(remaining);
      if (data != null) yield data;
    }
  }

  await for (final chunk in chunks) {
    buffer.write(chunk);
    yield* Stream.fromIterable(drain(buffer.toString(), flushTail: false));
  }
  // Flush a final event that wasn't terminated by a trailing blank line.
  yield* Stream.fromIterable(drain(buffer.toString(), flushTail: true));
}

/// Join the `data:` line(s) of one event block, or null if it carries no data.
String? _extractData(String rawEvent) {
  final dataLines = <String>[];
  for (final line in rawEvent.split('\n')) {
    if (line.startsWith('data:')) {
      dataLines.add(line.substring(5).trimLeft());
    }
  }
  if (dataLines.isEmpty) return null;
  final joined = dataLines.join('\n').trim();
  return joined.isEmpty ? null : joined;
}
