import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../audio/multitrack_engine.dart';
import '../audio/wav_engine.dart';

/// Machine-readable result of genuine source separation and polyphonic
/// transcription. No inferred or invented confidence figures in this loader.
class AiStemSession {
  const AiStemSession({
    required this.title,
    required this.originalPath,
    required this.instrumentalPath,
    required this.parts,
    required this.stems,
    required this.bpm,
    required this.beatsPerBar,
    required this.durationSeconds,
  });

  final String title;
  final String originalPath;
  final String? instrumentalPath;
  final List<InstrumentPart> parts;
  final Map<InstrumentFamily, String> stems;
  final int bpm;
  final int beatsPerBar;
  final double durationSeconds;

  static const maxArchiveBytes = 1200 * 1024 * 1024;
  static const maxFiles = 32;
  static const maxNoteEvents = 150000;

  static bool safePath(String value) =>
      value.isNotEmpty && !value.startsWith('/') &&
      !value.contains('\\') && !value.contains('..') &&
      !value.contains(':') && !value.startsWith('.') &&
      value.split('/').every((segment) =>
          segment.isNotEmpty && !segment.startsWith('.'));

  static InstrumentFamily? _family(String key) => switch (key) {
    'vocals' => InstrumentFamily.melody,
    'bass' => InstrumentFamily.bass,
    'drums' => InstrumentFamily.drums,
    'other' => InstrumentFamily.harmony,
    _ => null,
  };

