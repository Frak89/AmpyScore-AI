import 'dart:math' as math;
import 'package:xml/xml.dart';
import '../audio/multitrack_engine.dart';
import '../score/score_engine.dart';

class ReferenceNote {
  const ReferenceNote(this.midi, this.startTick);
  final int midi;
  final int startTick;
}

class ScoreComparison {
  const ScoreComparison({
    required this.f1,
    required this.matched,
    required this.transcribed,
    required this.reference,
    this.meter,
  });
  final double f1;
  final int matched;
  final int transcribed;
  final int reference;
  final int? meter;
}

/// Offline MusicXML note-onset evaluation. A score sourced by the user is
/// compared to the local transcription (not retrieved/scraped automatically).
class ReferenceScore {
  static (List<ReferenceNote>, int?) parse(String input) {
    final xml = XmlDocument.parse(input);
    final parts = xml.findAllElements('part');
    final notes = <ReferenceNote>[];
    int? beats;
    for (final part in parts) {
      var divisions = 480;
      var current = 0.0;
      var previous = 0.0;
      for (final measure in part.findElements('measure')) {
        for (final child in measure.children.whereType<XmlElement>()) {
          if (child.name.local == 'attributes') {
            final div = child.findAllElements('divisions').firstOrNull;
            if (div != null) divisions =
                int.tryParse(div.innerText.trim()) ?? divisions;
            final b = child.findAllElements('beats').firstOrNull;
            if (beats == null && b != null) beats =
                int.tryParse(b.innerText.trim());
          }
          if (child.name.local == 'backup') {
            final value = double.tryParse(
                child.findElements('duration').firstOrNull?.innerText ?? '0') ?? 0;
            current = math.max(0, current - value / divisions);
          }
          if (child.name.local == 'forward') {
            final value = double.tryParse(
                child.findElements('duration').firstOrNull?.innerText ?? '0') ?? 0;
            current += value / divisions;
          }
          if (child.name.local != 'note') continue;
          final chord = child.findElements('chord').isNotEmpty;
          final onset = chord ? previous : current;
          final rawDuration = double.tryParse(
              child.findElements('duration').firstOrNull?.innerText ?? '0') ?? 0;
          if (!chord) previous = current;
          final pitch = child.findElements('pitch').firstOrNull;
          if (pitch != null && child.findElements('rest').isEmpty) {
            final step = pitch.findElements('step').firstOrNull?.innerText.trim();
            final octave = int.tryParse(
                pitch.findElements('octave').firstOrNull?.innerText ?? '');
            final alter = int.tryParse(
                pitch.findElements('alter').firstOrNull?.innerText ?? '0') ?? 0;
            const steps = {'C':0,'D':2,'E':4,'F':5,'G':7,'A':9,'B':11};
            if (octave != null && steps.containsKey(step)) {
              final midi = (octave + 1) * 12 + steps[step]! + alter;
              notes.add(ReferenceNote(midi,
                  (onset * ticksPerQuarter).round()));
            }
          }
          if (!chord) current += rawDuration / divisions;
        }
      }
    }
    return (notes, beats);
  }

  static ScoreComparison compare(ScoreProject project, String xml) {
    final (reference, beats) = parse(xml);
    final detected = <ReferenceNote>[
      for (final part in project.parts)
        for (final item in project.forFamily(part.family))
          if (!item.isRest) ReferenceNote(item.midi, item.start),
    ];
    var matches = 0;
    final seen = <int>{};
    for (final note in detected) {
      var best = -1;
      var distance = 3;
      for (var i = 0; i < reference.length; i++) {
        if (seen.contains(i) || reference[i].midi != note.midi) continue;
        final delta = (reference[i].startTick - note.startTick).abs();
        if (delta <= 2 && delta < distance) {
          best = i;
          distance = delta;
        }
      }
      if (best >= 0) {
        seen.add(best);
        matches++;
      }
    }
    final f1 = detected.isEmpty && reference.isEmpty ? 1.0 :
        detected.isEmpty || reference.isEmpty ? 0.0 :
        2 * matches / (detected.length + reference.length);
    return ScoreComparison(f1: f1, matched: matches,
        transcribed: detected.length, reference: reference.length,
        meter: beats);
  }
}
