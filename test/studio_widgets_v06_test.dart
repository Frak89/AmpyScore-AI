import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ampy_score_ai/audio/multitrack_engine.dart';
import 'package:ampy_score_ai/audio/wav_engine.dart';
import 'package:ampy_score_ai/score/score_engine.dart';
import 'package:ampy_score_ai/score/score_sheet.dart';
import 'package:ampy_score_ai/score/note_lab.dart';

void main() {
  testWidgets('Score sheet draws and exposes zoom after long press',
      (tester) async {
    final score = ScoreProject.fromTranscription([
      InstrumentPart(
        family: InstrumentFamily.melody, confidence: .7,
        notes: [
          const DetectedNote(
            midi: 60, startSeconds: 0,
            endSeconds: .5, confidence: .8),
          const DetectedNote(
            midi: 62, startSeconds: .5,
            endSeconds: 1, confidence: .8),
        ],
      ),
    ], 120);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(
        body: StudioScore(project: score,
            positionSeconds: 0.1, tone: PaperTone.ivory))),
    );
    expect(tester.takeException(), isNull);
    await tester.longPress(find.byType(StudioScore));
    await tester.pump();
    expect(find.byIcon(Icons.zoom_in), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NoteLab toolbar exposes 1/32–4/1 and toggles selected rest',
      (tester) async {
    final part = InstrumentPart(
      family: InstrumentFamily.melody,
      confidence: .7,
      notes: [const DetectedNote(midi: 60, startSeconds: 0,
          endSeconds: .5, confidence: .8)],
    );
    final score = ScoreProject.fromTranscription([part], 120);
    final selected = score.notes.first;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: NoteLab(
        score: score,
        selectedFamily: InstrumentFamily.melody,
        selectedNoteId: selected.id,
        onSelect: (_) {},
        onChanged: () {},
      ))),
    ));
    expect(find.text('1/4'), findsOneWidget);
    expect(find.text('Pausa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
