import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class StemMixInput {
  const StemMixInput(this.file, {this.gain = 1.0});
  final File file;
  final double gain;
}

/// Lossless PCM-domain stem selection. No MIDI, no pitch tracking, no MP3
/// transcode. Mixes ALL selected real source waveforms in 64-bit arithmetic;
/// outputs 24-bit stereo PCM at the model's ORIGINAL output sample rate.
/// Two passes use a single GLOBAL protective gain to avoid clipping without
/// flattening relative dynamics between time windows.
class StemMixRenderer {
  static const blockFrames = 8192;
  static const maxWavBytes = 0xffffffff - 72;

  static Future<File> export({
    required List<StemMixInput> selected,
    required File output,
    void Function(double)? onProgress,
  }) async {
    if (selected.isEmpty || selected.length > 8) {
      throw const FormatException('Seleziona da 1 a 8 sorgenti.');
    }
    if (selected.any((s) => !s.gain.isFinite ||
        s.gain < 0 || s.gain > 2)) {
      throw const FormatException('Volume sorgente fuori dai limiti.');
    }
    final sources = <_PcmSource>[];
    try {
      for (final input in selected) {
        sources.add(await _PcmSource.open(input.file, input.gain));
      }
      final base = sources.first;
      for (final src in sources.skip(1)) {
        if (src.rate != base.rate || src.channels != base.channels) {
          throw const FormatException(
              'Sorgenti con canali o frequenze differenti. '
              'Riesporta con un campionamento comune.');
        }
      }
      final maxFrames = sources
          .map((src) => src.frames).reduce(math.max);
      final bytes = maxFrames * base.channels * 3;
      if (bytes > maxWavBytes) {
        throw const FormatException(
          'WAV >4 GB: occorre esportare in più segmenti o RF64.');
      }
      if (output.path == selected.first.file.path ||
          selected.any((s) => s.file.path == output.path)) {
        throw const FormatException('Non sovrascrivere una sorgente.');
      }
      if (selected.length == 1 && selected.first.gain == 1.0) {
        // Exact byte-for-byte export, retaining PCM format and metadata.
        await selected.first.file.copy(output.path);
        onProgress?.call(1);
        return output;
      }
      var globalPeak = 0.0;
      var done = 0;
      while (done < maxFrames) {
        final frames = math.min(blockFrames, maxFrames - done);
        final mixed = await _block(sources, done, frames, base.channels);
        for (final v in mixed) {
          if (v.abs() > globalPeak) globalPeak = v.abs();
        }
        done += frames;
        onProgress?.call(.48 * done / maxFrames);
      }
      // Do not normalize all recordings up to 0dB; only protect overs.
      final gain = globalPeak > .985 ? .985 / globalPeak : 1.0;
      final writer = await output.open(mode: FileMode.write);
      try {
        await writer.writeFrom(_waveHeader(
          base.rate, base.channels, 24, bytes));
        done = 0;
        while (done < maxFrames) {
          final frames = math.min(blockFrames, maxFrames - done);
          final mixed = await _block(sources, done, frames, base.channels);
          final pcm = Uint8List(mixed.length * 3);
          for (var i = 0; i < mixed.length; i++) {
            final scaled = (mixed[i] * gain).clamp(-1.0, 1.0);
            final sample = (scaled * 8388607).round();
            final offset = i * 3;
            pcm[offset] = sample & 255;
            pcm[offset + 1] = (sample >> 8) & 255;
            pcm[offset + 2] = (sample >> 16) & 255;
          }
          await writer.writeFrom(pcm);
          done += frames;
          onProgress?.call(.48 + .52 * done / maxFrames);
        }
        await writer.flush();
      } finally {
        await writer.close();
      }
      return output;
    } catch (_) {
      if (await output.exists()) {
        try { await output.delete(); } catch (_) {}
      }
      rethrow;
    } finally {
      for (final source in sources) {
        await source.close();
      }
    }
  }

  static Future<Float64List> _block(
      List<_PcmSource> sources, int from, int frames, int channels) async {
    final sum = Float64List(frames * channels);
    for (final source in sources) {
      if (source.gain == 0 || from >= source.frames) continue;
      final count = math.min(frames, source.frames - from);
      final samples = await source.readFrames(from, count);
      for (var i = 0; i < samples.length; i++) {
        sum[i] += samples[i] * source.gain;
      }
    }
    return sum;
  }