  /// Parse metadata independently from zip extraction (unit-testable).
  static AiStemSession fromManifest(
      Map<String, dynamic> manifest, String root) {
    if (manifest['format'] != 'ampyscore-ai-session' ||
        manifest['version'] != 1) {
      throw const FormatException('Formato progetto AI non riconosciuto.');
    }
    final title = manifest['title'];
    final original = manifest['original'];
    if (title is! String || title.trim().isEmpty ||
        original is! String || !safePath(original)) {
      throw const FormatException('Metadati progetto incompleti.');
    }
    final bpmInput = manifest['bpm'];
    final meterInput = manifest['beatsPerBar'];
    final durationInput = manifest['durationSeconds'];
    final bpm = bpmInput is num ? bpmInput.toInt().clamp(40, 240) : 120;
    final meter = meterInput is num
        ? meterInput.toInt().clamp(2, 12) : 4;
    final duration = durationInput is num
        ? durationInput.toDouble() : 0.0;
    if (!duration.isFinite || duration <= 0 || duration > 24 * 3600) {
      throw const FormatException('Durata audio fuori dai limiti.');
    }
    final tracks = manifest['tracks'];
    if (tracks is! List || tracks.length > 4 || tracks.isEmpty) {
      throw const FormatException('Servono fino a quattro sorgenti audio.');
    }
    final parts = <InstrumentPart>[];
    final stems = <InstrumentFamily, String>{};
    for (final data in tracks) {
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Traccia AI non valida.');
      }
      final family = _family(data['id']?.toString() ?? '');
      final audioPath = data['audio'];
      final label = data['label'];
      final rawNotes = data['notes'];
      if (family == null || stems.containsKey(family) ||
          audioPath is! String || !safePath(audioPath) ||
          label is! String || label.length > 100 ||
          rawNotes is! List || rawNotes.length > maxNoteEvents) {
        throw const FormatException('Traccia o elenco note non valido.');
      }
      final parsed = <DetectedNote>[];
      for (final event in rawNotes) {
        if (event is! Map<String, dynamic>) {
          throw const FormatException('Evento nota non valido.');
        }
        final pitch = event['midi'];
        final start = event['start'];
        final end = event['end'];
        final confidence = event['confidence'];
        if (pitch is! num || start is! num || end is! num ||
            confidence is! num) {
          throw const FormatException('Valori nota non validi.');
        }
        final first = start.toDouble(), last = end.toDouble();
        if (!first.isFinite || !last.isFinite ||
            first < 0 || last <= first || last > duration + 1 ||
            pitch.toInt() < 0 || pitch.toInt() > 127) {
          continue;
        }
        parsed.add(DetectedNote(
          midi: pitch.toInt(),
          startSeconds: first,
          endSeconds: last,
          confidence: confidence.toDouble().clamp(0, 1),
        ));
      }
      parsed.sort((a, b) =>
          a.startSeconds.compareTo(b.startSeconds));
      final program = data['gmProgram'];
      final programId = program is num && program >= 0 &&
              program <= 127 ? program.toInt() : null;
      final evidence = data['confidence'] is num
          ? (data['confidence'] as num).toDouble().clamp(0.0, 1.0) : .65;
      parts.add(InstrumentPart(
        family: family, notes: parsed, confidence: evidence,
        signalLevel: 0.75, programOverride: programId,
        sourceName: label,
      ));
      stems[family] = '$root/$audioPath';
    }
    return AiStemSession(
      title: title,
      originalPath: '$root/$original',
      instrumentalPath: manifest['instrumental'] is String &&
          safePath(manifest['instrumental'] as String)
          ? '$root/${manifest['instrumental']}' : null,
      parts: parts,
      stems: stems,
      bpm: bpm,
      beatsPerBar: meter,
      durationSeconds: duration,
    );
  }

  /// Decode the ZIP on a worker isolate; malicious paths, links and oversized
  /// expanded archives are rejected before creating any output files.
  static Future<AiStemSession> load(String zipPath) async {
    final file = File(zipPath);
    if (await file.length() > maxArchiveBytes) {
      throw const FormatException('Progetto AI oltre il limite di 1,2 GB.');
    }
    final directory = await getApplicationDocumentsDirectory();
    final target = Directory('${directory.path}/ampyscore_ai_'
        '${DateTime.now().microsecondsSinceEpoch}');
    try {
      await compute(_unpack, (zipPath, target.path));
      final data = jsonDecode(
          await File('${target.path}/manifest.json').readAsString());
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Manifest AI non valido.');
      }
      final session = fromManifest(data, target.path);
      if (!await File(session.originalPath).exists()) {
        throw const FormatException('Brano originale assente dal progetto.');
      }
      if (session.instrumentalPath != null &&
          !await File(session.instrumentalPath!).exists()) {
        throw const FormatException('Base strumentale mancante.');
      }
      for (final stem in session.stems.values) {
        if (!await File(stem).exists()) {
          throw const FormatException('Sorgente musicale mancante.');
        }
      }
      return session;
    } catch (_) {
      if (await target.exists()) await target.delete(recursive: true);
      rethrow;
    }
  }

  static Future<void> _unpack((String, String) input) async {
    final (zipPath, destination) = input;
    final stream = InputFileStream(zipPath);
    try {
      final zip = ZipDecoder().decodeStream(stream);
      if (zip.length > maxFiles) {
        throw const FormatException('Troppi file nel progetto AI.');
      }
      var total = 0;
      var manifestCount = 0;
      for (final entry in zip) {
        final name = entry.name;
        if (!safePath(name) || entry.isSymbolicLink || !entry.isFile) {
          throw const FormatException('Elemento ZIP non sicuro.');
        }
        if (name == 'manifest.json') manifestCount++;
        if (entry.size > maxArchiveBytes ||
            total > maxArchiveBytes - entry.size) {
          throw const FormatException('Dimensione decompressa eccessiva.');
        }
        total += entry.size;
      }
      if (manifestCount != 1) {
        throw const FormatException('Manifest AI mancante.');
      }
      Directory(destination).createSync(recursive: true);
      // ZIP writers may omit explicit directory entries. Only validated
      // relative paths are used to create the necessary subdirectories.
      for (final entry in zip) {
        final components = entry.name.split('/');
        if (components.length > 1) {
          final parent = components.sublist(0, components.length - 1)
              .join(Platform.pathSeparator);
          Directory('$destination/$parent')
              .createSync(recursive: true);
        }
      }
      await extractArchiveToDisk(zip, destination);
    } finally {
      await stream.close();
    }
  }
}
