import 'package:flutter_test/flutter_test.dart';
import 'package:ampy_score_ai/audio/wav_engine.dart';
import 'package:ampy_score_ai/audio/multitrack_engine.dart';
import 'package:ampy_score_ai/score/score_engine.dart';

InstrumentPart part(List<DetectedNote> notes) => InstrumentPart(
  family: InstrumentFamily.harmony,
  notes: notes, confidence: .65,
  sourceName: 'Pianoforte e altri · sorgente AI',
);

void main() {
  test('Neural polyphonic chord does not discard overlapping notes', () {
    final score = ScoreProject.fromTranscription([
      part([
        const DetectedNote(midi: 60,startSeconds: 0,
          endSeconds: .50,confidence: .9),
        const DetectedNote(midi: 64,startSeconds: 0,
          endSeconds: .50,confidence: .9),
        const DetectedNote(midi: 67,startSeconds: 0,
          endSeconds: .50,confidence: .9),
      ]),
    ], 120, polyphonic: true);
    expect(score.notes.length, 3);
    expect(score.measures(InstrumentFamily.harmony).first.overflow, false);
    final chords=score.measures(InstrumentFamily.harmony)
        .first.cells.where((x)=>x.chord).length;
    expect(chords, 2);
    final xml=MusicXmlWriter.export(score);
    expect('<chord/>'.allMatches(xml).length, 2);
    expect(xml, contains('Pianoforte e altri'));
    expect(xml, contains('<voice>1</voice>'));
  });

  test('Different overlapping durations create independent MusicXML voices', () {
    final score=ScoreProject.fromTranscription([
      part([
        const DetectedNote(midi: 60,startSeconds:0,
          endSeconds:1,confidence:.8),
        const DetectedNote(midi:67,startSeconds:.5,
          endSeconds:1.5,confidence:.8),
      ]),
    ],120,polyphonic:true);
    expect(score.notes.length,2);
    final xml=MusicXmlWriter.export(score);
    expect(xml, contains('<backup><duration>1920</duration></backup>'));
    expect(xml, contains('<voice>2</voice>'));
    expect(score.hasOverflow(InstrumentFamily.harmony,0),isFalse);
  });

  test('Legacy NoteLab overlap warning remains enabled for manual mode', () {
    final score=ScoreProject.fromTranscription([
      part([
        const DetectedNote(midi:60,startSeconds:0,
          endSeconds:1,confidence:.8),
        const DetectedNote(midi:67,startSeconds:.5,
          endSeconds:1.5,confidence:.8),
      ]),
    ],120);
    // Legacy mode protects the monophonic editor against incompatible
    // overlapping edits; ML mode preserves intentional chord notes.
    expect(score.polyphonic,isFalse);
    expect(score.notes.length,2);
  });
}
