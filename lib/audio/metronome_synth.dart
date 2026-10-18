import 'dart:math' as math;
import 'dart:typed_data';

class MetronomeSettings {
  const MetronomeSettings({
    required this.bpm,
    required this.subdivisions,
    required this.durationSeconds,
    this.beatsPerBar = 4,
    this.startSeconds = 0,
  });

  final int bpm;
  /// 1 = quarter click, 2 = eighth, 4 = sixteenth, 8 = thirty-second.
  final int subdivisions;
  final double durationSeconds;
  final int beatsPerBar;
  final double startSeconds;
}

/// Generate a full WAV click track and play from the same seek position as
/// the source player. This avoids jitter from Dart Timer-driven short sounds.
class MetronomeSynth {
  static Uint8List render(MetronomeSettings settings) {
    const sampleRate = 16000;
    final bpm = settings.bpm.clamp(40, 240);
    final divisions = settings.subdivisions.clamp(1, 8);
    final duration = settings.durationSeconds.clamp(0.01, 30.0);
    final count = (duration * sampleRate).ceil();
    final pcm = Float32List(count);
    final interval = 60.0 / (bpm * divisions);
    var click = (settings.startSeconds / interval).ceil();
    while (true) {
      final begin = ((click * interval - settings.startSeconds) * sampleRate).round();
      if (begin >= count) break;
      final accent = (click % (settings.beatsPerBar * divisions)) == 0;
      final beat = click % divisions == 0;
      final hz = accent ? 1320.0 : (beat ? 940.0 : 610.0);
      final amp = accent ? 0.62 : (beat ? 0.4 : 0.23);
      final length = math.min(count - begin, (sampleRate * 0.035).round());
      for (var i = 0; i < length; i++) {
        final t = i / sampleRate;
        final decay = math.exp(-95 * t);
        pcm[begin + i] += amp * decay *
            math.sin(2 * math.pi * hz * t);
      }
      click++;
    }

    final data = Uint8List(44 + count * 2);
    final view = ByteData.sublistView(data);
    void put(int offset, String word) {
      for (var i = 0; i < word.length; i++) {
        data[offset + i] = word.codeUnitAt(i);
      }
    }
    put(0, 'RIFF');
    view.setUint32(4, data.length - 8, Endian.little);
    put(8, 'WAVE');
    put(12, 'fmt ');
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little);
    view.setUint16(22, 1, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, sampleRate * 2, Endian.little);
    view.setUint16(32, 2, Endian.little);
    view.setUint16(34, 16, Endian.little);
    put(36, 'data');
    view.setUint32(40, count * 2, Endian.little);
    for (var i = 0; i < count; i++) {
      view.setInt16(44 + 2 * i,
          (pcm[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    }
    return data;
  }
}
