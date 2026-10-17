import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'wav_engine.dart';

class StaffPreview extends StatelessWidget {
  const StaffPreview({super.key, required this.notes});

  final List<DetectedNote> notes;

  @override
  Widget build(BuildContext context) {
    final width = math.max(350, 56 + notes.length * 66).toDouble();
    return Container(
      height: 190,
      decoration: BoxDecoration(
        color: const Color(0xFF1B2632),
        borderRadius: BorderRadius.circular(18),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: CustomPaint(
          size: Size(width, 190),
          painter: _StaffPainter(notes),
        ),
      ),
    );
  }
}

class _StaffPainter extends CustomPainter {
  const _StaffPainter(this.notes);
  final List<DetectedNote> notes;

  static const _naturalSteps = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6];

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 131.0;
    const lineGap = 18.0;
    final line = Paint()
      ..color = const Color(0xFF687687)
      ..strokeWidth = 1.25;
    for (var i = 0; i < 5; i++) {
      final y = bottom - i * lineGap;
      canvas.drawLine(Offset(24, y), Offset(size.width - 12, y), line);
    }

    _write(canvas, '𝄞', const Offset(10, 40), 34, const Color(0xFFDAE4ED));
    if (notes.isEmpty) {
      _write(canvas, 'Nessuna nota rilevata', const Offset(48, 155), 13,
          const Color(0xFF9DAABA));
      return;
    }

    for (var i = 0; i < notes.length; i++) {
      final note = notes[i];
      final x = 65.0 + 66 * i;
      final step = (note.midi ~/ 12 - 5) * 7 +
          _naturalSteps[note.midi % 12];
      final y = bottom - (step - 2) * (lineGap / 2);

      final ledger = Paint()
        ..color = const Color(0xFF687687)
        ..strokeWidth = 1.2;
      if (y > bottom) {
        for (var ledgerY = bottom + lineGap;
            ledgerY <= y + 0.5;
            ledgerY += lineGap) {
          canvas.drawLine(Offset(x - 14, ledgerY),
              Offset(x + 14, ledgerY), ledger);
        }
      }
      if (y < bottom - 4 * lineGap) {
        for (var ledgerY = bottom - 5 * lineGap;
            ledgerY >= y - 0.5;
            ledgerY -= lineGap) {
          canvas.drawLine(Offset(x - 14, ledgerY),
              Offset(x + 14, ledgerY), ledger);
        }
      }
      final paint = Paint()..color = const Color(0xFF62DFC3);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(-0.32);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 21, height: 13), paint);
      canvas.restore();
      canvas.drawLine(Offset(x + 9, y), Offset(x + 9, y - 33),
          Paint()..color = const Color(0xFF62DFC3)..strokeWidth = 2);
      if ([1, 3, 6, 8, 10].contains(note.midi % 12)) {
        _write(canvas, '♯', Offset(x - 23, y - 16), 21,
            const Color(0xFFF5C16B));
      }
      _write(canvas, note.label, Offset(x - 19, 151), 12,
          const Color(0xFFE4EDF6));
    }
  }

  void _write(
    Canvas canvas,
    String message,
    Offset position,
    double size,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: message,
        style: TextStyle(fontSize: size, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant _StaffPainter oldDelegate) =>
      oldDelegate.notes != notes;
}
