import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'score_engine.dart';
import '../audio/multitrack_engine.dart';

/// Vector A4 multi-staff export: all measures, rests and edited notes.
/// Intended for review/printing; professional engraving remains MusicXML.
class ScorePdf {
  static const barsPerSystem = 4;
  static const minimumSystemsPerPage = 2;

  static Future<Uint8List> render(ScoreProject score, {
    String title = 'AmpyScore Studio',
    bool sepia = false,
  }) async {
    final document = pw.Document(compress: true);
    final ink = sepia ? PdfColor.fromInt(0xff302719) : PdfColors.black;
    final paper = sepia ? PdfColor.fromInt(0xfff9f2e5) : PdfColors.white;
    final name = title.replaceAll(RegExp(r'[^\w .-]'), ' ').trim();
    final totalSystems = (score.barCount / barsPerSystem).ceil();
    final systemHeight = score.parts.length * 54 + 37;
    final systemsPerPage = math.max(minimumSystemsPerPage,
        math.min(6, (480 / systemHeight).floor()));
    final pageCount = (totalSystems / systemsPerPage).ceil();
    for (var page = 0; page < pageCount; page++) {
      final systems = <pw.Widget>[];
      for (var section = 0; section < systemsPerPage; section++) {
        final systemIndex = page * systemsPerPage + section;
        if (systemIndex >= totalSystems) break;
        final firstBar = systemIndex * barsPerSystem;
        final lastBar = math.min(score.barCount, firstBar + barsPerSystem);
        systems.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 16),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Battute ${firstBar + 1}-$lastBar',
                style: pw.TextStyle(fontSize: 8, color: ink)),
              pw.SizedBox(height: 3),
              for (final part in score.parts)
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.SizedBox(width: 104,
                      child: pw.Text(part.name.replaceAll(' (stima)',''),
                        style: pw.TextStyle(fontSize: 7, color: ink))),
                    pw.CustomPaint(
                      size: const PdfPoint(636, 54),
                      painter: (canvas, size) => _drawStaff(
                        canvas, size, score, part, firstBar, lastBar, ink),
                    ),
                  ],
                ),
            ],
          ),
        ));
      }
      document.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(30, 26, 30, 20),
        build: (context) => pw.Container(
          color: paper, width: double.infinity, height: double.infinity,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(name.isEmpty ? 'AmpyScore Studio' : name,
                    style: pw.TextStyle(fontSize: 16,
                        fontWeight: pw.FontWeight.bold, color: ink)),
                  pw.Text('${score.beatsPerBar}/4 · ${score.bpm} BPM',
                    style: pw.TextStyle(fontSize: 11, color: ink)),
                ],
              ),
              pw.SizedBox(height: 16),
              ...systems,
              pw.Spacer(),
              pw.Text('AmpyScore Studio · Trascrizione automatica da verificare'
                ' · Pagina ${page + 1}/$pageCount',
                style: pw.TextStyle(fontSize: 8, color: ink)),
            ],
          ),
        ),
      ));
    }
    return document.save();
  }

  static void _line(PdfGraphics g, double x1,double y1,double x2,double y2,
      PdfColor color, {double width=.7}) {
    g..setStrokeColor(color)..setLineWidth(width)
      ..moveTo(x1,y1)..lineTo(x2,y2)..strokePath();
  }

  static void _drawStaff(
    PdfGraphics g, PdfPoint size, ScoreProject score, InstrumentPart part,
    int firstBar, int lastBar, PdfColor ink,
  ) {
    final top = 17.0;
    final endX = size.x - 3;
    final span = endX - 9;
    final barWidth = span / (lastBar-firstBar);
    for (var staff = 0; staff < 5; staff++) {
      final y = top + staff * 7.0;
      _line(g,7,y,endX,y,ink, width:.55);
    }
    for (var bar = firstBar; bar <= lastBar; bar++) {
      final x = 7.0 + (bar - firstBar) * barWidth;
      _line(g,x,top,x,top+28,ink,width:.8);
    }
    final parts = score.measuresRange(part.family,firstBar,lastBar);
    for (final measure in parts) {
      final barStart = measure.index*score.barTicks;
      for (final cell in measure.cells) {
        final x = 7 + (measure.index-firstBar)*barWidth +
            (cell.start-barStart+cell.length*.5) /
                score.barTicks*barWidth;
        if (cell.isRest) {
          final y=top+14;
          _line(g,x-3,y,x+3,y,ink,width:2.0);
          continue;
        }
        final pitch=cell.note!.midi;
        final bass=part.family==InstrumentFamily.bass;
        final percussion=part.percussion;
        // Staff bottom note: E4 treble / G2 bass. Seven semitone steps
        // map chromatic pitch to diatonic position for vector drawing.
        final base = bass ? 43 : 64;
        final step = _diatonic(pitch) - _diatonic(base);
        final y=top+step*3.5;
        final constrainedY=y.clamp(2.0,size.y-3.0);
        // Round/elliptic notehead with stem and optional flag.
        g..setColor(ink)
         ..drawEllipse(x,constrainedY,3.7,2.6);
        if (cell.length < 16) g.fillPath(); else g.strokePath();
        if (cell.length < 32 && !percussion) {
          _line(g,x+3.4,constrainedY,x+3.4,constrainedY+22,ink,width:.8);
          if (cell.length <= 4) {
            _line(g,x+3.4,constrainedY+22,x+10,constrainedY+16,ink,width:1.5);
          }
        }
        if (cell.tieStart) {
          _line(g,x-2,constrainedY-5,x+8,constrainedY-5,ink,width:.55);
        }
        // Minimal ledger line for notes outside staff.
        if (y < top-1 || y > top+29) {
          final ledger = y < top ? top-7 : top+35;
          _line(g,x-6,ledger,x+6,ledger,ink,width:.65);
        }
      }
      if (measure.overflow) {
        final bx=7 + (measure.index-firstBar+1)*barWidth;
        _line(g,bx,top,bx,top+28,PdfColors.red,width:1.8);
      }
    }
  }

  static int _diatonic(int midi) {
    const offsets=[0,0,1,1,2,3,3,4,4,5,5,6];
    return (midi ~/ 12)*7 + offsets[midi%12];
  }
}
