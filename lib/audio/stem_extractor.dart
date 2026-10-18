import 'dart:math' as math;
import 'dart:typed_data';
import 'wav_engine.dart';

/// Experimental local spectral focus tracks. This deliberately does NOT
/// pretend to separate voices/instruments with a trained neural model.
/// Band-pass filters preserve other instruments in the same frequency range.
enum FocusStem {
  bass('Basse frequenze · <240 Hz'),
  middle('Armonia · 240–1300 Hz'),
  treble('Frequenze acute · >1300 Hz'),
  percussion('Transienti acuti · >2000 Hz'),
  vocalCandidate('Fascia vocale candidata · 180–3000 Hz');
  const FocusStem(this.title);
  final String title;
}

class StemRequest {
  const StemRequest(this.wav, this.focus);
  final Uint8List wav;
  final FocusStem focus;
}

class StemExtractor {
  static Uint8List focus(StemRequest request) {
    final audio = WavAudio.decode(request.wav);
    final rate = audio.sampleRate;
    final signal = audio.samples;
    final output = Float32List(signal.length);
    // Three stages for a steeper, inexpensive 18 dB/octave slope.
    List<double> lowPass(List<double> samples, double hz) {
      final alpha = 1 - math.exp(-2 * math.pi * hz / rate);
      final result = List<double>.filled(samples.length, 0);
      var y = 0.0;
      for (var i = 0; i < samples.length; i++) {
        y += alpha * (samples[i] - y);
        result[i] = y;
      }
      return result;
    }

    List<double> highPass(List<double> samples, double hz) {
      final low = lowPass(samples, hz);
      return List<double>.generate(samples.length,
          (i) => samples[i] - low[i]);
    }

    List<double> low3(List<double> s, double hz) =>
      lowPass(lowPass(lowPass(s, hz), hz), hz);
    List<double> high3(List<double> s, double hz) =>
      highPass(highPass(highPass(s, hz), hz), hz);

    final filtered = switch (request.focus) {
      FocusStem.bass => low3(signal, 240),
      FocusStem.middle => low3(high3(signal, 240), 1300),
      FocusStem.treble => high3(signal, 1300),
      FocusStem.percussion => high3(signal, 2000),
      FocusStem.vocalCandidate => low3(high3(signal, 180), 3000),
    };
    for (var i = 0; i < filtered.length; i++) {
      output[i] = filtered[i].clamp(-1.0, 1.0);
    }
    return _wav(output, rate.round());
  }

  static Uint8List _wav(Float32List pcm, int rate) {
    final bytes = Uint8List(44 + 2 * pcm.length);
    final view = ByteData.sublistView(bytes);
    void write(int start, String label) {
      for (var i = 0; i < label.length; i++) {
        bytes[start + i] = label.codeUnitAt(i);
      }
    }
    write(0, 'RIFF');
    view.setUint32(4, bytes.length - 8, Endian.little);
    write(8, 'WAVE');
    write(12, 'fmt ');
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little);
    view.setUint16(22, 1, Endian.little);
    view.setUint32(24, rate, Endian.little);
    view.setUint32(28, rate * 2, Endian.little);
    view.setUint16(32, 2, Endian.little);
    view.setUint16(34, 16, Endian.little);
    write(36, 'data');
    view.setUint32(40, pcm.length * 2, Endian.little);
    for (var i = 0; i < pcm.length; i++) {
      view.setInt16(44 + i * 2,
          (pcm[i].clamp(-1, 1) * 32767).round(), Endian.little);
    }
    return bytes;
  }
}
