import 'dart:math' as math;
import 'dart:typed_data';

/// A supported WAV file: little-endian, 16-bit linear PCM, 1 or 2 channels.
class WavAudio {
  const WavAudio(this.sampleRate, this.samples);

  final double sampleRate;
  final List<double> samples;

  factory WavAudio.decode(Uint8List bytes) {
    if (bytes.length < 44 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('File WAV RIFF non valido.');
    }
    final data = ByteData.sublistView(bytes);
    int offset = 12;
    int? sampleRate;
    int? channels;
    int? bitDepth;
    int? format;
    int? payloadOffset;
    int? payloadLength;

    while (offset + 8 <= bytes.length) {
      final tag = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size = data.getUint32(offset + 4, Endian.little);
      final start = offset + 8;
      if (size > bytes.length - start) {
        throw const FormatException('Chunk WAV troncato.');
      }
      if (tag == 'fmt ') {
        if (size < 16) {
          throw const FormatException('Formato WAV incompleto.');
        }
        format = data.getUint16(start, Endian.little);
        channels = data.getUint16(start + 2, Endian.little);
        sampleRate = data.getUint32(start + 4, Endian.little);
        bitDepth = data.getUint16(start + 14, Endian.little);
      } else if (tag == 'data') {
        payloadOffset = start;
        payloadLength = size;
      }
      offset = start + size + (size.isOdd ? 1 : 0);
    }

    if (format != 1 ||
        bitDepth != 16 ||
        channels == null ||
        (channels != 1 && channels != 2) ||
        sampleRate == null ||
        sampleRate < 4000 ||
        sampleRate > 192000 ||
        payloadOffset == null ||
        payloadLength == null) {
      throw const FormatException(
        'Formato non supportato: serve WAV PCM 16-bit mono o stereo.',
      );
    }

    final frameBytes = channels * 2;
    final frames = payloadLength ~/ frameBytes;
    if (frames == 0) {
      throw const FormatException('File audio vuoto.');
    }

    // Limit CPU and memory on mobile by decimating to approximately 8 kHz.
    // A production version will replace this with an anti-aliasing resampler.
    final stride = math.max(1, (sampleRate / 8000).floor());
    final effectiveRate = sampleRate / stride;
    final maxFrames = math.min(frames, sampleRate * 40);
    final out = <double>[];
    for (var i = 0; i < maxFrames; i += stride) {
      var value = 0.0;
      final frameStart = payloadOffset + i * frameBytes;
      for (var ch = 0; ch < channels; ch++) {
        value += data.getInt16(frameStart + ch * 2, Endian.little) / 32768.0;
      }
      out.add(value / channels);
    }
    return WavAudio(effectiveRate, out);
  }
}

class DetectedNote {
  const DetectedNote({
    required this.midi,
    required this.startSeconds,
    required this.endSeconds,
    required this.confidence,
  });

  final int midi;
  final double startSeconds;
  final double endSeconds;
  final double confidence;

  static const _names = [
    'Do', 'Do♯', 'Re', 'Re♯', 'Mi', 'Fa',
    'Fa♯', 'Sol', 'Sol♯', 'La', 'La♯', 'Si',
  ];

  String get label => '${_names[midi % 12]}${midi ~/ 12 - 1}';
  double get durationSeconds => endSeconds - startSeconds;
}

