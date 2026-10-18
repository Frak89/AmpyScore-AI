import 'dart:math' as math;
import 'dart:typed_data';

import 'wav_engine.dart';

/// Experimental signal-processing voice grouping, NOT trained instrument ID.
enum InstrumentFamily { bass, harmony, melody, drums }

class InstrumentPart {
  const InstrumentPart({
    required this.family,
    required this.notes,
    required this.confidence,
    this.programOverride,
  });

  final InstrumentFamily family;
  final List<DetectedNote> notes;
  final double confidence;
  final int? programOverride;

  String get id => family.name;
  String get name => switch (family) {
        InstrumentFamily.bass => 'Basso (stima)',
        InstrumentFamily.harmony => 'Tastiera / armonia (stima)',
        InstrumentFamily.melody => 'Melodia acuta (stima)',
        InstrumentFamily.drums => 'Percussioni (transienti)',
      };
  int get midiChannel => switch (family) {
        InstrumentFamily.bass => 1,
        InstrumentFamily.harmony => 2,
        InstrumentFamily.melody => 0,
        InstrumentFamily.drums => 9,
      };
  int get midiProgram => programOverride ?? switch (family) {
        InstrumentFamily.bass => 32, // Acoustic bass.
        InstrumentFamily.harmony => 0,
        InstrumentFamily.melody => 65, // General MIDI alto sax, changeable in Tracks.
        InstrumentFamily.drums => 0,
      };
  bool get percussion => family == InstrumentFamily.drums;
}

class MultiTrackResult {
  const MultiTrackResult(this.parts, this.durationSeconds);

  final List<InstrumentPart> parts;
  final double durationSeconds;
  bool get hasNotes => parts.any((p) => p.notes.isNotEmpty);
  List<DetectedNote> get allNotes =>
      [for (final part in parts) ...part.notes];
}

/// Low-cost spectral peak tracking on a single mixed WAV, divided into
/// frequency families. It does NOT separate real instruments or identify
/// instrument timbres. Can create false harmonic/duplicated notes.
class MultiTrackAnalyzer {
  static const int _fftSize = 2048;
  static const int _bins = _fftSize ~/ 2;
  static const double _hopSeconds = 0.07;

  static MultiTrackResult analyze(Uint8List bytes) {
    final audio = WavAudio.decode(bytes); // One bounded PCM window supplied by the timeline analyzer.
    final rate = audio.sampleRate;
    final samples = audio.samples;
    final duration = samples.length / rate;
    final hop = math.max(1, (rate * _hopSeconds).round());
    final frames = <_Frame>[];
    final window = Float64List(_fftSize);
    final cosT = Float64List(_fftSize);
    for (var n = 0; n < _fftSize; n++) {
      window[n] = 0.5 * (1 - math.cos(2 * math.pi * n / (_fftSize - 1)));
    }
    if (samples.length < _fftSize) {
      return MultiTrackResult(const [], duration);
    }

    Float64List? previousSpectrum;
    var previousHigh = 0.0;
    for (var start = 0; start + _fftSize <= samples.length; start += hop) {
      var energy = 0.0;
      for (var i = 0; i < _fftSize; i++) {
        final v = samples[start + i];
        cosT[i] = v * window[i];
        energy += v * v;
      }
      final rms = math.sqrt(energy / _fftSize);
      final spec = _magnitudeSpectrum(cosT);
      final centerTime = (start + _fftSize / 2) / rate;
      final bass = _dominant(spec, rate, 39, 55, rms);
      final middle = _dominant(spec, rate, 56, 69, rms);
      final high = _dominant(spec, rate, 70, 85, rms);
      var highEnergy = 0.0;
      var flux = 0.0;
      final highFrom = math.min(_bins - 1, (1400 * _fftSize / rate).floor());
      for (var i = highFrom; i < _bins; i++) {
        highEnergy += spec[i];
        if (previousSpectrum != null) {
          flux += math.max(0, spec[i] - previousSpectrum[i]);
        }
      }
      // Broadband transient, not guaranteed to be a drum onset.
      final transient = previousSpectrum != null &&
          rms > 0.023 &&
          flux > 16 &&
          highEnergy > 2.1 * previousHigh &&
          flux > highEnergy * 0.42;
      frames.add(_Frame(centerTime, bass, middle, high, transient, rms));
      previousSpectrum = spec;
      previousHigh = highEnergy;
    }

    final bassNotes = _buildLane(frames, (f) => f.bass, duration);
    final harmonyNotes = _buildLane(frames, (f) => f.harmony, duration);
    final melodyNotes = _buildLane(frames, (f) => f.melody, duration);
    final drumNotes = <DetectedNote>[];
    var lastHit = -1.0;
    for (final f in frames) {
      if (!f.transient || f.time - lastHit < 0.23) continue;
      drumNotes.add(DetectedNote(
        midi: 38, // GM snare: provisional unpitched onset label.
        startSeconds: math.max(0, f.time - 0.07),
        endSeconds: math.min(duration, f.time + 0.09),
        confidence: 0.5,
      ));
      lastHit = f.time;
    }

    final candidateParts = [
      InstrumentPart(
        family: InstrumentFamily.bass,
        notes: bassNotes,
        confidence: 0.60,
      ),
      InstrumentPart(
        family: InstrumentFamily.harmony,
        notes: harmonyNotes,
        confidence: 0.43,
      ),
      InstrumentPart(
        family: InstrumentFamily.melody,
        notes: melodyNotes,
        confidence: 0.54,
      ),
      InstrumentPart(
        family: InstrumentFamily.drums,
        notes: drumNotes,
        confidence: 0.35,
      ),
    ];
    return MultiTrackResult(
      candidateParts.where((part) => part.notes.isNotEmpty).toList(),
      duration,
    );
  }

