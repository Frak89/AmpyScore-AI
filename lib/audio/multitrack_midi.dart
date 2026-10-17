import 'dart:math' as math;
import 'dart:typed_data';
import 'multitrack_engine.dart';

class TrackMix {
  const TrackMix(this.parts, this.gains, {this.durationSeconds});
  final List<InstrumentPart> parts;
  final Map<InstrumentFamily, double> gains;
  final double? durationSeconds;
}

class MultiTrackMidi {
  static const int sampleRate = 16000;
  static const int ticksPerQuarter = 480;

  /// Type-1 SMF with tempo track and one actual MIDI track per family.
  static Uint8List export(List<InstrumentPart> parts, {int bpm = 120}) {
    final output = BytesBuilder(copy: false);
    final checkedBpm = bpm.clamp(40, 240);
    final ticksPerSecond = ticksPerQuarter * checkedBpm / 60.0;
    output.add([0x4D, 0x54, 0x68, 0x64]); // MThd
    output.add(_u32(6));
    output.add([0, 1, 0, (parts.length + 1) & 255, 1, 0xE0]);

    final tempo = (60000000 / checkedBpm).round();
    final meta = <int>[
      0, 0xFF, 0x51, 3,
      (tempo >> 16) & 255, (tempo >> 8) & 255, tempo & 255,
      // Meter is unknown, 4/4 is an export convention, not analysis.
      0, 0xFF, 0x58, 4, 4, 2, 24, 8,
      0, 0xFF, 0x2F, 0,
    ];
    output.add(_track(meta));
    for (final part in parts) {
      final channel = part.midiChannel;
      final name = part.name.codeUnits.take(110).toList();
      final messages = <_Event>[
        _Event(0, -3, [0xFF, 0x03, name.length, ...name]),
        if (!part.percussion)
          _Event(0, -2, [0xC0 | channel, part.midiProgram]),
      ];
      for (final note in part.notes.take(200)) {
        final first = (note.startSeconds * ticksPerSecond).round().clamp(0, 40000 * 960);
        final last = math.max(first + 1,
            (note.endSeconds * ticksPerSecond).round().clamp(0, 40000 * 960));
        final pitch = note.midi.clamp(0, 127);
        messages.add(_Event(first, 1, [0x90 | channel, pitch, 100]));
        messages.add(_Event(last, 0, [0x80 | channel, pitch, 0]));
      }
      messages.sort((a, b) {
        final tick = a.tick.compareTo(b.tick);
        return tick != 0 ? tick : a.priority.compareTo(b.priority);
      });
      final events = BytesBuilder(copy: false);
      var previousTick = 0;
      for (final entry in messages) {
        events.add(_vlq(entry.tick - previousTick));
        events.add(entry.bytes);
        previousTick = entry.tick;
      }
      events.add([0, 0xFF, 0x2F, 0]);
      output.add(_track(events.toBytes()));
    }
    return output.toBytes();
  }

  /// Renders multiple synthetic pitches, with a distinct timbre per family.
  /// Same local waveform is used for the sound comparison; this does NOT
  /// separate the source recording nor use a General MIDI SoundFont.
  static Uint8List renderMix(TrackMix request) {
    var duration = request.durationSeconds ?? 0.0;
    for (final part in request.parts) {
      for (final note in part.notes) {
        duration = math.max(duration, note.endSeconds + 0.1);
      }
    }
    final length = (duration.clamp(0.4, 40.5) * sampleRate).ceil();
    final samples = Float32List(length);
    for (final part in request.parts) {
      final gain = (request.gains[part.family] ?? 1.0).clamp(0.0, 1.0);
      if (gain <= 0) continue;
      for (final note in part.notes.take(200)) {
        final from = (math.max(0, note.startSeconds) * sampleRate).round();
        final end = math.min(length, (note.endSeconds * sampleRate).round());
        if (from >= end) continue;
        final hz = 440 * math.pow(2, (note.midi - 69) / 12);
        var seed = note.midi * 48271 + from;
        final durationSeconds = (end - from) / sampleRate;
        for (var i = from; i < end; i++) {
          final t = (i - from) / sampleRate;
          final attack = math.min(1.0, t / 0.011);
          final release = math.min(1.0, (durationSeconds - t) / 0.035);
          final env = math.max(0.0, math.min(attack, release));
          final phase = 2 * math.pi * hz * t;
          double wave;
          switch (part.family) {
            case InstrumentFamily.bass:
              wave = math.sin(phase) + .16 * math.sin(2 * phase);
            case InstrumentFamily.harmony:
              wave = math.sin(phase) + .25 * math.sin(3 * phase);
            case InstrumentFamily.melody:
              wave = math.sin(phase) + .36 * math.sin(2 * phase) +
                  .18 * math.sin(3 * phase);
            case InstrumentFamily.drums:
              seed = (seed * 1103515245 + 12345) & 0x7fffffff;
              wave = (seed / 1073741824.0 - 1) *
                  math.exp(-43 * t);
          }
          samples[i] += wave * env * gain * 0.20;
        }
      }
    }
    return _encodeWav(samples);
  }

  static Uint8List _encodeWav(Float32List samples) {
    final wav = Uint8List(44 + samples.length * 2);
    final view = ByteData.sublistView(wav);
    void word(int start, String value) {
      for (var i = 0; i < value.length; i++) {
        wav[start + i] = value.codeUnitAt(i);
      }
    }
    word(0, 'RIFF');
    view.setUint32(4, wav.length - 8, Endian.little);
    word(8, 'WAVE');
    word(12, 'fmt ');
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little);
    view.setUint16(22, 1, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, sampleRate * 2, Endian.little);
    view.setUint16(32, 2, Endian.little);
    view.setUint16(34, 16, Endian.little);
    word(36, 'data');
    view.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      // Soft limiting protects multi-note audio from integer overflow.
      final sample = samples[i];
      final soft = sample / (1 + sample.abs() * 0.5);
      view.setInt16(44 + i * 2,
          (soft.clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    }
    return wav;
  }

  static List<int> _track(List<int> bytes) => [
    0x4D, 0x54, 0x72, 0x6B, ..._u32(bytes.length), ...bytes,
  ];

  static List<int> _u32(int n) =>
      [(n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255];

  static List<int> _vlq(int n) {
    var value = math.max(0, n);
    final out = <int>[value & 0x7F];
    value >>= 7;
    while (value > 0) {
      out.insert(0, 0x80 | (value & 0x7F));
      value >>= 7;
    }
    return out;
  }
}

class _Event {
  const _Event(this.tick, this.priority, this.bytes);
  final int tick;
  final int priority;
  final List<int> bytes;
}