/// Deterministic on-device DSP baseline (YIN-like difference + CMND).
/// This is not trained AI, polyphonic transcription or instrument separation.
class WavTranscriber {
  static List<DetectedNote> transcribe(Uint8List bytes) {
    final wave = WavAudio.decode(bytes);
    final samples = wave.samples;
    final rate = wave.sampleRate;
    const frameLength = 1024;
    final minLag = math.max(2, (rate / 1100).floor());
    final maxLag = (rate / 80).ceil();
    final hop = math.max(1, (rate * 0.09).round());
    if (samples.length < frameLength + maxLag) return const [];

    final results = <DetectedNote>[];
    int? active;
    var onset = 0.0;
    var previous = 0.0;
    var confidenceSum = 0.0;
    var frames = 0;

    void flush(double end) {
      if (active != null && frames >= 2 && end - onset >= 0.13) {
        results.add(DetectedNote(
          midi: active!,
          startSeconds: onset,
          endSeconds: end,
          confidence: (confidenceSum / frames).clamp(0.0, 1.0),
        ));
      }
    }

    for (var start = 0;
        start + frameLength + maxLag <= samples.length && results.length < 128;
        start += hop) {
      final time = (start + frameLength / 2) / rate;
      var energy = 0.0;
      for (var i = 0; i < frameLength; i++) {
        final x = samples[start + i];
        energy += x * x;
      }
      final rms = math.sqrt(energy / frameLength);
      int? midi;
      var confidence = 0.0;

      if (rms > 0.02) {
        final difference = List<double>.filled(maxLag + 1, 0);
        final cmnd = List<double>.filled(maxLag + 1, 1);
        var rolling = 0.0;
        for (var lag = 1; lag <= maxLag; lag++) {
          var sum = 0.0;
          for (var i = 0; i < frameLength; i++) {
            final delta = samples[start + i] - samples[start + i + lag];
            sum += delta * delta;
          }
          difference[lag] = sum;
          rolling += sum;
          cmnd[lag] = rolling > 0 ? sum * lag / rolling : 1.0;
        }

        var candidate = -1;
        for (var lag = minLag; lag <= maxLag; lag++) {
          if (cmnd[lag] < 0.17) {
            while (lag < maxLag && cmnd[lag + 1] < cmnd[lag]) {
              lag++;
            }
            candidate = lag;
            break;
          }
        }
        if (candidate > 0) {
          var refined = candidate.toDouble();
          if (candidate > 1 && candidate < maxLag) {
            final left = cmnd[candidate - 1];
            final center = cmnd[candidate];
            final right = cmnd[candidate + 1];
            final denominator = left - 2 * center + right;
            if (denominator.abs() > 1e-9) {
              refined += (0.5 * (left - right) / denominator).clamp(-0.5, 0.5);
            }
          }
          final hz = rate / refined;
          final m = (69 + 12 * math.log(hz / 440) / math.ln2).round();
          confidence = (1 - cmnd[candidate]).clamp(0.0, 1.0);
          if (m >= 40 && m <= 84 && confidence > 0.75) {
            midi = m;
          }
        }
      }

      if (midi != active) {
        flush(time);
        active = midi;
        onset = time;
        confidenceSum = 0;
        frames = 0;
      }
      if (midi != null) {
        previous = time;
        confidenceSum += confidence;
        frames++;
      }
    }
    flush(previous + hop / rate);
    return results;
  }
}

/// Small offline demo WAV, deliberately monophonic and generated in memory.
class DemoWav {
  static Uint8List create() {
    const rate = 16000;
    const noteSeconds = 0.48;
    const gapSeconds = 0.09;
    const midis = [60, 62, 64, 67, 67, 64, 62, 60];
    final segmentSamples = ((noteSeconds + gapSeconds) * rate).round();
    final toneSamples = (noteSeconds * rate).round();
    final sampleCount = midis.length * segmentSamples;
    final byteCount = 44 + sampleCount * 2;
    final bytes = Uint8List(byteCount);
    final view = ByteData.sublistView(bytes);

    void str(int at, String s) {
      for (var i = 0; i < s.length; i++) {
        bytes[at + i] = s.codeUnitAt(i);
      }
    }

    str(0, 'RIFF');
    view.setUint32(4, byteCount - 8, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little);
    view.setUint16(22, 1, Endian.little);
    view.setUint32(24, rate, Endian.little);
    view.setUint32(28, rate * 2, Endian.little);
    view.setUint16(32, 2, Endian.little);
    view.setUint16(34, 16, Endian.little);
    str(36, 'data');
    view.setUint32(40, sampleCount * 2, Endian.little);

    for (var i = 0; i < sampleCount; i++) {
      final midi = midis[i ~/ segmentSamples];
      final k = i % segmentSamples;
      var amplitude = 0.0;
      if (k < toneSamples) {
        final seconds = k / rate;
        final release = (toneSamples - k) / (0.025 * rate);
        final attack = seconds / 0.015;
        final envelope = math.min(1.0, math.min(attack, release));
        final freq = 440 * math.pow(2, (midi - 69) / 12);
        amplitude = 0.62 *
            envelope *
            (math.sin(2 * math.pi * freq * seconds) +
                0.14 * math.sin(4 * math.pi * freq * seconds));
      }
      view.setInt16(44 + i * 2, (amplitude * 32767).round(), Endian.little);
    }
    return bytes;
  }
}
