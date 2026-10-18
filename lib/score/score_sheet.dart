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
    this.onFullScreen,
    this.fullScreen = false,
  });

  final ScoreProject project;
  final double positionSeconds;
  final PaperTone tone;
  final int? activeNoteId;
  final ValueChanged<ScoreNote>? onTapNote;
  final VoidCallback? onFullScreen;
  final bool fullScreen;

  @override
  State<StudioScore> createState() => _StudioScoreState();
}

class _StudioScoreState extends State<StudioScore> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  late final AnimationController _blink;
  final _transformation = TransformationController();
  bool _zoomEnabled = false;
  static const _barWidth = 190.0;
  static const _lead = 130.0;
  static const _rowHeight = 92.0;
  static const _pageBars = 8;
  int _firstBar = 0;
  DateTime _lastFollow = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 680));
    if (widget.activeNoteId != null) _blink.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant StudioScore oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project != widget.project) _firstBar = 0;
    if (oldWidget.activeNoteId != widget.activeNoteId) {
      if (widget.activeNoteId != null) {
        _blink.repeat(reverse: true);
      } else {
        _blink.stop();
      }
    }
    final seconds = widget.positionSeconds;
    final bars = widget.project.beatsPerBar;
    final bar = (seconds * widget.project.bpm / (60 * bars))
        .floor().clamp(0, widget.project.barCount - 1);
    if (bar < _firstBar || bar >= _firstBar + _pageBars) {
      _firstBar = (bar ~/ _pageBars) * _pageBars;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    final now = DateTime.now();
    if (now.difference(_lastFollow).inMilliseconds >= 220) {
      _lastFollow = now;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final x = _lead +
          (seconds * widget.project.bpm * ticksPerQuarter / 60 -
           _firstBar * widget.project.barTicks) /
              widget.project.barTicks * _barWidth;
        final viewport = _scroll.position.viewportDimension;
        final target = (x - viewport * .42)
            .clamp(0.0, _scroll.position.maxScrollExtent).toDouble();
        if ((_scroll.offset - target).abs() > 65) {
          _scroll.animateTo(target,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic);
        }
      });
    }
  }

  void _navigate(int direction) {
    final maxFirst = math.max(0, widget.project.barCount - 1);
    setState(() => _firstBar =
        (_firstBar + direction * _pageBars).clamp(0, maxFirst));
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _blink.dispose();
    _transformation.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parts = widget.project.parts;
    final endBar = math.min(widget.project.barCount, _firstBar + _pageBars);
    final width = _lead + (endBar - _firstBar) * _barWidth + 32;
    final height = 38.0 + parts.length * _rowHeight + 22.0;
    final cream = widget.tone == PaperTone.sepia;
    final paper = cream ? const Color(0xFFF2E5CA) : const Color(0xFFFAFAF8);
    final ink = cream ? const Color(0xFF302217) : const Color(0xFF191A1C);

    final painted = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (event) {
        if (widget.onTapNote == null) return;
        final dx = event.localPosition.dx;
        final dy = event.localPosition.dy;
        final row = ((dy - 35) / _rowHeight).floor();
        if (row < 0 || row >= parts.length) return;
        final lane = widget.project.forFamily(parts[row].family);
        ScoreNote? chosen;
        var bestDistance = double.infinity;
        for (final note in lane) {
          final centerX = _lead +
              (note.start + note.length / 2 - _firstBar * widget.project.barTicks) *
                _barWidth / widget.project.barTicks;
          final distance = (dx - centerX).abs();
          if (distance < bestDistance && distance <= 30) {
            chosen = note;
            bestDistance = distance;
          }
        }
        if (chosen != null) widget.onTapNote!(chosen);
      },
      onLongPress: () => setState(() => _zoomEnabled = true),
      child: AnimatedBuilder(
        animation: _blink,
        builder: (_, __) => CustomPaint(
          size: Size(width, height),
          painter: _StudioPainter(
            widget.project,
            widget.positionSeconds,
            ink,
            widget.activeNoteId,
            _blink.value,
            _firstBar,
            endBar,
          ),
        ),
      ),
    );

    final content = SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        child: painted,
      ),
    );
    return RepaintBoundary(
      child: DecoratedBox(
      decoration: BoxDecoration(
        color: paper,
        border: Border.all(
          color: cream ? const Color(0xFFBBA687) : const Color(0xFFDBDCE0),
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000),
              blurRadius: 7, offset: Offset(0, 2)),
        ],
      ),
      child: SizedBox(
        height: widget.fullScreen ? MediaQuery.sizeOf(context).height :
            math.min(height, 430),
        child: Stack(children: [
          Positioned.fill(
            child: _zoomEnabled
                ? InteractiveViewer(
                    transformationController: _transformation,
                    constrained: false,
                    boundaryMargin: const EdgeInsets.all(300),
                    minScale: 0.65,
                    maxScale: 5,
                    panEnabled: true,
                    scaleEnabled: true,
                    child: content,
                  )
                : content,
          ),
          Positioned(
            left: 4, top: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(color: const Color(0xD9152732),
                borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'Battute precedenti',
                  onPressed: _firstBar > 0 ? () => _navigate(-1) : null,
                  icon: const Icon(Icons.chevron_left, color: Colors.white)),
                Text('${_firstBar + 1}–$endBar',
                  style: const TextStyle(color: Colors.white)),
                IconButton(tooltip: 'Battute successive',
                  onPressed: endBar < widget.project.barCount
                      ? () => _navigate(1) : null,
                  icon: const Icon(Icons.chevron_right, color: Colors.white)),
              ]),
            ),
          ),
          if (_zoomEnabled)
            Positioned(
              right: 10, top: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xEE152732),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(children: [
                  IconButton(
                    tooltip: 'Zoom −',
                    color: Colors.white,
                    onPressed: () => _zoom(0.8),
                    icon: const Icon(Icons.zoom_out),
                  ),
                  IconButton(
                    tooltip: 'Zoom +',
                    color: Colors.white,
                    onPressed: () => _zoom(1.25),
                    icon: const Icon(Icons.zoom_in),
                  ),
                  IconButton(
                    tooltip: 'Schermo intero',
                    color: Colors.white,
                    onPressed: widget.onFullScreen,
                    icon: const Icon(Icons.fullscreen),
                  ),
                  IconButton(
                    tooltip: 'Disabilita zoom',
                    color: Colors.white,
                    onPressed: () => setState(() {
                      _zoomEnabled = false;
                      _transformation.value = Matrix4.identity();
                    }),
                    icon: const Icon(Icons.close),
                  ),
                ]),
              ),
            ),
        ]),
      ),
      ),
    );
  }

  void _zoom(double factor) {
    final value = _transformation.value.clone();
    value.scaleByDouble(factor, factor, factor, 1);
    final scale = value.getMaxScaleOnAxis();
    if (scale >= 0.65 && scale <= 5) {
      _transformation.value = value;
    }
  }
}

