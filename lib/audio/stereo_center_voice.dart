import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'wav_window_reader.dart';

/// Stereo center band candidate for voice. Not trained separation.
class CenterVoiceRequest {
  const CenterVoiceRequest(this.wav,this.lowpass,this.highpass);
  final Uint8List wav;
  final double lowpass;
  final double highpass;
}

class CenterVoiceChunk {
  const CenterVoiceChunk(this.pcm,this.lowpass,this.highpass);
  final Uint8List pcm;
  final double lowpass;
  final double highpass;
}

class CenterVoiceExporter {
  static CenterVoiceChunk filter(CenterVoiceRequest request) {
    final view=ByteData.sublistView(request.wav);
    final rate=view.getUint32(24,Endian.little);
    final channels=view.getUint16(22,Endian.little);
    if(channels!=2) throw const FormatException('Necessario audio stereo.');
    final frames=(request.wav.length-44)~/4;
    final result=Uint8List(frames*2);
    final out=ByteData.sublistView(result);
    final bassAlpha=1-math.exp(-2*math.pi*145/rate);
    final topAlpha=1-math.exp(-2*math.pi*3900/rate);
    var low=request.lowpass;
    var high=request.highpass;
    for(var i=0;i<frames;i++){
      final left=view.getInt16(44+4*i,Endian.little)/32768;
      final right=view.getInt16(46+4*i,Endian.little)/32768;
      final center=(left+right)*.5;
      low+=bassAlpha*(center-low);
      high+=topAlpha*(center-high);
      // Keep the central midband. Also catches central sax, keys, snare.
      final candidate=(high-low)*1.12;
      final clipped=candidate/(1+.25*candidate.abs());
      out.setInt16(2*i,(clipped.clamp(-1.0,1.0)*32767).round(),
        Endian.little);
    }
    return CenterVoiceChunk(result,low,high);
  }

  static Future<void> export(WavWindowReader source,File target,{
    void Function(double)? progress,
  }) async {
    if(source.channels!=2) throw const FormatException(
      'Solo-voce sperimentale richiede due canali stereo.');
    final writer=await target.open(mode:FileMode.write);
    var pcmLength=0,low=0.0,high=0.0;
    try{
      await writer.writeFrom(Uint8List(44));
      const chunkSeconds=4.0;
      for(var start=0.0;start<source.durationSeconds;start+=chunkSeconds){
        final duration=math.min(chunkSeconds,source.durationSeconds-start);
        final result=await compute(filter,CenterVoiceRequest(
          await source.window(start,duration),low,high));
        low=result.lowpass;
        high=result.highpass;
        await writer.writeFrom(result.pcm);
        pcmLength+=result.pcm.length;
        progress?.call((start+duration)/source.durationSeconds);
      }
      final header=Uint8List(44);
      final v=ByteData.sublistView(header);
      void tag(int pos,String text){
        for(var i=0;i<text.length;i++) header[pos+i]=text.codeUnitAt(i);
      }
      tag(0,'RIFF');tag(8,'WAVE');tag(12,'fmt ');tag(36,'data');
      v.setUint32(4,pcmLength+36,Endian.little);
      v.setUint32(16,16,Endian.little);
      v.setUint16(20,1,Endian.little);
      v.setUint16(22,1,Endian.little);
      v.setUint32(24,source.sampleRate,Endian.little);
      v.setUint32(28,source.sampleRate*2,Endian.little);
      v.setUint16(32,2,Endian.little);
      v.setUint16(34,16,Endian.little);
      v.setUint32(40,pcmLength,Endian.little);
      await writer.setPosition(0);
      await writer.writeFrom(header);
      await writer.flush();
    }finally{
      await writer.close();
    }
  }
}
