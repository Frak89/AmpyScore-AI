import 'dart:convert';
import 'dart:io';

class SongCandidate {
  const SongCandidate(this.title, this.artist, this.url);
  final String title;
  final String artist;
  final Uri url;
}

/// Optional web metadata lookup; only a sanitized file TITLE is sent.
/// Does not fingerprint audio or compare MIDI against original sheet music.
class SongLookup {
  static String? filenameTitle(String filename) {
    var clean = filename.replaceAll(RegExp(r'\.[a-z0-9]{2,5}$',
        caseSensitive: false), '').trim();
    clean = clean.replaceAll(RegExp(r'[_\-.]+'), ' ').replaceAll(
        RegExp(r'\b(?:track|audio|recording|untitled|import|brano|demo)\b',
            caseSensitive: false), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length < 4 || clean.length > 140) return null;
    if (RegExp(r'^\d+$').hasMatch(clean)) return null;
    return clean;
  }

  static Future<List<SongCandidate>> find(String filename) async {
    final title = filenameTitle(filename);
    if (title == null) return [];
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 9);
    try {
      final uri = Uri.https('musicbrainz.org', '/ws/2/recording', {
        'query': 'recording:"$title"',
        'fmt': 'json',
        'limit': '5',
      });
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent',
          'AmpyScoreAI/0.6 (https://github.com/Frak89/AmpyScore-AI)');
      final response = await request.close()
          .timeout(const Duration(seconds: 13));
      if (response.statusCode != 200) {
        throw HttpException('MusicBrainz: ${response.statusCode}');
      }
      final json = jsonDecode(
        await response.transform(utf8.decoder).join(),
      ) as Map<String, dynamic>;
      final recordings = (json['recordings'] as List?) ?? const [];
      return [
        for (final item in recordings)
          if (item is Map && item['id'] is String)
            SongCandidate(
              (item['title'] as String?) ?? 'Titolo sconosciuto',
              ((item['artist-credit'] as List?) ?? const [])
                  .whereType<Map>()
                  .map((e) => e['name']?.toString() ?? '')
                  .where((name) => name.isNotEmpty)
                  .join(', '),
              Uri.https('musicbrainz.org',
                  '/recording/${item['id']}'),
            ),
      ];
    } finally {
      client.close(force: true);
    }
  }
}
