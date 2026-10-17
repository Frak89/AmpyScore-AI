import 'package:flutter_test/flutter_test.dart';
import 'package:ampy_score_ai/audio/multitrack_engine.dart';
import 'package:ampy_score_ai/audio/stem_extractor.dart';
import 'package:ampy_score_ai/audio/wav_engine.dart';
import 'package:ampy_score_ai/score/score_engine.dart';

void main() {
  InstrumentPart lane(List<DetectedNote> notes) => InstrumentPart(
    family: InstrumentFamily.melody,
    notes: notes,
    confidence: 0.65,
  );

  test('4/4 bar correctly fills remaining time with rests', () {
    final project = ScoreProject.fromTranscription([
      lane([
        const DetectedNote(midi: 60, startSeconds: 0,
            endSeconds: .50, confidence: .8),
      ]),
    ], 120);
    final measure = project.measures(InstrumentFamily.melody).first;
    expect(measure.cells.map((x) => x.length).reduce((a, b) => a + b), 16);
    expect(measure.cells.any((c) => c.isRest), isTrue);
    expect(measure.overflow, isFalse);
    final xml = MusicXmlWriter.export(project);
    expect(xml, contains('<beats>4</beats><beat-type>4</beat-type>'));
    expect(xml, contains('<rest/>'));
    expect(xml, contains('<duration>480</duration>'));
  });

  test('Ties split a note that spans a barline (not overflow)', () {
    final project = ScoreProject.fromTranscription([
      lane([
        const DetectedNote(midi: 60, startSeconds: 1.75,
            endSeconds: 2.35, confidence: .8),
      ]),
    ], 120);
    final all = project.measures(InstrumentFamily.melody);
    expect(all.length, 2);
    expect(all.first.cells.any((c) => c.tieStart), isTrue);
    expect(all.last.cells.any((c) => c.tieStop), isTrue);
    expect(all.first.overflow, isFalse);
    expect(MusicXmlWriter.export(project), contains('<tie type="start"/>'));
    expect(MusicXmlWriter.export(project), contains('<tie type="stop"/>'));
  });

  test('NoteLab overlap is red-bar candidate; deleting resolves it', () {
    final project = ScoreProject.fromTranscription([
      lane([
        const DetectedNote(midi: 60, startSeconds: 0,
            endSeconds: 1.0, confidence: .8),
        const DetectedNote(midi: 62, startSeconds: 1.0,
            endSeconds: 1.5, confidence: .7),
      ]),
    ], 120);
    final events = project.forFamily(InstrumentFamily.melody);
    events[1].start = 0;
    events[1].length = 16;
    expect(project.hasOverflow(InstrumentFamily.melody, 0), isTrue);
    expect(project.estimatedReliability(InstrumentFamily.melody),
        inInclusiveRange(0, 100));
    project.removeNote(events[1].id);
    expect(project.hasOverflow(InstrumentFamily.melody, 0), isFalse);
  });

  test('Spectral focus produces playable local WAV without network', () {
    final wav = DemoWav.create();
    for (final band in FocusStem.values) {
      final focused = StemExtractor.focus(StemRequest(wav, band));
      final decoded = WavAudio.decode(focused);
      expect(decoded.samples.length, greaterThan(1200));
    }
  });
}
