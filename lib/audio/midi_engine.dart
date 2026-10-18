import 'dart:math' as math;
import 'dart:typed_data';

import 'wav_engine.dart';

/// Turns approximate DetectedNote events into a real Standard MIDI File
/// (format 0) and a local PCM preview. No network or soundfont needed.
class MidiEngine {
  static const int sampleRate = 16000;
  static const int ticksPerQuarter = 480;
  // Fixed 120 BPM: 960 MIDI ticks/second; event start/duration in seconds
  // remain identical to the analyzed timeline.
  static const int ticksPerSecond = 960;

  static Uint8List exportMidi(List<DetectedNote> notes) {
    final events = <_MidiEvent>[
      const _MidiEvent(0, -2, [0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]),
      const _MidiEvent(0, -1, [0xC0, 0]), // Acoustic piano, channel 1.
    ];
    for (final note in notes) {
      final start = math.max(0, (note.startSeconds * ticksPerSecond).round());
      final end = math.max(
        start + 1,
        (note.endSeconds * ticksPerSecond).round(),
      );
      events.add(_MidiEvent(start, 1, [0x90, note.midi.clamp(0, 127), 100]));
      events.add(_MidiEvent(end, 0, [0x80, note.midi.clamp(0, 127), 0]));
    }
    events.sort((a, b) {
      final byTick = a.tick.compareTo(b.tick);
      return byTick == 0 ? a.priority.compareTo(b.priority) : byTick;
    });

    final track = BytesBuilder(copy: false);
    var previousTick = 0;
    for (final event in events) {
      track.add(_vlq(event.tick - previousTick));
      track.add(event.bytes);
      previousTick = event.tick;
    }
    track.add([0, 0xFF, 0x2F, 0]); // End of Track.
    final trackBytes = track.toBytes();
    final header = BytesBuilder(copy: false)
      ..add([0x4D, 0x54, 0x68, 0x64]) // MThd
      ..add(_uint32(6))
      ..add([0, 0, 0, 1, 1, 0xE0]) // format 0, 1 track, PPQ 480
      ..add([0x4D, 0x54, 0x72, 0x6B]) // MTrk
      ..add(_uint32(trackBytes.length))
      ..add(trackBytes);
    return header.toBytes();
  }

  static Uint8List renderWav(List<DetectedNote> notes) {
    if (notes.isEmpty) return _encodeWav(Float32List(sampleRate ~/ 2));
    final maxEnd = notes.fold<double>(
      0,
      (old, n) => math.max(old, n.endSeconds),
    );
    final seconds = (maxEnd + 0.15).clamp(0.5, 30.0);
    final pcm = Float32List((seconds * sampleRate).ceil());
    for (final note in notes) {
      final begin = (math.max(0, note.startSeconds) * sampleRate).floor();
      final end = math.min(
        pcm.length,
        (math.min(seconds, note.endSeconds) * sampleRate).ceil(),
      );
      if (begin >= end) continue;
      final duration = (end - begin) / sampleRate;
      final hz = 440 * math.pow(2, (note.midi - 69) / 12);
      for (var i = begin; i < end; i++) {
        final t = (i - begin) / sampleRate;
        final envelope = math.min(
          1.0,
          math.min(t / 0.012, (duration - t) / 0.035),
        ).clamp(0.0, 1.0);
        final phase = 2 * math.pi * hz * t;
        // Gentle two-harmonic tone. This is synthesized MIDI preview,
        // not the original timbre/instrument extracted from a recording.
        pcm[i] += (0.40 * math.sin(phase) +
                0.09 * math.sin(2 * phase)) *
            envelope;
      }
    }
    return _encodeWav(pcm);
  }

  static Uint8List renderOneNote(int midi) => renderWav([
        DetectedNote(
          midi: midi,
          startSeconds: 0,
          endSeconds: 0.7,
          confidence: 1,
        ),
      ]);

  static Uint8List _encodeWav(Float32List pcm) {
    final output = Uint8List(44 + pcm.length * 2);
    final data = ByteData.sublistView(output);
    void label(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        output[offset + i] = s.codeUnitAt(i);
      }
    }

    label(0, 'RIFF');
    data.setUint32(4, output.length - 8, Endian.little);
    label(8, 'WAVE');
    label(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    label(36, 'data');
    data.setUint32(40, pcm.length * 2, Endian.little);
    for (var i = 0; i < pcm.length; i++) {
      final value = pcm[i].clamp(-1.0, 1.0);
      data.setInt16(
        44 + i * 2,
        (value * 32767).round(),
        Endian.little,
      );
    }
    return output;
  }

  static List<int> _uint32(int value) => [
        (value >> 24) & 255,
        (value >> 16) & 255,
        (value >> 8) & 255,
        value & 255,
      ];

  static List<int> _vlq(int value) {
    var remaining = math.max(0, value);
    final buffer = <int>[remaining & 0x7F];
    remaining >>= 7;
    while (remaining > 0) {
      buffer.insert(0, 0x80 | (remaining & 0x7F));
      remaining >>= 7;
    }
    return buffer;
  }
}

class _MidiEvent {
  const _MidiEvent(this.tick, this.priority, this.bytes);
  final int tick;
  final int priority;
  final List<int> bytes;
}
