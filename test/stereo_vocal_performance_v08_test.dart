import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ampy_score_ai/audio/stereo_vocal_reducer.dart';
import 'package:ampy_score_ai/audio/band_focus_renderer.dart';
import 'package:ampy_score_ai/audio/instrument_heuristics.dart';
import 'package:ampy_score_ai/audio/stem_extractor.dart';
import 'package:ampy_score_ai/audio/wav_window_reader.dart';
import 'package:ampy_score_ai/audio/multitrack_engine.dart';
import 'package:ampy_score_ai/audio/wav_engine.dart';

Uint8List fakeStereo({
  int sampleRate = 16000,
  double seconds = 1.5,
  bool stereoSides = true,
}) {
  final count = (sampleRate * seconds).floor();
  final bytes = Uint8List(44 + count * 4);
  final bd = ByteData.sublistView(bytes);
  void word(int at, String name) {
    for (var i = 0; i < name.length; i++) {
      bytes[at + i] = name.codeUnitAt(i);
    }
  }
  word(0,'RIFF'); word(8,'WAVE'); word(12,'fmt '); word(36,'data');
  bd.setUint32(4, bytes.length - 8, Endian.little);
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20,1,Endian.little);
  bd.setUint16(22,2,Endian.little);
  bd.setUint32(24,sampleRate,Endian.little);
  bd.setUint32(28,sampleRate * 4,Endian.little);
  bd.setUint16(32,4,Endian.little);
  bd.setUint16(34,16,Endian.little);
  bd.setUint32(40,count * 4,Endian.little);
  for(var i=0;i<count;i++){
    final t=i/sampleRate;
    final voice=.55*math.sin(2*math.pi*440*t);
    final guitar=stereoSides?.3*math.sin(2*math.pi*660*t):0.0;
    bd.setInt16(44+4*i,((voice+guitar)*32767).round(),Endian.little);
    bd.setInt16(46+4*i,(voice*32767).round(),Endian.little);
  }
  return bytes;
}

double bandEnergy(Uint8List bytes,int sampleRate,int hz) {
  final bd=ByteData.sublistView(bytes);
  final frames=(bytes.length-44)~/4;
  var cosPart=0.0,sinPart=0.0;
  for(var i=0;i<frames;i++){
    final l=bd.getInt16(44+4*i,Endian.little)/32768;
    final r=bd.getInt16(46+4*i,Endian.little)/32768;
    final v=(l+r)*.5;
    final phase=2*math.pi*hz*i/sampleRate;
    cosPart+=v*math.cos(phase);
    sinPart+=v*math.sin(phase);
  }
  return math.sqrt(cosPart*cosPart+sinPart*sinPart)/frames;
}

void main(){
  test('Stereo processing reduces centered vocals but retains panned music',(){
    final src=fakeStereo();
    final out=StereoVocalReducer.process(
      VocalChunkRequest(src,.90,0,1));
    final processed=Uint8List(src.length);
    processed.setRange(0,44,src);
    processed.setRange(44,processed.length,out.pcm);
    final before440=bandEnergy(src,16000,440);
    final after440=bandEnergy(processed,16000,440);
    final before660=bandEnergy(src,16000,660);
    final after660=bandEnergy(processed,16000,660);
    expect(after440,lessThan(before440*.5));
    expect(after660,greaterThan(before660*.55));
    expect(out.outputRms,greaterThan(0));
  });

  test('Stereo vocal reduction and full-length band filter remain on disk',
      () async {
    final folder=await Directory.systemTemp.createTemp('ampyscore-stereo');
    try{
      final input=File('${folder.path}/input.wav');
      await input.writeAsBytes(fakeStereo(seconds:3.5));
      final reader=await WavWindowReader.open(input);
      final output=File('${folder.path}/karaoke.wav');
      await StereoVocalReducer.export(reader,output);
      final result=await WavWindowReader.open(output);
      expect(result.channels,2);
      expect(result.durationSeconds,closeTo(3.5,.01));
      final target=File('${folder.path}/focus.wav');
      await BandFocusRenderer.export(reader,target,FocusStem.bass);
      final wave=await WavWindowReader.open(target);
      expect(wave.channels,1);
      expect(wave.durationSeconds,closeTo(3.5,.03));
    } finally{
      await folder.delete(recursive:true);
    }
  });

  test('Automatic instrument choices are labeled heuristic, not AI certainty',(){
    const n=DetectedNote(midi:45,startSeconds:0,endSeconds:.8,
      confidence:.8);
    final part=InstrumentPart(family:InstrumentFamily.bass,
      notes:const [n],confidence:.6,signalLevel:.64);
    final guess=InstrumentHeuristics.suggest(part);
    expect(guess.program,32);
    expect(guess.reason,isNotEmpty);
    expect(InstrumentHeuristics.level(part),inInclusiveRange(0,1));
  });
}
