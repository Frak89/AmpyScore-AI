import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ampy_score_ai/audio/live_capture_store.dart';
import 'package:ampy_score_ai/audio/live_transcription.dart';
import 'package:ampy_score_ai/audio/multitrack_engine.dart';
import 'package:ampy_score_ai/audio/wav_engine.dart';
import 'package:ampy_score_ai/audio/wav_window_reader.dart';
import 'package:ampy_score_ai/score/score_engine.dart';

void main() {
  test('Live PCM recording produces valid WAV snapshots and full output',
      () async {
    const rate = 16000;
    final dir = await Directory.systemTemp.createTemp('ampyscore-mic');
    try {
      final file = File('${dir.path}/live.wav');
      final store = await LiveCaptureStore.open(file);
      // 4 seconds of A4. Feed non-aligned stream buffers to exercise
      // carryover handling between audio callbacks.
      final pcm = Uint8List(rate * 4 * 2);
      final view = ByteData.sublistView(pcm);
      for (var i = 0; i < rate * 4; i++) {
        view.setInt16(i * 2,
            (math.sin(2 * math.pi * i * 440 / rate) * 12000).round(),
            Endian.little);
      }
      await store.append(Uint8List.sublistView(pcm, 0, 3333));
      await store.append(Uint8List.sublistView(pcm, 3333, rate * 2));
      final duration = await store.snapshot();
      expect(duration, closeTo(1.0, 0.001));
      final preview = await WavWindowReader.open(file);
      final wav = await preview.window(0, 1);
      expect(WavAudio.decode(wav).samples.isNotEmpty, true);
      await store.append(Uint8List.sublistView(pcm, rate * 2));
      await store.finish();
      final full = await WavWindowReader.open(file);
      expect(full.durationSeconds, closeTo(4, .01));
      expect(store.closed, isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('Live notes from overlapping windows merge into independent staves',
      () {
    final accumulator = LiveTranscriptionAccumulator();
    accumulator.add(MultiTrackResult([
      InstrumentPart(
        family: InstrumentFamily.bass,
        confidence: .5,
        notes: [const DetectedNote(midi: 45, startSeconds: .5,
          endSeconds: 2.0, confidence: .8)],
      ),
      InstrumentPart(
        family: InstrumentFamily.melody,
        confidence: .5,
        notes: [const DetectedNote(midi: 69, startSeconds: 1,
          endSeconds: 1.5, confidence: .7)],
      ),
    ], 3), startSeconds: 0, endSeconds: 1.8);
    accumulator.add(MultiTrackResult([
      InstrumentPart(
        family: InstrumentFamily.bass,
        confidence: .5,
        notes: [const DetectedNote(midi: 45, startSeconds: .0,
          endSeconds: .8, confidence: .8)],
      ),
    ], 1), startSeconds: 1.5, endSeconds: 2.3);
    expect(accumulator.parts.length, 2);
    final bass = accumulator.parts.firstWhere(
        (part) => part.family == InstrumentFamily.bass);
    expect(bass.notes.length, 1);
    expect(bass.notes.single.startSeconds, closeTo(.5, .01));
    expect(bass.notes.single.endSeconds, closeTo(2.3, .01));
    final score = ScoreProject.fromTranscription(accumulator.parts, 120,
      minimumDurationSeconds: 2.3);
    expect(score.forFamily(InstrumentFamily.melody), isNotEmpty);
    expect(score.forFamily(InstrumentFamily.bass), isNotEmpty);
    expect(accumulator.noteCount, 2);
  });
}
