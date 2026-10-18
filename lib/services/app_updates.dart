import 'dart:convert';
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class GitHubUpdate {
  const GitHubUpdate(this.version, this.url, this.hasNewVersion);
  final String version;
  final Uri url;
  final bool hasNewVersion;
}

/// Explicit, read-only release check: no background network requests and
/// no silent APK install. Signed APK updates must keep the same key.
class AppUpdates {
  static final releases = Uri.parse(
    'https://github.com/Frak89/AmpyScore-AI/releases',
  );

  static int _compare(String a, String b) {
    final partsA = RegExp(r'\d+').allMatches(a).take(3)
        .map((m) => int.parse(m.group(0)!)).toList();
    final partsB = RegExp(r'\d+').allMatches(b).take(3)
        .map((m) => int.parse(m.group(0)!)).toList();
    for (var i = 0; i < 3; i++) {
      final x = i < partsA.length ? partsA[i] : 0;
      final y = i < partsB.length ? partsB[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static Future<GitHubUpdate?> check() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 9);
    try {
      final req = await client.getUrl(Uri.https(
        'api.github.com',
        '/repos/Frak89/AmpyScore-AI/releases/latest',
      ));
      req.headers.set('User-Agent', 'AmpyScoreAI/0.6');
      req.headers.set('Accept', 'application/vnd.github+json');
      final reply = await req.close().timeout(const Duration(seconds: 12));
      if (reply.statusCode == 404) return null; // No published release.
      if (reply.statusCode != 200) {
        throw HttpException('GitHub: HTTP ${reply.statusCode}');
      }
      final body = await reply.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final tag = (data['tag_name'] as String? ?? '').trim();
      if (tag.isEmpty) return null;
      final html = data['html_url'] as String?;
      final url = Uri.tryParse(html ?? '');
      if (url == null || url.host != 'github.com' ||
          url.pathSegments.take(2).join('/') != 'Frak89/AmpyScore-AI') {
        return null;
      }
      final current = (await PackageInfo.fromPlatform()).version;
      return GitHubUpdate(tag, url, _compare(tag, current) > 0);
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> openReleases({Uri? url}) async {
    await launchUrl(url ?? releases, mode: LaunchMode.externalApplication);
  }
}
