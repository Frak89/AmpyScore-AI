import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ampy_score_ai/audio/stem_mix_renderer.dart';

Uint8List wav(int sampleRate, List<double> left,
    List<double> right, {int depth = 16}) {
  if (left.length != right.length) {
    throw ArgumentError('Stereo channel frame mismatch.');
  }
  final bps = depth ~/ 8;
  final pcmBytes = left.length * 2 * bps;
  final out = Uint8List(pcmBytes + 44);
  final view = ByteData.sublistView(out);
  void tag(int start, String label) {
    for (var i = 0; i < label.length; i++) {
      out[start+i] = label.codeUnitAt(i);
    }
  }
  tag(0, 'RIFF'); tag(8, 'WAVE'); tag(12, 'fmt '); tag(36, 'data');
  view.setUint32(4, 36 + pcmBytes, Endian.little);
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little);
  view.setUint16(22, 2, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, sampleRate * 2 * bps, Endian.little);
  view.setUint16(32, 2 * bps, Endian.little);
  view.setUint16(34, depth, Endian.little);
  view.setUint32(40, pcmBytes, Endian.little);
  for (var i = 0; i < left.length; i++) {
    for (var ch = 0; ch < 2; ch++) {
      final value = ch == 0 ? left[i] : right[i];
      final sample = (value * (depth == 16 ? 32767 : 8388607)).round();
      final at = 44 + (i * 2 + ch) * bps;
      out[at] = sample & 255;
      out[at+1] = (sample >> 8) & 255;
      if (depth == 24) out[at+2] = (sample >> 16) & 255;
    }
  }
  return out;
}

double pcm24(Uint8List bytes, int frame, int ch) {
  final at = 44 + frame * 6 + ch * 3;
  var n = bytes[at] | bytes[at+1] << 8 | bytes[at+2] << 16;
  if ((n & 0x800000) != 0) n -= 0x1000000;
  return n / 8388608;
}

void main() {
  test('One AI stem exported bit-for-bit without MIDI or resampling', () async {
    final temp = await Directory.systemTemp.createTemp('ampyscore-pcm');
    try {
      final input = File('${temp.path}/drums.wav');
      final original = wav(44100, [0, .25, -.35, .8], [0, -.25, .35, -.8],
          depth:24);
      await input.writeAsBytes(original);
      final target = File('${temp.path}/solo.wav');
      await StemMixRenderer.export(
        selected: [StemMixInput(input)], output:target);
      expect(await target.readAsBytes(), original);
      expect(await input.readAsBytes(), original);
    } finally {
      await temp.delete(recursive:true);
    }
  });

  test('Selected multi-instrument waveform mix retains stereo and 44.1kHz, avoids clipping', () async {
    final temp = await Directory.systemTemp.createTemp('ampyscore-mix');
    try {
      final count = 1600;
      final bass = File('${temp.path}/bass.wav');
      final drums = File('${temp.path}/drums.wav');
      final samplesL = [for (var i=0;i<count;i++)
        .7*math.sin(2*math.pi*i/20)];
      final samplesR = [for (var i=0;i<count;i++)
        -.45*math.sin(2*math.pi*i/20)];
      await bass.writeAsBytes(wav(44100, samplesL, samplesR));
      await drums.writeAsBytes(wav(44100,
        [for (var i=0;i<count;i++) .55*math.sin(2*math.pi*i/20)],
        [for (var i=0;i<count;i++) .25*math.sin(2*math.pi*i/20)],
        depth:24));
      final originalBass = await bass.readAsBytes();
      final target = File('${temp.path}/mix.wav');
      await StemMixRenderer.export(
        selected: [StemMixInput(bass), StemMixInput(drums)],
        output: target);
      final bytes = await target.readAsBytes();
      final hdr = ByteData.sublistView(bytes);
      expect(hdr.getUint16(22,Endian.little), 2);
      expect(hdr.getUint32(24,Endian.little), 44100);
      expect(hdr.getUint16(34,Endian.little), 24);
      expect(bytes.length, 44 + count * 2 * 3);
      var peak=0.0;
      for(var i=0;i<count;i++){
        peak=math.max(peak,pcm24(bytes,i,0).abs());
        peak=math.max(peak,pcm24(bytes,i,1).abs());
      }
      expect(peak, lessThan(.99));
      expect(pcm24(bytes,5,0), greaterThan(0));
      expect(pcm24(bytes,5,1), lessThan(0));
      expect(await bass.readAsBytes(),originalBass);
    } finally {
      await temp.delete(recursive:true);
    }
  });

  test('Different WAV samplerates rejected instead of silent quality loss', () async {
    final temp=await Directory.systemTemp.createTemp('ampyscore-sr');
    try{
      final f1=File('${temp.path}/bass.wav')
        ..writeAsBytesSync(wav(44100,[.3],[.3]));
      final f2=File('${temp.path}/melody.wav')
        ..writeAsBytesSync(wav(48000,[.4],[.4]));
      await expectLater(
        StemMixRenderer.export(
          selected:[StemMixInput(f1),StemMixInput(f2)],
          output:File('${temp.path}/out.wav')),
        throwsFormatException);
    } finally {
      await temp.delete(recursive:true);
    }
  });

  test('No audio stems selected is rejected, never renders silence', () async {
    final temp=await Directory.systemTemp.createTemp('ampyscore-empty');
    try{
      await expectLater(StemMixRenderer.export(
        selected:[],output:File('${temp.path}/none.wav')),
        throwsFormatException);
    } finally{
      await temp.delete(recursive:true);
    }
  });
}
