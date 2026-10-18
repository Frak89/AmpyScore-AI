import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'wav_window_reader.dart';

/// Spatial center cancellation, not neural source separation. Works only
/// when the source has two channels and centered material is correlated.
class VocalChunkRequest {
  const VocalChunkRequest(this.wav, this.strength, this.bassMemory,
      this.gainMemory);
  final Uint8List wav;
  final double strength;
  final double bassMemory;
  final double gainMemory;
}

class VocalChunkResult {
  const VocalChunkResult(this.pcm, this.bassMemory, this.gainMemory,
      this.originalRms, this.outputRms);
  final Uint8List pcm;
  final double bassMemory;
  final double gainMemory;
  final double originalRms;
  final double outputRms;
}

class StereoVocalReducer {
  /// Returns only stereo PCM bytes, preserving filter and gain state between
  /// windows. Apply it in a background isolate via compute().
  static VocalChunkResult process(VocalChunkRequest request) {
    final bytes = request.wav;
    if (bytes.length < 44) throw const FormatException('WAV vuoto.');
    final view = ByteData.sublistView(bytes);
    final channels = view.getUint16(22, Endian.little);
    final sampleRate = view.getUint32(24, Endian.little);
    if (channels != 2 || sampleRate < 8000) {
      throw const FormatException(
          'Riduzione vocale disponibile soltanto per file stereo.');
    }
    final frames = (bytes.length - 44) ~/ 4;
    final out = Uint8List(frames * 4);
    final dst = ByteData.sublistView(out);
    final amount = request.strength.clamp(0.0, 1.0);
    // Preserve centered bass (<120Hz) while reducing central vocals.
    final alpha = 1 - math.exp(-2 * math.pi * 120 / sampleRate);
    var bass = request.bassMemory;
    var totalInput = 1e-6, totalOutput = 1e-6;
    for (var i = 0; i < frames; i++) {
      final left = view.getInt16(44 + 4 * i, Endian.little) / 32768.0;
      final right = view.getInt16(46 + 4 * i, Endian.little) / 32768.0;
      final center = (left + right) * 0.5;
      bass += alpha * (center - bass);
      final side = (left - right) * 0.5;
      // Mix between the unprocessed source and L-R cancellation.
      final baseL = side + bass;
      // Duplicate side to both output channels so phone speakers or
      // mono Bluetooth devices do not cancel the entire instrumental.
      final baseR = side + bass;
      final resultL = left * (1 - amount) + baseL * amount;
      final resultR = right * (1 - amount) + baseR * amount;
      totalInput += left * left + right * right;
      totalOutput += resultL * resultL + resultR * resultR;
    }
    final targetGain = math.sqrt(totalInput / totalOutput).clamp(.75, 2.35);
    final finalGain = (request.gainMemory * .6 + targetGain * .4)
        .clamp(.75, 2.35);
    // Second pass applies a stable segment gain and soft limiter. Avoids
    // blindly normalizing every chunk to peak level.
    bass = request.bassMemory;
    for (var i = 0; i < frames; i++) {
      final left = view.getInt16(44 + 4 * i, Endian.little) / 32768.0;
      final right = view.getInt16(46 + 4 * i, Endian.little) / 32768.0;
      final center = (left + right) * 0.5;
      bass += alpha * (center - bass);
      final side = (left - right) * 0.5;
      final l = (left * (1 - amount) + (side + bass) * amount) * finalGain;
      final r = (right * (1 - amount) + (side + bass) * amount) * finalGain;
      double limit(double v) {
        final x = v.abs();
        final excess = x - .90;
        final value = x <= .90 ? v :
            (v.isNegative ? -1 : 1) * (.90 + .1 * excess / (.1 + excess));
        return value.clamp(-1.0, 1.0);
      }
      dst.setInt16(4 * i, (limit(l) * 32767).round(), Endian.little);
      dst.setInt16(4 * i + 2, (limit(r) * 32767).round(), Endian.little);
    }
    return VocalChunkResult(out, bass, finalGain,
        math.sqrt(totalInput / math.max(1, frames * 2)),
        math.sqrt(totalOutput / math.max(1, frames * 2)) * finalGain);
  }

  static Future<void> export(
    WavWindowReader source, File destination, {
    double strength = .87,
    void Function(double)? progress,
  }) async {
    if (source.channels != 2) {
      throw const FormatException('La traccia originale non è stereo.');
    }
    final output = await destination.open(mode: FileMode.write);
    var bytesWritten = 0, bassMemory = 0.0, gainMemory = 1.0;
    try {
      await output.writeFrom(Uint8List(44));
      const chunkSeconds = 3.0;
      var firstChunk = true;
      for (var start = 0.0; start < source.durationSeconds;
          start += chunkSeconds) {
        final seconds = math.min(
            chunkSeconds, source.durationSeconds - start);
        final data = await source.window(start, seconds);
        if (firstChunk) {
          firstChunk = false;
          final view = ByteData.sublistView(data);
          final frames = (data.length - 44) ~/ 4;
          var stereoEnergy = 0.0, totalEnergy = 1e-9;
          for (var i = 0; i < frames; i += 7) {
            final l = view.getInt16(44 + i * 4, Endian.little).toDouble();
            final r = view.getInt16(46 + i * 4, Endian.little).toDouble();
            stereoEnergy += (l - r) * (l - r);
            totalEnergy += (l + r) * (l + r);
          }
          if (totalEnergy > 5e5 &&
              stereoEnergy / totalEnergy < 0.00002) {
            throw const FormatException(
              'Canali stereo quasi identici: '
              'riduzione vocale non applicabile.');
          }
        }
        final result = await compute(process,
            VocalChunkRequest(data, strength, bassMemory, gainMemory));
        bassMemory = result.bassMemory;
        gainMemory = result.gainMemory;
        await output.writeFrom(result.pcm);
        bytesWritten += result.pcm.length;
        progress?.call(math.min(1.0,
            (start + seconds) / source.durationSeconds));
      }
      final head = Uint8List(44);
      final v = ByteData.sublistView(head);
      void word(int pos, String value) {
        for (var i = 0; i < value.length; i++) {
          head[pos + i] = value.codeUnitAt(i);
        }
      }
      word(0, 'RIFF'); word(8, 'WAVE'); word(12, 'fmt ');
      word(36, 'data');
      v.setUint32(4, 36 + bytesWritten, Endian.little);
      v.setUint32(16, 16, Endian.little);
      v.setUint16(20, 1, Endian.little);
      v.setUint16(22, 2, Endian.little);
      v.setUint32(24, source.sampleRate, Endian.little);
      v.setUint32(28, source.sampleRate * 4, Endian.little);
      v.setUint16(32, 4, Endian.little);
      v.setUint16(34, 16, Endian.little);
      v.setUint32(40, bytesWritten, Endian.little);
      await output.setPosition(0);
      await output.writeFrom(head);
      await output.flush();
    } finally {
      await output.close();
    }
  }
}
