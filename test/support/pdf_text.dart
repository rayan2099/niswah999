import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Minimal text extractor for the PDFs this app generates with the `pdf`
/// package (Type0/TTF fonts with a /ToUnicode map, Flate-compressed content
/// streams). It exists so acceptance tests can assert what a generated
/// report actually SAYS instead of only that it is non-empty. It is not a
/// general PDF parser.
///
/// Word spacing in these PDFs is produced by positioning, not by space
/// glyphs, so extracted text has no reliable spaces: compare with
/// [PdfText.squash] (all whitespace removed).
class PdfText {
  PdfText._(this.pages);

  /// Extracted text runs per page, in drawing order.
  final List<List<String>> pages;

  String get all => pages.expand((p) => p).join('\n');

  /// Whitespace-free text for `contains` comparisons.
  String get squashed => squash(all);

  static String squash(String s) => s.replaceAll(RegExp(r'\s+'), '');

  int get pageCount => pages.length;

  bool contains(String needle) => squashed.contains(squash(needle));

  static PdfText parse(Uint8List bytes) {
    final src = latin1.decode(bytes, allowInvalid: true);
    final objects = <int, _Obj>{};
    final objRe = RegExp(r'(\d+) 0 obj(.*?)endobj', dotAll: true);
    for (final m in objRe.allMatches(src)) {
      final id = int.parse(m.group(1)!);
      final body = m.group(2)!;
      final streamAt = body.indexOf('stream');
      if (streamAt == -1) {
        objects[id] = _Obj(body, null);
        continue;
      }
      final dict = body.substring(0, streamAt);
      var start = streamAt + 'stream'.length;
      if (body.startsWith('\r\n', start)) {
        start += 2;
      } else if (body.startsWith('\n', start)) {
        start += 1;
      }
      final end = body.lastIndexOf('endstream');
      var raw = latin1.encode(
        body.substring(start, end < start ? body.length : end),
      );
      if (dict.contains('FlateDecode')) {
        try {
          raw = Uint8List.fromList(zlib.decode(raw));
        } catch (_) {
          // Trailing newline before endstream: retry without it.
          raw = Uint8List.fromList(zlib.decode(raw.sublist(0, raw.length - 1)));
        }
      }
      objects[id] = _Obj(dict, raw);
    }

    // font resource name -> code map, per object id of the font.
    final cmapCache = <int, Map<int, String>>{};
    Map<int, String> cmapFor(int fontObjId) =>
        cmapCache.putIfAbsent(fontObjId, () {
          final font = objects[fontObjId];
          final ref = RegExp(r'/ToUnicode (\d+) 0 R')
              .firstMatch(font?.dict ?? '');
          if (ref == null) return const {};
          final cmapObj = objects[int.parse(ref.group(1)!)];
          return _parseCMap(latin1.decode(cmapObj?.stream ?? Uint8List(0)));
        });

    final pages = <List<String>>[];
    for (final entry in objects.entries) {
      final d = entry.value.dict;
      if (!RegExp(r'/Type\s*/Page(?![a-z])').hasMatch(d)) continue;
      final fonts = <String, int>{};
      final fontBlock = RegExp(
        r'/Font\s*<<(.*?)>>',
        dotAll: true,
      ).firstMatch(d);
      if (fontBlock != null) {
        for (final f in RegExp(
          r'/(\w+) (\d+) 0 R',
        ).allMatches(fontBlock.group(1)!)) {
          fonts[f.group(1)!] = int.parse(f.group(2)!);
        }
      }
      final contents = <int>[];
      final single = RegExp(r'/Contents (\d+) 0 R').firstMatch(d);
      if (single != null) {
        contents.add(int.parse(single.group(1)!));
      } else {
        final arr = RegExp(
          r'/Contents\s*\[(.*?)\]',
          dotAll: true,
        ).firstMatch(d);
        if (arr != null) {
          for (final r in RegExp(r'(\d+) 0 R').allMatches(arr.group(1)!)) {
            contents.add(int.parse(r.group(1)!));
          }
        }
      }
      final runs = <String>[];
      for (final id in contents) {
        final stream = objects[id]?.stream;
        if (stream == null) continue;
        runs.addAll(_extractRuns(latin1.decode(stream), fonts, cmapFor));
      }
      pages.add(runs);
    }
    return PdfText._(pages);
  }

  static Map<int, String> _parseCMap(String cmap) {
    final map = <int, String>{};
    String u(String hex) {
      final units = <int>[];
      for (var i = 0; i + 4 <= hex.length; i += 4) {
        units.add(int.parse(hex.substring(i, i + 4), radix: 16));
      }
      return String.fromCharCodes(units);
    }

    for (final block in RegExp(
      r'beginbfchar(.*?)endbfchar',
      dotAll: true,
    ).allMatches(cmap)) {
      for (final m in RegExp(
        r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>',
      ).allMatches(block.group(1)!)) {
        map[int.parse(m.group(1)!, radix: 16)] = u(m.group(2)!);
      }
    }
    for (final block in RegExp(
      r'beginbfrange(.*?)endbfrange',
      dotAll: true,
    ).allMatches(cmap)) {
      for (final m in RegExp(
        r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>',
      ).allMatches(block.group(1)!)) {
        final lo = int.parse(m.group(1)!, radix: 16);
        final hi = int.parse(m.group(2)!, radix: 16);
        final dst = int.parse(m.group(3)!, radix: 16);
        for (var c = lo; c <= hi; c++) {
          map[c] = String.fromCharCode(dst + (c - lo));
        }
      }
    }
    return map;
  }

  static List<String> _extractRuns(
    String content,
    Map<String, int> fonts,
    Map<int, String> Function(int) cmapFor,
  ) {
    final runs = <String>[];
    Map<int, String> current = const {};
    final tokenRe = RegExp(
      r'/(\w+)\s+[\d.]+\s+Tf|\[(.*?)\]\s*TJ|<([0-9A-Fa-f]*)>\s*Tj|\((.*?)(?<!\\)\)\s*Tj',
      dotAll: true,
    );
    String decodeHex(String hex) {
      final b = StringBuffer();
      for (var i = 0; i + 4 <= hex.length; i += 4) {
        final code = int.parse(hex.substring(i, i + 4), radix: 16);
        b.write(current[code] ?? '');
      }
      return b.toString();
    }

    for (final m in tokenRe.allMatches(content)) {
      if (m.group(1) != null) {
        final id = fonts[m.group(1)!];
        current = id == null ? const {} : cmapFor(id);
      } else if (m.group(2) != null) {
        final b = StringBuffer();
        for (final h in RegExp(r'<([0-9A-Fa-f]*)>').allMatches(m.group(2)!)) {
          b.write(decodeHex(h.group(1)!));
        }
        runs.add(b.toString());
      } else if (m.group(3) != null) {
        runs.add(decodeHex(m.group(3)!));
      } else if (m.group(4) != null) {
        runs.add(m.group(4)!);
      }
    }
    return runs.where((r) => r.isNotEmpty).toList();
  }
}

class _Obj {
  _Obj(this.dict, this.stream);
  final String dict;
  final Uint8List? stream;
}