class _StudioPainter extends CustomPainter {
  const _StudioPainter(this.score, this.position, this.ink,
      this.selected, this.blink, this.firstBar, this.lastBar);
  final ScoreProject score;
  final double position;
  final Color ink;
  final int? selected;
  final double blink;
  final int firstBar;
  final int lastBar;

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
    _text(canvas, '${score.beatsPerBar}/4  ·  ♩ = ${score.bpm} BPM',
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
      for (final measure in score.measuresRange(part.family, firstBar, lastBar)) {
        final x0 = lead + (measure.index - firstBar) * bw;
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
        for (var beat = 1; beat < score.beatsPerBar; beat++) {
          final x = x0 + beat * bw / score.beatsPerBar;
          canvas.drawLine(Offset(x, y + 12), Offset(x, y + 52), weak);
        }
        for (final cell in measure.cells) {
          final x = lead + (cell.start + cell.length / 2 - firstBar * score.barTicks) *
              bw / score.barTicks;
          if (cell.isRest) {
            final symbol = switch (cell.length) {
              32 => '▰', 24 || 16 => '▬',
              12 || 8 => '𝄽', 6 || 4 => '𝄾',
              3 || 2 => '𝄿', _ => '𝅀'
            };
            _text(canvas, symbol, x - 6, y + 25, 15,
                cell.note != null && selected == cell.note!.id
                    ? Color.lerp(ink, const Color(0xFF006546), blink)!
                    : ink.withValues(alpha: .8));
            continue;
          }
          final note = cell.note!;
          final accent = selected == note.id
              ? Color.lerp(ink, const Color(0xFF006546), blink)!
              : ink;
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
          if (cell.length < 32) {
            canvas.drawLine(Offset(x + 5, yy),
                Offset(x + 5, yy - 27),
                Paint()..color = accent..strokeWidth = 1.3);
            if (cell.length <= 4 &&
                !_isBeamed(measure.cells, cell)) {
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
        // Explicitly join nearby eighths/sixteenths with beams per beat.
        // Do not beam across rests, quarter boundaries or ties.
        for (var beat = 0; beat < score.beatsPerBar; beat++) {
          final startBeat = measure.index * score.barTicks + beat * ticksPerQuarter;
          final endBeat = startBeat + ticksPerQuarter;
          final groups = <List<ScoreCell>>[];
          var currentGroup = <ScoreCell>[];
          for (final cell in measure.cells) {
            if (cell.start < startBeat || cell.start >= endBeat) continue;
            final canJoin = !cell.isRest && cell.length <= 4 &&
                !cell.tieStart && !cell.tieStop;
            if (!canJoin) {
              if (currentGroup.length >= 2) groups.add(currentGroup);
              currentGroup = <ScoreCell>[];
              continue;
            }
            if (currentGroup.isNotEmpty &&
                currentGroup.last.start + currentGroup.last.length !=
                    cell.start) {
              if (currentGroup.length >= 2) groups.add(currentGroup);
              currentGroup = <ScoreCell>[];
            }
            currentGroup.add(cell);
          }
          if (currentGroup.length >= 2) groups.add(currentGroup);
          for (final group in groups) {
            final color = ink;
            var beamY = double.infinity;
            for (final cell in group) {
              beamY = math.min(beamY, _noteY(cell.note!.midi, bottom,
                  isBass, isDrums) - 27);
            }
            final xFirst = lead +
                (group.first.start + group.first.length / 2 - firstBar * score.barTicks) * bw /
                    ticksPerBar + 5;
            final xLast = lead +
                (group.last.start + group.last.length / 2 - firstBar * score.barTicks) * bw /
                    ticksPerBar + 5;
            for (final cell in group) {
              final stemX = lead +
                  (cell.start + cell.length / 2 - firstBar * score.barTicks) * bw / score.barTicks + 5;
              final noteY = _noteY(cell.note!.midi, bottom, isBass, isDrums);
              canvas.drawLine(Offset(stemX, noteY),
                  Offset(stemX, beamY), Paint()
                      ..color = color..strokeWidth = 1.7);
            }
            canvas.drawLine(Offset(xFirst, beamY),
                Offset(xLast, beamY), Paint()
                    ..color = color..strokeWidth = 4);
            final shortGroup = group.where((c) => c.length <= 2).toList();
            for (var j = 0; j + 1 < shortGroup.length; j++) {
              final a = shortGroup[j];
              final b = shortGroup[j + 1];
              if (a.start + a.length != b.start) continue;
              final xa = lead + (a.start + a.length / 2 - firstBar * score.barTicks) * bw /
                  ticksPerBar + 5;
              final xb = lead + (b.start + b.length / 2 - firstBar * score.barTicks) * bw /
                  ticksPerBar + 5;
              canvas.drawLine(Offset(xa, beamY + 6),
                  Offset(xb, beamY + 6),
                  Paint()..color = color..strokeWidth = 3);
            }
          }
        }
      }
    }
    // Single marine-green playhead through every simultaneous staff.
    final tick = position * score.bpm * ticksPerQuarter / 60;
    final cursorX = lead + (tick - firstBar * score.barTicks) /
        score.barTicks * bw;
    final cursor = Paint()
      ..color = const Color(0xFF0E9B7A)
      ..strokeWidth = 3.5;
    canvas.drawLine(Offset(cursorX, 24),
        Offset(cursorX, size.height - 10), cursor);
    canvas.drawCircle(Offset(cursorX, 23), 5,
        Paint()..color = const Color(0xFF0E9B7A));
  }

  bool _isBeamed(List<ScoreCell> cells, ScoreCell note) {
    if (note.isRest || note.tieStart || note.tieStop || note.length > 4) {
      return false;
    }
    for (final other in cells) {
      if (identical(other, note) || other.isRest || other.length > 4 ||
          other.tieStart || other.tieStop) continue;
      final sameBeat = other.start ~/ ticksPerQuarter ==
          note.start ~/ ticksPerQuarter;
      if (!sameBeat) continue;
      if (note.start + note.length == other.start ||
          other.start + other.length == note.start) return true;
    }
    return false;
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
      old.ink != ink || old.selected != selected || old.blink != blink ||
      old.firstBar != firstBar || old.lastBar != lastBar;
}
