import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ampy_score_ai/audio/wav_engine.dart';
import 'package:ampy_score_ai/audio/wav_window_reader.dart';
import 'package:ampy_score_ai/audio/multitrack_engine.dart';
import 'package:ampy_score_ai/audio/multitrack_midi.dart';
import 'package:ampy_score_ai/score/score_engine.dart';

void main() {
  test('WAV window reader sees notes after 40s without full-song decode', () async {
    const rate = 16000, seconds = 53;
    final n = rate * seconds;
    final wav = Uint8List(44 + 2 * n);
    final bd = ByteData.sublistView(wav);
    void put(int offset, String name) {
      for (var i = 0; i < name.length; i++) {
        wav[offset + i] = name.codeUnitAt(i);
      }
    }
    put(0, 'RIFF'); put(8, 'WAVE'); put(12, 'fmt '); put(36, 'data');
    bd.setUint32(4, wav.length - 8, Endian.little);
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);
    bd.setUint16(22, 1, Endian.little);
    bd.setUint32(24, rate, Endian.little);
    bd.setUint32(28, rate * 2, Endian.little);
    bd.setUint16(32, 2, Endian.little);
    bd.setUint16(34, 16, Endian.little);
    put(36, 'data');
    bd.setUint32(40, n * 2, Endian.little);
    for (var i = 46 * rate; i < 47 * rate; i++) {
      final t = (i - 46 * rate) / rate;
      final envelope = math.min(1.0, (47 * rate - i) / 800);
      bd.setInt16(44 + 2 * i,
          (0.62 * math.max(0.0, envelope) *
              math.sin(2 * math.pi * 440 * t) * 32767).round(),
          Endian.little);
    }
    final tmp = await Directory.systemTemp.createTemp('ampyscore-full');
    try {
      final file = File('${tmp.path}/long.wav');
      await file.writeAsBytes(wav);
      final reader = await WavWindowReader.open(file);
      expect(reader.durationSeconds, closeTo(53, .01));
      final endOfSong = await reader.window(44, 9);
      expect(endOfSong.length, lessThan(300000));
      final wave = WavAudio.decode(endOfSong);
      expect(wave.samples.length / wave.sampleRate, closeTo(9, .02));
      final notes = WavTranscriber.transcribe(endOfSong);
      expect(notes.any((note) => note.midi == 69), isTrue);
    } finally {
      await tmp.delete(recursive: true);
    }
  });

  test('MIDI SMF format 1 includes >200 notes in later measures', () {
    final notes = [
      for (var i = 0; i < 260; i++)
        DetectedNote(midi: 60 + i % 12, startSeconds: i * .20,
          endSeconds: i * .20 + .14, confidence: .8),
    ];
    final midi = MultiTrackMidi.export([
      InstrumentPart(family: InstrumentFamily.melody,
          notes: notes, confidence: .7),
    ], bpm: 120, beatsPerBar: 5);
    expect(String.fromCharCodes(midi.sublist(0, 4)), 'MThd');
    expect(midi.length, greaterThan(2000));
    expect(midi.contains(5), isTrue);
  });

  test('5/4 score spans full recording and lazily returns selected bars', () {
    final part = InstrumentPart(family: InstrumentFamily.melody,
      confidence: .7, notes: [
        const DetectedNote(midi: 69, startSeconds: 45,
          endSeconds: 47, confidence: .8),
      ]);
    final score = ScoreProject.fromTranscription([part], 120,
      beatsPerBar: 5, minimumDurationSeconds: 53);
    expect(score.barCount, greaterThan(18));
    expect(score.measuresRange(InstrumentFamily.melody, 9, 12).length, 3);
    final xml = MusicXmlWriter.export(score);
    expect(xml, contains('<beats>5</beats><beat-type>4</beat-type>'));
    expect(score.hasOverflow(InstrumentFamily.melody, 18), isFalse);
  });
}
