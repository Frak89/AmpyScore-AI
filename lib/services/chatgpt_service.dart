import 'dart:convert';
import 'dart:io';
import '../audio/wav_engine.dart';

/// Explicitly opt-in online helper. Sends ONLY text pitches, never audio.
/// This is not instrument identification and is unrelated to local DSP.
class ChatGptService {
  static Future<String> explain({
    required List<DetectedNote> notes,
    required String apiKey,
  }) async {
    if (notes.isEmpty) {
      throw StateError('Analizza prima un file audio.');
    }
    if (apiKey.trim().isEmpty) {
      throw StateError('Inserisci la tua chiave API OpenAI.');
    }

    final melody = notes.take(48).map((n) {
      return n.label +
          ' (' +
          n.durationSeconds.toStringAsFixed(2) +
          ' s)';
    }).join(', ');

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(
        Uri.parse('https://api.openai.com/v1/responses'),
      );
      request.headers.set(HttpHeaders.authorizationHeader,
          'Bearer ' + apiKey.trim());
      request.headers.contentType = ContentType.json;
      final payload = <String, Object>{
        'model': 'gpt-4.1-mini',
        'instructions':
            'Sei un assistente didattico di teoria musicale. Rispondi '
            'in italiano, in modo conciso. Ricevi SOLO altezze e durate '
            'approssimative, non ascolti nessun audio. Puoi spiegare '
            'scala, andamento e possibili esercizi. NON dedurre quali '
            'strumenti siano stati utilizzati e NON spacciare la '
            'trascrizione come perfetta.',
        'input': 'Trascrizione monofonica approssimata: ' + melody +
            '. Spiega brevemente il contenuto e un consiglio per suonarlo.',
        'max_output_tokens': 320,
      };
      request.add(utf8.encode(jsonEncode(payload)));
      final response =
          await request.close().timeout(const Duration(seconds: 25));
      final raw = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw HttpException(
          'OpenAI API HTTP ${response.statusCode}. '
          'Verifica chiave, disponibilità del modello e credito API.',
        );
      }

      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final output = parsed['output'];
      if (output is! List) {
        throw const FormatException('Risposta API priva di testo.');
      }
      final fragments = <String>[];
      for (final item in output) {
        if (item is! Map) continue;
        final content = item['content'];
        if (content is! List) continue;
        for (final piece in content) {
          if (piece is Map && piece['text'] is String) {
            fragments.add(piece['text'] as String);
          }
        }
      }
      if (fragments.isEmpty) {
        throw const FormatException('Nessun suggerimento restituito.');
      }
      return fragments.join('\n').trim();
    } finally {
      client.close(force: true);
    }
  }
}
