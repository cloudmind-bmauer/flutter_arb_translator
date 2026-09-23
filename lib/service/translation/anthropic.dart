import 'dart:convert';

import 'base.dart';
import '../http/http_client.dart';
import '../log/logger.dart';

import '../../models/translation.dart';
import '../../models/types.dart';
import '../../models/api_result.dart';

/// Translator that uses the Anthropic Messages API for translation
/// Anthropic API Documentation:
/// https://docs.anthropic.com/en/api/messages
class AnthropicTranslationService extends AbstractTranslationService
    with
        SupportsSimpleTranslationToTargetsList,
        SupportsBulkTranslationToSingleTarget {
  static const String _defaultModel = 'claude-sonnet-5';
  static const String _apiVersion = '2023-06-01';

  final HttpClient _httpClient;
  final Logger logger;
  final String model;

  AnthropicTranslationService({
    required String baseUrl,
    required String apiKey,
    required this.logger,
    String? model,
  })  : model = (model == null || model.isEmpty) ? _defaultModel : model,
        _httpClient = HttpClient(
          baseUrl: baseUrl,
          authorizationHeaders: {
            'x-api-key': apiKey,
            'anthropic-version': _apiVersion,
          },
          logger: logger,
        );

  /// Translates given text to specified language
  /// [source] - text which should be translated
  /// [sourceLanguage] - the language in which [source] was given
  /// [target] - language to which [source] should be translated
  @override
  Future<String> translate(
    String source,
    LanguageCode sourceLanguage,
    LanguageCode target,
  ) async {
    logger.info('Translate "$source" from $sourceLanguage to $target');

    final prompt =
        'Translate the following text from $sourceLanguage to $target: $source';

    final apiResult = await _queryMessages(prompt);

    if (!apiResult.succeeded) {
      logger.warning('Translation failed');
      return source;
    }

    if (apiResult.valueUnsafe.content.isEmpty) {
      logger.warning('Content list is empty for prompt: $prompt');
      return source;
    }

    final translatedText = apiResult.valueUnsafe.content.first.text;

    return translatedText.trim();
  }

  /// Translates given text to specified languages
  /// [source] - text which should be translated
  /// [sourceLanguage] - the language in which [source] was given
  /// [targets] - list of languages to which [source] should be translated
  @override
  Future<Translation> translateToTargetsList(
    String source,
    LanguageCode sourceLanguage,
    List<LanguageCode> targets,
  ) async {
    logger
        .info('Translate "$source" from $sourceLanguage to multiple $targets');

    final prompt = '''
Translate the following text from $sourceLanguage to these languages: ${targets.join(', ')}.
Return only the translations, in the same order as the languages listed, separated by '\n******\n'.
Do not include the language names, colons, or any extra text—just the translations.
Text: $source
''';

    final apiResult = await _queryMessages(prompt);

    if (!apiResult.succeeded) {
      logger.warning('Translation failed');
      return Translation(
        source: source,
        sourceLanguage: sourceLanguage,
        translations: {for (final x in targets) x: source},
      );
    }

    if (apiResult.valueUnsafe.content.isEmpty) {
      logger.warning('Content list is empty for prompt: $prompt');
      return Translation(
        source: source,
        sourceLanguage: sourceLanguage,
        translations: {for (final x in targets) x: source},
      );
    }

    final translatedText = apiResult.valueUnsafe.content.first.text;

    final lines = _splitResponseIntoLines(translatedText);
    if (lines.length != targets.length) {
      logger.warning(
          'Expected ${targets.length} translations, got ${lines.length}');
    }

    Map<LanguageCode, String> translations = {};
    for (int i = 0; i < targets.length; i++) {
      translations[targets[i]] = i < lines.length ? lines[i] : source;
    }

    return Translation(
      source: source,
      sourceLanguage: sourceLanguage,
      translations: translations,
    );
  }

  /// Translates given texts to specified language
  /// [sources] - list of text which should be translated
  /// [sourceLanguage] - the language in which [sources] were given
  /// [target] - language to which [sources] should be translated
  @override
  Future<List<String>> translateBulkToSingleTarget(
    List<String> sources,
    LanguageCode sourceLanguage,
    LanguageCode target,
  ) async {
    logger.info(
        'Translate bulk "$sources" from $sourceLanguage to single $target');

    final prompt = '''
Translate the following texts from $sourceLanguage to $target.
Each string to be translated is separated by '\n******\n'.
Return only the translations, in the same order as the texts listed, with every returned translation separated by '\n******\n'.
Do not include the original texts, language names, colons, or any extra text—just the translations.
Texts:
${sources.join('\n******\n')}
''';

    final apiResult = await _queryMessages(prompt, 10000);

    if (!apiResult.succeeded) {
      logger.warning('Translation failed');
      return sources;
    }

    if (apiResult.valueUnsafe.content.isEmpty) {
      logger.warning('Content list is empty for prompt: $prompt');
      return sources;
    }

    final translatedText = apiResult.valueUnsafe.content.first.text;

    final lines = _splitResponseIntoLines(translatedText);
    if (lines.length != sources.length) {
      logger.warning(
          'Expected ${sources.length} translations, got ${lines.length}');
    }

    return List.generate(
      sources.length,
      (i) => i < lines.length ? lines[i] : sources[i],
    );
  }

  static List<String> _splitResponseIntoLines(String text) => text
      .trim()
      .split('******')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<ApiResult<_AnthropicMessagesResponse>> _queryMessages(
    String prompt, [
    int maxTokens = 1000,
  ]) =>
      _httpClient.post<_AnthropicMessagesResponse>(
        path: 'v1/messages',
        headers: {
          'Content-Type': 'application/json',
        },
        body: {
          'model': model,
          'max_tokens': maxTokens,
          'messages': [
            {
              'role': 'user',
              'content': prompt,
            },
          ],
        },
        decoder: (response) => _AnthropicMessagesResponse.fromJson(
            jsonDecode(utf8.decode(response.bodyBytes))),
      );
}

class _AnthropicMessagesResponse {
  final List<_AnthropicContentBlock> content;

  _AnthropicMessagesResponse({required this.content});

  factory _AnthropicMessagesResponse.fromJson(Map<String, dynamic> json) {
    return _AnthropicMessagesResponse(
      content: (json['content'] as List<dynamic>)
          .map((e) => _AnthropicContentBlock.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class _AnthropicContentBlock {
  final String text;

  _AnthropicContentBlock({required this.text});

  factory _AnthropicContentBlock.fromJson(Map<String, dynamic> json) {
    return _AnthropicContentBlock(
      text: json['text'] as String? ?? '',
    );
  }
}
