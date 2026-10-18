import 'package:flutter_test/flutter_test.dart';
import 'package:ampy_score_ai/audio/multitrack_engine.dart';
import 'package:ampy_score_ai/audio/wav_engine.dart';
import 'package:ampy_score_ai/score/score_engine.dart';
import 'package:ampy_score_ai/score/reference_score.dart';

void main() {
  test('Import MusicXML 5/4 and compare true note/onset matches', () {
    final score = ScoreProject.fromTranscription([
      InstrumentPart(
        family: InstrumentFamily.melody,
        confidence: .8,
        notes: [
          const DetectedNote(midi: 60,
            startSeconds: 0, endSeconds: .5, confidence: .9),
        ],
      ),
    ], 120, beatsPerBar: 5);
    final xml = MusicXmlWriter.export(score);
    final evaluated = ReferenceScore.compare(score, xml);
    expect(evaluated.meter, 5);
    expect(evaluated.matched, greaterThan(0));
    expect(evaluated.f1, greaterThan(.6));
  });

  test('Wrong pitches lower score F1; no spurious 100% accuracy claim', () {
    final reference = ScoreProject.fromTranscription([
      InstrumentPart(family: InstrumentFamily.melody,
        confidence: .8, notes: [
          const DetectedNote(midi: 60,
            startSeconds: 0, endSeconds: .5, confidence: .8),
        ]),
    ], 120);
    final xml = MusicXmlWriter.export(reference);
    final found = ScoreProject.fromTranscription([
      InstrumentPart(family: InstrumentFamily.melody,
        confidence: .8, notes: [
          const DetectedNote(midi: 64,
            startSeconds: 0, endSeconds: .5, confidence: .8),
        ]),
    ], 120);
    expect(ReferenceScore.compare(found, xml).f1, 0);
  });
}