  static Uint8List _waveHeader(
      int sampleRate, int channels, int depth, int dataBytes) {
    final out = Uint8List(44), view = ByteData.sublistView(out);
    void tag(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        out[offset + i] = value.codeUnitAt(i);
      }
    }
    tag(0, 'RIFF'); tag(8, 'WAVE'); tag(12, 'fmt '); tag(36, 'data');
    view.setUint32(4, 36 + dataBytes, Endian.little);
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little);
    view.setUint16(22, channels, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, sampleRate * channels * depth ~/ 8, Endian.little);
    view.setUint16(32, channels * depth ~/ 8, Endian.little);
    view.setUint16(34, depth, Endian.little);
    view.setUint32(40, dataBytes, Endian.little);
    return out;
  }
}

class _PcmSource {
  _PcmSource(this._handle, this.gain, this.rate, this.channels,
      this.depth, this.format, this.dataOffset, this.frames);

  final RandomAccessFile _handle;
  final double gain;
  final int rate, channels, depth, format, dataOffset, frames;
  int get bytesPerSample => depth ~/ 8;

  static Future<_PcmSource> open(File path, double gain) async {
    final handle = await path.open();
    try {
      final size = await handle.length();
      final bytes = Uint8List.fromList(
          await handle.read(math.min(size, 1024 * 1024)));
      if (bytes.length < 44 ||
          String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
          String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
        throw const FormatException('Serve un file audio WAV.');
      }
      final v = ByteData.sublistView(bytes);
      int? fmt, rate, channels, depth, offset, length;
      for (var i = 12; i + 8 <= bytes.length;) {
        final tag = String.fromCharCodes(bytes.sublist(i, i + 4));
        final chunk = v.getUint32(i + 4, Endian.little);
        final at = i + 8;
        if (tag == 'fmt ' && chunk >= 16 && at + 16 <= bytes.length) {
          fmt = v.getUint16(at, Endian.little);
          channels = v.getUint16(at + 2, Endian.little);
          rate = v.getUint32(at + 4, Endian.little);
          depth = v.getUint16(at + 14, Endian.little);
        }
        if (tag == 'data') {
          offset = at;
          length = math.min(chunk, size - at);
          break;
        }
        final next = at + chunk + (chunk.isOdd ? 1 : 0);
        if (next <= i) throw const FormatException('Chunk WAV non valido.');
        i = next;
      }
      if (fmt == null || channels == null || rate == null ||
          depth == null || offset == null || length == null ||
          (channels != 1 && channels != 2) || rate < 8000 ||
          rate > 192000 ||
          !((fmt == 1 && (depth == 16 || depth == 24)) ||
              (fmt == 3 && depth == 32))) {
        throw const FormatException(
          'Supportati PCM 16/24 bit oppure WAV float 32 bit.');
      }
      return _PcmSource(handle, gain, rate, channels, depth, fmt,
          offset, length ~/ (channels * (depth ~/ 8)));
    } catch (_) {
      await handle.close();
      rethrow;
    }
  }

  Future<Float64List> readFrames(int from, int frames) async {
    await _handle.setPosition(
        dataOffset + from * channels * bytesPerSample);
    final raw = await _handle.read(frames * channels * bytesPerSample);
    final result = Float64List(raw.length ~/ bytesPerSample);
    final view = ByteData.sublistView(Uint8List.fromList(raw));
    for (var i = 0; i < result.length; i++) {
      final at = i * bytesPerSample;
      if (format == 3) {
        result[i] = view.getFloat32(at, Endian.little);
      } else if (depth == 24) {
        var signed = raw[at] | (raw[at + 1] << 8) |
            (raw[at + 2] << 16);
        if ((signed & 0x800000) != 0) signed -= 0x1000000;
        result[i] = signed / 8388608.0;
      } else {
        result[i] = view.getInt16(at, Endian.little) / 32768.0;
      }
      if (!result[i].isFinite) {
        throw const FormatException('Campioni PCM non finiti.');
      }
    }
    return result;
  }

  Future<void> close() => _handle.close();
}
