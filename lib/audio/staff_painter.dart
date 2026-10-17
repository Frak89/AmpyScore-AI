import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'wav_engine.dart';

/// Scrollable score preview following the current time position.
/// The score is approximate: no rhythmic quantization or separate instruments.
class StaffPreview extends StatefulWidget {
  const StaffPreview({
    super.key,
    required this.notes,
    this.activeIndex = -1,
    this.onNoteTap,
  });

  final List<DetectedNote> notes;
  final int activeIndex;
  final ValueChanged<int>? onNoteTap;

  @override
  State<StaffPreview> createState() => _StaffPreviewState();
}

class _StaffPreviewState extends State<StaffPreview> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant StaffPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeIndex < 0 ||
        (widget.activeIndex == oldWidget.activeIndex &&
         widget.notes == oldWidget.notes)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final noteX = 65.0 + widget.activeIndex * 66.0;
      final target = (noteX - position.viewportDimension / 2)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((position.pixels - target).abs() > 12) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 210),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = math.max(350, 110 + widget.notes.length * 66).toDouble();
    return Container(
      height: 190,
      decoration: BoxDecoration(
        color: const Color(0xFF1B2632),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.onNoteTap == null
              ? null
              : (details) {
                  final x = details.localPosition.dx;
                  final index = ((x - 65) / 66).round();
                  if (index >= 0 && index < widget.notes.length &&
                      (x - (65 + index * 66)).abs() < 27) {
                    widget.onNoteTap!(index);
                  }
                },
          child: Semantics(
            label: 'Pentagramma: note evidenziate durante la riproduzione',
            child: CustomPaint(
              size: Size(width, 190),
              painter: _StaffPainter(widget.notes, widget.activeIndex),
            ),
          ),
        ),
      ),
    );
  }
}

class _StaffPainter extends CustomPainter {
  const _StaffPainter(this.notes, this.activeIndex);
  final List<DetectedNote> notes;
  final int activeIndex;

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
      final selected = i == activeIndex;
      if (selected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - 25, 9, 50, 174),
            const Radius.circular(12),
          ),
          Paint()..color = const Color(0x333DF0B6),
        );
      }

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
      final paint = Paint()
        ..color = selected
            ? const Color(0xFFFFD07B) : const Color(0xFF62DFC3);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(-0.32);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero,
              width: selected ? 25 : 21, height: selected ? 16 : 13), paint);
      canvas.restore();
      canvas.drawLine(
          Offset(x + 9, y), Offset(x + 9, y - 33),
          Paint()
            ..color = selected
                ? const Color(0xFFFFD07B) : const Color(0xFF62DFC3)
            ..strokeWidth = 2);
      if ([1, 3, 6, 8, 10].contains(note.midi % 12)) {
        _write(canvas, '♯', Offset(x - 23, y - 16), 21,
            const Color(0xFFF5C16B));
      }
      _write(canvas, note.label, Offset(x - 19, 151), 12,
          selected ? const Color(0xFFFFD07B) : const Color(0xFFE4EDF6));
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
      oldDelegate.notes != notes || oldDelegate.activeIndex != activeIndex;
}