  static List<DetectedNote> _buildLane(
    List<_Frame> frames,
    _Pitch? Function(_Frame) select,
    double totalDuration,
  ) {
    final notes = <DetectedNote>[];
    int? active;
    var onset = 0.0;
    var lastTime = 0.0;
    var sums = 0.0;
    var count = 0;

    void close(double end) {
      if (active != null && count >= 2 && end - onset >= 0.14 &&
          notes.length < 100000) {
        notes.add(DetectedNote(
          midi: active,
          startSeconds: math.max(0, onset - 0.04),
          endSeconds: math.min(totalDuration, end),
          confidence: (sums / count).clamp(0.0, 1.0).toDouble(),
        ));
      }
    }

    for (final frame in frames) {
      final candidate = select(frame);
      final midi = candidate?.midi;
      if (midi != active) {
        close(frame.time);
        active = midi;
        onset = frame.time;
        count = 0;
        sums = 0;
      }
      if (midi != null) {
        count++;
        lastTime = frame.time;
        sums += candidate!.quality;
      }
    }
    close(lastTime + _hopSeconds);
    return notes;
  }

  static _Pitch? _dominant(
    Float64List spectrum,
    double rate,
    int low,
    int high,
    double rms,
  ) {
    if (rms < 0.016) return null;
    final candidates = <_Pitch>[];
    var maxInBand = 0.0;
    for (var midi = low; midi <= high; midi++) {
      final frequency = 440 * math.pow(2, (midi - 69) / 12);
      final bin = frequency * _fftSize / rate;
      final fundamental = _peak(spectrum, bin);
      maxInBand = math.max(maxInBand, fundamental);
      // Favor true fundamental, not a low-frequency subharmonic: small
      // reinforcement only from harmonics.
      var harmonics = 0.0;
      for (var n = 2; n <= 4; n++) {
        if (bin * n >= _bins - 2) break;
        harmonics += _peak(spectrum, bin * n) / (n * n);
      }
      final value = fundamental + harmonics * 0.14;
      candidates.add(_Pitch(midi, value, fundamental));
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final best = candidates.first;
    if (best.fundamental < 4.0 || best.fundamental < maxInBand * 0.58) {
      return null;
    }
    // Reject broad noise by checking whether the pitch bin is a sharp peak.
    final freq = 440 * math.pow(2, (best.midi - 69) / 12);
    final bin = freq * _fftSize / rate;
    final local = spectrum[math.max(1, bin.floor())];
    final broad = (spectrum[math.max(1, bin.floor() - 5)] +
            spectrum[math.min(_bins - 1, bin.floor() + 5)]) /
        2;
    if (local < broad * 1.6 && best.fundamental < broad * 2) {
      return null;
    }
    final quality = (best.fundamental / (best.fundamental + 8))
        .clamp(0.0, 1.0).toDouble();
    return _Pitch(best.midi, best.score, best.fundamental, quality);
  }

  static double _peak(Float64List spec, double center) {
    final bin = center.round();
    var peak = 0.0;
    for (var i = math.max(1, bin - 1);
        i <= math.min(_bins - 1, bin + 1);
        i++) {
      peak = math.max(peak, spec[i]);
    }
    return peak;
  }

  static Float64List _magnitudeSpectrum(Float64List input) {
    final real = Float64List.fromList(input);
    final imag = Float64List(_fftSize);
    var j = 0;
    for (var i = 1; i < _fftSize; i++) {
      var bit = _fftSize >> 1;
      while (j & bit != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j ^= bit;
      if (i < j) {
        final t = real[i];
        real[i] = real[j];
        real[j] = t;
      }
    }
    for (var len = 2; len <= _fftSize; len <<= 1) {
      final angle = -2 * math.pi / len;
      final wRe = math.cos(angle);
      final wIm = math.sin(angle);
      for (var i = 0; i < _fftSize; i += len) {
        var xRe = 1.0;
        var xIm = 0.0;
        for (var k = 0; k < len ~/ 2; k++) {
          final top = i + k;
          final bottom = top + len ~/ 2;
          final tRe = real[bottom] * xRe - imag[bottom] * xIm;
          final tIm = real[bottom] * xIm + imag[bottom] * xRe;
          final aRe = real[top];
          final aIm = imag[top];
          real[top] = aRe + tRe;
          imag[top] = aIm + tIm;
          real[bottom] = aRe - tRe;
          imag[bottom] = aIm - tIm;
          final nextRe = xRe * wRe - xIm * wIm;
          xIm = xRe * wIm + xIm * wRe;
          xRe = nextRe;
        }
      }
    }
    final result = Float64List(_bins);
    for (var i = 0; i < _bins; i++) {
      result[i] = math.sqrt(real[i] * real[i] + imag[i] * imag[i]);
    }
    return result;
  }
}

class _Frame {
  const _Frame(
    this.time,
    this.bass,
    this.harmony,
    this.melody,
    this.transient,
    this.rms,
  );
  final double time;
  final _Pitch? bass;
  final _Pitch? harmony;
  final _Pitch? melody;
  final bool transient;
  final double rms;
}

class _Pitch {
  const _Pitch(this.midi, this.score, this.fundamental, [this.quality = 0.5]);
  final int midi;
  final double score;
  final double fundamental;
  final double quality;
}

/// Demo purposefully synthesizes separate pitch registers plus noisy hits.
/// This is controlled audio, NOT a guarantee of real-song instrument recognition.
class MultiInstrumentDemo {
  static Uint8List create() {
    const rate = 16000;
    const beats = 16;
    const beatSeconds = 0.52;
    const totalSeconds = beats * beatSeconds + 0.3;
    final count = (rate * totalSeconds).ceil();
    final pcm = Float32List(count);
    const bass = [48, 43, 45, 41];
    const harmony = [60, 62, 64, 65];
    const melody = [72, 74, 76, 79, 79, 76, 74, 72];
    void pitched(int midi, double startSeconds, double duration, double gain,
        double secondHarmonic) {
      final from = (startSeconds * rate).floor();
      final length = (duration * rate).floor();
      final hz = 440 * math.pow(2, (midi - 69) / 12);
      for (var k = 0; k < length && from + k < count; k++) {
        final t = k / rate;
        final env = math.min(1.0,
            math.min(t / 0.014, (duration - t) / 0.035)).clamp(0.0, 1.0);
        pcm[from + k] += gain * env *
            (math.sin(2 * math.pi * hz * t) +
             secondHarmonic * math.sin(4 * math.pi * hz * t));
      }
    }

    for (var beat = 0; beat < beats; beat++) {
      final at = beat * beatSeconds;
      // Separate registers, each group has a different synth character.
      pitched(bass[(beat ~/ 4) % bass.length], at, 0.43, 0.27, 0.16);
      pitched(harmony[(beat ~/ 4) % harmony.length], at, 0.41, 0.16, 0.02);
      pitched(melody[(beat ~/ 2) % melody.length], at, 0.42, 0.29, 0.25);
      if (beat.isOdd) {
        var state = (beat + 51) * 7919;
        const hitDuration = 0.085;
        final from = (at * rate).round();
        for (var k = 0; k < (hitDuration * rate).floor(); k++) {
          state = (state * 1103515245 + 12345) & 0x7fffffff;
          final noise = state / 1073741824.0 - 1.0;
          final env = math.exp(-55 * k / rate);
          pcm[from + k] += 0.17 * noise * env;
        }
      }
    }
    // Export to 16-bit PCM WAV for the v0.1/0.2 shared audio player.
    final bytes = Uint8List(44 + count * 2);
    final bd = ByteData.sublistView(bytes);
    void tag(int index, String name) {
      for (var i = 0; i < name.length; i++) {
        bytes[index + i] = name.codeUnitAt(i);
      }
    }
    tag(0, 'RIFF');
    bd.setUint32(4, bytes.length - 8, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);
    bd.setUint16(22, 1, Endian.little);
    bd.setUint32(24, rate, Endian.little);
    bd.setUint32(28, rate * 2, Endian.little);
    bd.setUint16(32, 2, Endian.little);
    bd.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    bd.setUint32(40, count * 2, Endian.little);
    for (var k = 0; k < count; k++) {
      bd.setInt16(44 + k * 2,
          (pcm[k].clamp(-0.93, 0.93) * 32767).round(), Endian.little);
    }
    return bytes;
  }
}
