import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class GeminiCitation {
  const GeminiCitation({
    required this.url,
    required this.title,
    required this.startIndex,
    required this.endIndex,
  });

  final String url;
  final String title;
  final int startIndex;
  final int endIndex;

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'start_index': startIndex,
    'end_index': endIndex,
  };
}

class GeminiResult {
  const GeminiResult({required this.text, this.citations = const []});

  final String text;
  final List<GeminiCitation> citations;
}

class GeminiService {
  GeminiService._({http.Client? client}) : _client = client ?? http.Client();

  static final GeminiService instance = GeminiService._();
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/interactions';

  final http.Client _client;

  String get _apiKey {
    try {
      return dotenv.env['GEMINI_API_KEY']?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  bool get isConfigured =>
      _apiKey.isNotEmpty && _apiKey != 'your_actual_api_key_here';

  Future<GeminiResult> generateText({
    required String prompt,
    required String systemInstruction,
    bool useGoogleSearch = false,
    bool preferReliableModel = false,
  }) async {
    if (!isConfigured) {
      throw StateError('GEMINI_API_KEY is not configured.');
    }

    final models = useGoogleSearch || preferReliableModel
        ? const ['gemini-3.6-flash', 'gemini-3.5-flash']
        : const ['gemini-3.5-flash-lite', 'gemini-3.6-flash'];
    late http.Response response;
    for (var index = 0; index < models.length; index++) {
      try {
        response = await _client
            .post(
              Uri.parse(_endpoint),
              headers: {
                'Content-Type': 'application/json',
                'x-goog-api-key': _apiKey,
              },
              body: jsonEncode({
                'model': models[index],
                'input': prompt,
                'system_instruction': systemInstruction,
                if (useGoogleSearch)
                  'tools': [
                    {'type': 'google_search'},
                  ],
              }),
            )
            .timeout(
              useGoogleSearch || preferReliableModel
                  ? const Duration(seconds: 35)
                  : const Duration(seconds: 18),
            );
      } catch (_) {
        if (index == models.length - 1) rethrow;
        continue;
      }
      final transient = const {429, 500, 503}.contains(response.statusCode);
      if (!transient || index == models.length - 1) break;
    }

    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded is Map<String, dynamic> ? decoded['error'] : null;
      final message = error is Map ? error['message']?.toString() : null;
      throw StateError(
        message ?? 'Gemini request failed (${response.statusCode}).',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected Gemini response.');
    }

    final blocks = _modelOutputBlocks(decoded);
    final text = blocks
        .map((block) => block['text']?.toString() ?? '')
        .where((value) => value.isNotEmpty)
        .join('\n')
        .trim();
    if (text.isEmpty) throw const FormatException('Gemini returned no text.');

    final citations = <GeminiCitation>[];
    for (final block in blocks) {
      final annotations = block['annotations'];
      if (annotations is! List) continue;
      for (final raw in annotations.whereType<Map>()) {
        final annotation = Map<String, dynamic>.from(raw);
        if (annotation['type'] != 'url_citation') continue;
        final url = annotation['url']?.toString() ?? '';
        if (url.isEmpty) continue;
        citations.add(
          GeminiCitation(
            url: url,
            title: annotation['title']?.toString() ?? Uri.parse(url).host,
            startIndex: annotation['start_index'] as int? ?? 0,
            endIndex: annotation['end_index'] as int? ?? 0,
          ),
        );
      }
    }
    return GeminiResult(text: text, citations: citations);
  }

  List<Map<String, dynamic>> _modelOutputBlocks(Map<String, dynamic> json) {
    final containers = [json['steps'], json['outputs']];
    final blocks = <Map<String, dynamic>>[];
    for (final container in containers) {
      if (container is! List) continue;
      for (final rawStep in container.whereType<Map>()) {
        final step = Map<String, dynamic>.from(rawStep);
        if (step['type'] != 'model_output') continue;
        final content = step['content'];
        if (content is List) {
          blocks.addAll(
            content.whereType<Map>().map(Map<String, dynamic>.from),
          );
        }
      }
    }
    return blocks;
  }
}
