import 'dart:math' as math;

import 'multitrack_engine.dart';
import 'wav_engine.dart';

/// Rhythmic values inferred from the timing of detected events.
/// A quarter note is one beat; this is separate from the time signature.
enum NoteValue {
  sixteenth('1/16', 0.25),
  eighth('1/8', 0.5),
  quarter('1/4', 1.0),
  half('1/2', 2.0),
  whole('1/1', 4.0);

  const NoteValue(this.label, this.beats);
  final String label;
  final double beats;
}

class RhythmReport {
  const RhythmReport({
    required this.bpm,
    required this.confidence,
    required this.values,
  });
  final int bpm;
  final double confidence;
  final Set<NoteValue> values;
  double get quarterSeconds => 60.0 / bpm;

  /// The first symbol is the most likely conventional *note value*, NOT meter.
  NoteValue valueFor(DetectedNote note, {DetectedNote? next}) {
    final gap = next == null ? note.durationSeconds :
        next.startSeconds - note.startSeconds;
    final duration = gap > 0 && gap < quarterSeconds * 5
        ? gap : note.durationSeconds;
    final beats = duration / quarterSeconds;
    var closest = NoteValue.quarter;
    var bestError = double.infinity;
    for (final candidate in NoteValue.values) {
      final error = (math.log(math.max(0.01, beats) /
                  candidate.beats)).abs();
      if (error < bestError) {
        bestError = error;
        closest = candidate;
      }
    }
    return closest;
  }
}

class RhythmAnalyzer {
  /// Approximate beat grid using coincidences between note onsets.
  ///
  /// No reliable time-signature inference is claimed: 4/4 is merely
  /// an export default. BPM ambiguity (half/double time) is intrinsic.
  static RhythmReport estimate(List<InstrumentPart> parts) {
    final onsetEvents = <double>[];
    for (final part in parts) {
      for (final note in part.notes) {
        onsetEvents.add(note.startSeconds);
      }
    }
    onsetEvents.sort();
    final unique = <double>[];
    for (final at in onsetEvents) {
      if (unique.isEmpty || at - unique.last > 0.055) unique.add(at);
    }
    if (unique.length < 3) {
      return const RhythmReport(
        bpm: 120, confidence: 0.0, values: <NoteValue>{},
      );
    }

    // Beat candidates in 55..190 BPM, comparing pairs of note onsets
    // against quarter/eighth/sixteenth/half beats. This is an intentionally
    // small, bounded estimator for short recordings.
    var bestBpm = 120;
    var best = double.negativeInfinity;
    var runnerUp = double.negativeInfinity;
    for (var bpm = 55; bpm <= 190; bpm++) {
      final beatSeconds = 60.0 / bpm;
      var score = 0.0;
      var comparisons = 0;
      for (var i = 0; i < unique.length; i++) {
        for (var j = i + 1; j < unique.length && j <= i + 7; j++) {
          final delta = unique[j] - unique[i];
          if (delta > 2.6) break;
          final beats = delta / beatSeconds;
          final closestUnits = (beats * 4).round();
          if (closestUnits < 1 || closestUnits > 16) continue;
          final residue = (beats - closestUnits / 4).abs();
          final precision = math.exp(-math.pow(residue / 0.065, 2));
          final weight = closestUnits % 4 == 0
              ? 1.1 : (closestUnits.isEven ? 0.7 : 0.38);
          score += precision * weight / math.sqrt(j - i);
          comparisons++;
        }
      }
      final bias = 1.0 - 0.0015 * (bpm - 116).abs();
      score = comparisons == 0 ? 0 : score * bias;
      if (score > best) {
        runnerUp = best;
        best = score;
        bestBpm = bpm;
      } else if (score > runnerUp) {
        runnerUp = score;
      }
    }
    final conf = unique.length >= 5
        ? (0.35 + 0.35 * (1 - math.exp(-unique.length / 12)))
            .clamp(0.0, 0.75).toDouble()
        : 0.25;
    final temporary = RhythmReport(bpm: bestBpm, confidence: conf, values: {});
    final values = <NoteValue>{};
    for (final part in parts) {
      for (var i = 0; i < part.notes.length; i++) {
        values.add(temporary.valueFor(part.notes[i],
            next: i + 1 < part.notes.length ? part.notes[i + 1] : null));
      }
    }
    return RhythmReport(bpm: bestBpm, confidence: conf, values: values);
  }
}
