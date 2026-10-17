import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../audio/multitrack_engine.dart';
import '../score/score_engine.dart';

enum PaperTone { ivory, sepia }

class StudioScore extends StatefulWidget {
  const StudioScore({
    super.key,
    required this.project,
    required this.positionSeconds,
    required this.tone,
    this.activeNoteId,
    this.onTapNote,
  });

  final ScoreProject project;
  final double positionSeconds;
  final PaperTone tone;
  final int? activeNoteId;
  final ValueChanged<ScoreNote>? onTapNote;

  @override
  State<StudioScore> createState() => _StudioScoreState();
}

class _StudioScoreState extends State<StudioScore> {
  final _scroll = ScrollController();
  static const _barWidth = 190.0;
  static const _lead = 130.0;
  static const _rowHeight = 92.0;

  @override
  void didUpdateWidget(covariant StudioScore oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.positionSeconds - oldWidget.positionSeconds).abs() < 0.07) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final ticks = widget.positionSeconds * widget.project.bpm * 4 / 60;
      final x = _lead + ticks / ticksPerBar * _barWidth;
      final target = (x - _scroll.position.viewportDimension * 0.48)
          .clamp(0.0, _scroll.position.maxScrollExtent).toDouble();
      if ((_scroll.offset - target).abs() > _scroll.position.viewportDimension * .35) {
        _scroll.animateTo(target,
            duration: const Duration(milliseconds: 230),
            curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parts = widget.project.parts;
    final width = _lead + widget.project.barCount * _barWidth + 32;
    final height = 38.0 + parts.length * _rowHeight + 22.0;
    final cream = widget.tone == PaperTone.sepia;
    final paper = cream ? const Color(0xFFF2E5CA) : const Color(0xFFFAFAF8);
    final ink = cream ? const Color(0xFF302217) : const Color(0xFF191A1C);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: paper,
        border: Border.all(color: cream ?
          const Color(0xFFBBA687) : const Color(0xFFDBDCE0)),
        boxShadow: const [BoxShadow(
            color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: SizedBox(
        height: math.min(height, 430),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (event) {
                if (widget.onTapNote == null) return;
                final dx = event.localPosition.dx;
                final dy = event.localPosition.dy;
                final row = ((dy - 35) / _rowHeight).floor();
                if (row < 0 || row >= parts.length) return;
                final tick = ((dx - _lead) / _barWidth * ticksPerBar)
                    .floor() + ((dx - _lead) / _barWidth).floor()
                        * (ticksPerBar - ticksPerBar);
                final family = parts[row].family;
                final lane = widget.project.forFamily(family);
                if (lane.isEmpty) return;
                // Nearest note is clickable even when touching the staff
                // slightly above/below the notehead.
                ScoreNote? selected;
                var delta = double.infinity;
                for (final note in lane) {
                  final candidateX = _lead +
                      (note.start + note.length / 2) * _barWidth / ticksPerBar;
                  final error = (candidateX - dx).abs();
                  if (error < delta && error < 33) {
                    selected = note;
                    delta = error;
                  }
                }
                if (selected != null) widget.onTapNote!(selected);
              },
              child: CustomPaint(
                size: Size(width, height),
                painter: _StudioPainter(
                  widget.project,
                  widget.positionSeconds,
                  ink,
                  widget.activeNoteId,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StudioPainter extends CustomPainter {
  const _StudioPainter(this.score, this.position, this.ink, this.selected);
  final ScoreProject score;
  final double position;
  final Color ink;
  final int? selected;

  static const double lead = 130;
  static const double bw = 190;
  static const double row = 92;
  static const steps = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6];
  static const sharpNotes = [1, 3, 6, 8, 10];

  @override
  void paint(Canvas canvas, Size size) {
    final main = Paint()..color = ink..strokeWidth = 1.15;
    final weak = Paint()..color = ink.withValues(alpha: .26)..strokeWidth = .8;
    _text(canvas, 'AmpyScore Studio', 15, 5, 15, ink, bold: true);
    _text(canvas, '4/4  ·  ♩ = ${score.bpm} BPM',
        165, 7, 12, ink);
    for (var p = 0; p < score.parts.length; p++) {
      final part = score.parts[p];
      final y = 35.0 + p * row;
      final bottom = y + 50;
      _text(canvas, part.name.replaceAll(' (stima)', ''),
          10, y + 10, 12, ink, bold: true);
      _text(canvas, '${score.estimatedReliability(part.family)}% stima',
          10, y + 30, 10, ink.withValues(alpha: .72));
      for (var line = 0; line < 5; line++) {
        final yy = bottom - line * 10;
        canvas.drawLine(Offset(lead, yy), Offset(size.width - 20, yy), main);
      }
      final isBass = part.family == InstrumentFamily.bass;
      final isDrums = part.family == InstrumentFamily.drums;
      _text(canvas, isDrums ? 'Ⅱ' : isBass ? '𝄢' : '𝄞',
          lead + 3, y + 7, 27, ink);
      for (final measure in score.measures(part.family)) {
        final x0 = lead + measure.index * bw;
        final x1 = x0 + bw;
        if (measure.overflow) {
          canvas.drawRect(
            Rect.fromLTWH(x0 + 1, y - 4, bw - 2, 70),
            Paint()..color = const Color(0x44B41E2C),
          );
          canvas.drawLine(Offset(x0 + 1, y - 5),
              Offset(x1 - 1, y - 5),
              Paint()..color = const Color(0xFFCF2020)..strokeWidth = 4);
        }
        canvas.drawLine(Offset(x1, y + 10), Offset(x1, y + 50), main);
        _text(canvas, '${measure.index + 1}', x0 + 9, y - 14, 10, ink);
        for (var beat = 1; beat < 4; beat++) {
          final x = x0 + beat * bw / 4;
          canvas.drawLine(Offset(x, y + 12), Offset(x, y + 52), weak);
        }
        for (final cell in measure.cells) {
          final x = lead + (cell.start + cell.length / 2) *
              bw / ticksPerBar;
          if (cell.isRest) {
            final symbol = switch (cell.length) {
              16 => '▰', 12 || 8 => '▬',
              6 || 4 => '𝄽', 3 || 2 => '𝄾', _ => '𝄿'
            };
            _text(canvas, symbol, x - 6, y + 25,
                15, ink.withValues(alpha: .8));
            continue;
          }
          final note = cell.note!;
          final accent = selected == note.id ?
            const Color(0xFF0A7C60) : ink;
          final yy = _noteY(note.midi, bottom, isBass, isDrums);
          if (yy > bottom + 2) {
            for (var ly = bottom + 10; ly <= yy; ly += 10) {
              canvas.drawLine(Offset(x - 10, ly), Offset(x + 12, ly), main);
            }
          } else if (yy < bottom - 40) {
            for (var ly = bottom - 50; ly >= yy; ly -= 10) {
              canvas.drawLine(Offset(x - 10, ly), Offset(x + 12, ly), main);
            }
          }
          canvas.save();
          canvas.translate(x, yy);
          canvas.rotate(-0.22);
          canvas.drawOval(Rect.fromCenter(
              center: Offset.zero, width: 12, height: 8),
              Paint()..color = accent);
          canvas.restore();
          if (cell.length < 16) {
            canvas.drawLine(Offset(x + 5, yy),
                Offset(x + 5, yy - 27),
                Paint()..color = accent..strokeWidth = 1.3);
            if (cell.length <= 2) {
              canvas.drawLine(Offset(x + 5, yy - 27),
                  Offset(x + 13, yy - 19),
                  Paint()..color = accent..strokeWidth = 1.6);
            }
          }
          if (sharpNotes.contains(note.midi % 12) && !isDrums) {
            _text(canvas, '♯', x - 14, yy - 11, 14, ink);
          }
          if (cell.tieStart) {
            final ytie = yy + 11;
            canvas.drawArc(Rect.fromLTWH(x + 1, ytie, 22, 6),
                0, math.pi,
                false, Paint()..color = accent
                    ..style = PaintingStyle.stroke..strokeWidth = 1);
          }
        }
      }
    }
    // Single marine-green playhead through every simultaneous staff.
    final tick = position * score.bpm * 4 / 60;
    final cursorX = lead + tick / ticksPerBar * bw;
    final cursor = Paint()
      ..color = const Color(0xFF0E9B7A)
      ..strokeWidth = 3.5;
    canvas.drawLine(Offset(cursorX, 24),
        Offset(cursorX, size.height - 10), cursor);
    canvas.drawCircle(Offset(cursorX, 23), 5,
        Paint()..color = const Color(0xFF0E9B7A));
  }

  double _noteY(int midi, double bottom, bool bass, bool drums) {
    if (drums) return bottom - 22;
    final diatonic = (midi ~/ 12) * 7 + steps[midi % 12];
    final bottomNote = bass ? (3 * 7 + 4) : (5 * 7 + 2);
    return bottom - (diatonic - bottomNote) * 5.0;
  }

  void _text(Canvas canvas, String s, double x, double y,
      double size, Color color, {bool bold = false}) {
    final p = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: size, color: color,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 123);
    p.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant _StudioPainter old) =>
      old.score != score || old.position != position ||
      old.ink != ink || old.selected != selected;
}
