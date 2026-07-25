import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/core/sse/sse_parser.dart';

void main() {
  Future<List<String>> collect(List<String> chunks) =>
      parseSseData(Stream.fromIterable(chunks)).toList();

  test('parses complete events split on blank lines', () async {
    final out = await collect(['data: {"a":1}\n\n', 'data: {"b":2}\n\n']);
    expect(out, ['{"a":1}', '{"b":2}']);
  });

  test('reassembles an event split across chunk boundaries', () async {
    final out = await collect(['data: {"hel', 'lo":"world"}\n', '\ndata: {"x":1}\n\n']);
    expect(out, ['{"hello":"world"}', '{"x":1}']);
  });

  test('handles CRLF line endings', () async {
    final out = await collect(['data: {"a":1}\r\n\r\n']);
    expect(out, ['{"a":1}']);
  });

  test('flushes a final event with no trailing blank line', () async {
    final out = await collect(['data: {"last":true}']);
    expect(out, ['{"last":true}']);
  });

  test('ignores non-data lines (comments, ids)', () async {
    final out = await collect([': keep-alive\n\nid: 7\ndata: {"ok":1}\n\n']);
    expect(out, ['{"ok":1}']);
  });
}
