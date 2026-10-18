import 'dart:math' as math;
import 'multitrack_engine.dart';
import 'wav_engine.dart';

/// Merges short microphone-analysis windows into a progressively growing
/// multistaff score. Frequency families are only provisional source hypotheses.
class LiveTranscriptionAccumulator {
  final Map<InstrumentFamily, List<DetectedNote>> _lanes = {};
  final Map<InstrumentFamily, double> _strengthSum = {};
  final Map<InstrumentFamily, int> _strengthCount = {};

  double _processedUntil = 0;
  double get processedUntil => _processedUntil;
  int get noteCount =>
      _lanes.values.fold(0, (sum, lane) => sum + lane.length);

  void add(MultiTrackResult segment, {
    required double startSeconds,
    required double endSeconds,
  }) {
    if (startSeconds < 0 || endSeconds <= _processedUntil) return;
    final newlyCoveredStart = _processedUntil;
    for (final part in segment.parts) {
      final lane = _lanes.putIfAbsent(part.family, () => []);
      _strengthSum[part.family] =
          (_strengthSum[part.family] ?? 0) + part.signalLevel;
      _strengthCount[part.family] =
          (_strengthCount[part.family] ?? 0) + 1;
      for (final note in part.notes) {
        final begin = math.max(
            newlyCoveredStart, startSeconds + note.startSeconds);
        final end = math.min(endSeconds,
            startSeconds + note.endSeconds);
        if (end <= begin) continue;
        final samePitch = lane.isNotEmpty &&
            lane.last.midi == note.midi &&
            begin - lane.last.endSeconds <= 0.13;
        if (samePitch) {
          final previous = lane.removeLast();
          lane.add(DetectedNote(
            midi: note.midi,
            startSeconds: previous.startSeconds,
            endSeconds: math.max(end, previous.endSeconds),
            confidence: (note.confidence + previous.confidence) / 2,
          ));
        } else {
          lane.add(DetectedNote(
            midi: note.midi,
            startSeconds: begin,
            endSeconds: end,
            confidence: note.confidence,
          ));
        }
      }
    }
    _processedUntil = math.max(_processedUntil, endSeconds);
  }

  List<InstrumentPart> get parts => [
    for (final family in InstrumentFamily.values)
      if (_lanes[family]?.isNotEmpty ?? false)
        InstrumentPart(
          family: family,
          notes: List.unmodifiable(_lanes[family]!),
          confidence: switch (family) {
            InstrumentFamily.bass => .60,
            InstrumentFamily.harmony => .43,
            InstrumentFamily.melody => .54,
            InstrumentFamily.drums => .35,
          },
          signalLevel: (_strengthSum[family] ?? .6) /
              math.max(1, _strengthCount[family] ?? 0),
        ),
  ];

  void clear() {
    _lanes.clear();
    _strengthSum.clear();
    _strengthCount.clear();
    _processedUntil = 0;
  }
}
