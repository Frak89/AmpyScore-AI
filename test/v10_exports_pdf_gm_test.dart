import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ampy_score_ai/audio/gm_catalog.dart';
import 'package:ampy_score_ai/audio/playback_tuning.dart';
import 'package:ampy_score_ai/audio/multitrack_engine.dart';
import 'package:ampy_score_ai/audio/multitrack_midi.dart';
import 'package:ampy_score_ai/audio/wav_engine.dart';
import 'package:ampy_score_ai/score/score_engine.dart';
import 'package:ampy_score_ai/score/score_pdf.dart';

void main() {
  test('Full General MIDI bank and all GM channel 10 instruments', () {
    expect(GmCatalog.programs.length, 128);
    expect(GmCatalog.programs.first, 'Acoustic Grand Piano');
    expect(GmCatalog.programs.last, 'Gunshot');
    expect(GmCatalog.percussion.length, 47);
    expect(GmCatalog.percussion[35], 'Acoustic Bass Drum');
    expect(GmCatalog.percussion[81], 'Open Triangle');
  });

  test('Experimental synth permits 4096 audio-buffer frames', () {
    expect(PlaybackTuning.bufferFrames, contains(4096));
    expect(PlaybackTuning.supportsBuffer(4096), isTrue);
    expect(PlaybackTuning.nominalMilliseconds(4096, 48000),
        closeTo(85.33, .1));
  });

  test('Chromatic layer is opt-in, never applied to percussion', () {
    final instrument = InstrumentPart(
      family: InstrumentFamily.melody,
      notes: [const DetectedNote(midi: 60,
        startSeconds: 0,endSeconds:.5,confidence:.9)],
      confidence:.7,
    );
    final normal = MultiTrackMidi.export([instrument]);
    final layered = MultiTrackMidi.export([instrument],
        semitoneLayer: true);
    expect(layered.length, greaterThan(normal.length));
    final drum = InstrumentPart(
      family: InstrumentFamily.drums,
      notes: [const DetectedNote(midi: 42,
        startSeconds: 0,endSeconds:.5,confidence:.9)],
      confidence:.7,
    );
    expect(MultiTrackMidi.export([drum],semitoneLayer:true),
        MultiTrackMidi.export([drum]));
  });

  test('Score PDF exports valid multipage PDF with score edits', () async {
    final part = InstrumentPart(
      family: InstrumentFamily.melody,
      notes: [
        const DetectedNote(midi:60,startSeconds:0,
          endSeconds:.5,confidence:.9),
        const DetectedNote(midi:64,startSeconds:10,
          endSeconds:10.5,confidence:.8),
      ],
      confidence:.75,
    );
    final score = ScoreProject.fromTranscription(
        [part],120,beatsPerBar:5,minimumDurationSeconds:34);
    final pdf = await ScorePdf.render(score,
      title:'Studio PDF test',sepia:true);
    expect(String.fromCharCodes(pdf.sublist(0,5)), '%PDF-');
    expect(pdf.length,greaterThan(1000));
    await Directory('build').create(recursive:true);
    await File('build/ampyscore_score_smoke.pdf').writeAsBytes(pdf);
  });
}
