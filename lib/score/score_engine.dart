import 'dart:math' as math;
import '../audio/multitrack_engine.dart';

const int ticksPerBar = 16;
const int midiTicksPerSixteenth = 120;

/// Native editor state: each event is an independently editable single note.
/// Rests are calculated from unoccupied time on each staff.
class ScoreNote {
  ScoreNote({
    required this.id,
    required this.family,
    required this.midi,
    required this.start,
    required this.length,
    required this.evidence,
  });
  final int id;
  final InstrumentFamily family;
  int midi;
  int start;
  int length;
  final double evidence;
  int get end => start + length;
  ScoreNote copy() => ScoreNote(id: id, family: family, midi: midi,
      start: start, length: length, evidence: evidence);
}

class ScoreCell {
  const ScoreCell({
    required this.start,
    required this.length,
    this.note,
    this.tieStart = false,
    this.tieStop = false,
  });
  final int start;
  final int length;
  final ScoreNote? note;
  final bool tieStart; // Continue to next cell.
  final bool tieStop; // Continued from previous cell.
  bool get isRest => note == null;
}

class ScoreMeasure {
  const ScoreMeasure(this.index, this.cells, this.overflow);
  final int index;
  final List<ScoreCell> cells;
  final bool overflow;
}

class ScoreProject {
  ScoreProject({
    required this.bpm,
    required this.parts,
    required this.notes,
  });
  int bpm;
  final List<InstrumentPart> parts;
  final List<ScoreNote> notes;
  int _nextId = 0;

  factory ScoreProject.fromTranscription(
      List<InstrumentPart> parts, int bpm) {
    final project = ScoreProject(bpm: bpm.clamp(40, 240),
        parts: parts, notes: []);
    final ticksPerSecond = project.bpm * 4 / 60.0;
    for (final part in parts) {
      ScoreNote? last;
      final ordered = part.notes.toList()
        ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
      for (final note in ordered) {
        final begin = math.max(0, (note.startSeconds * ticksPerSecond).round());
        final end = math.max(begin + 1,
            (note.endSeconds * ticksPerSecond).round());
        final adjustedStart = last == null ? begin : math.max(begin, last.end);
        if (adjustedStart >= end) continue;
        final item = ScoreNote(
          id: project._nextId++, family: part.family,
          midi: note.midi, start: adjustedStart,
          length: end - adjustedStart,
          evidence: note.confidence,
        );
        project.notes.add(item);
        last = item;
      }
    }
    return project;
  }

  List<ScoreNote> forFamily(InstrumentFamily family) =>
      notes.where((n) => n.family == family).toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  double get durationSeconds => (barCount * ticksPerBar) * 60 / (bpm * 4);

  int get barCount {
    final maxEnd = notes.fold<int>(0, (v, note) => math.max(v, note.end));
    return math.max(1, (maxEnd / ticksPerBar).ceil());
  }

  int? activeNoteId(InstrumentFamily family, double time) {
    final tick = (time * bpm * 4 / 60).floor();
    for (final note in forFamily(family)) {
      if (tick >= note.start && tick < note.end) return note.id;
    }
    return null;
  }

  double timeOf(ScoreNote note) => note.start * 60 / (bpm * 4);

  void addNote(InstrumentFamily family, {int? afterId}) {
    final lane = forFamily(family);
    final after = afterId == null ? null :
        notes.where((n) => n.id == afterId).firstOrNull;
    final pos = after != null ? after.end :
        (lane.isEmpty ? 0 : lane.last.end);
    notes.add(ScoreNote(
      id: _nextId++, family: family,
      midi: after?.midi ?? 60,
      start: pos,
      length: 4,
      evidence: 0,
    ));
  }

  bool removeNote(int id) {
    final count = notes.length;
    notes.removeWhere((note) => note.id == id);
    return count != notes.length;
  }

  /// Different frequencies inside a single estimated register are not
  /// treated as independent polyphonic voices in this early score editor.
  /// Overlap produces a red bar, rather than silently hiding the problem.
  bool hasOverflow(InstrumentFamily family, int bar) {
    final begin = bar * ticksPerBar;
    final end = begin + ticksPerBar;
    var total = 0;
    for (final note in forFamily(family)) {
      total += math.max(0, math.min(note.end, end) -
          math.max(note.start, begin));
    }
    return total > ticksPerBar;
  }

  List<ScoreMeasure> measures(InstrumentFamily family) {
    final lane = forFamily(family);
    final out = <ScoreMeasure>[];
    for (var bar = 0; bar < barCount; bar++) {
      final start = bar * ticksPerBar;
      final end = start + ticksPerBar;
      var cursor = start;
      final cells = <ScoreCell>[];
      for (final note in lane) {
        if (note.end <= start) continue;
        if (note.start >= end) break;
        final begin = math.max(start, note.start);
        final finish = math.min(end, note.end);
        if (begin > cursor) {
          cells.addAll(_split(cursor, begin, null));
          cursor = begin;
        }
        final actualStart = math.max(begin, cursor);
        if (finish <= actualStart) continue;
        cells.addAll(_split(actualStart, finish, note,
            continuesFrom: actualStart > note.start,
            continuesTo: finish < note.end));
        cursor = finish;
      }
      if (cursor < end) cells.addAll(_split(cursor, end, null));
      out.add(ScoreMeasure(bar, cells, hasOverflow(family, bar)));
    }
    return out;
  }

  static List<ScoreCell> _split(int start, int end, ScoreNote? note,
      {bool continuesFrom = false, bool continuesTo = false}) {
    final cells = <ScoreCell>[];
    var at = start;
    const values = [16, 12, 8, 6, 4, 3, 2, 1];
    while (at < end) {
      final barEnd = (at ~/ ticksPerBar + 1) * ticksPerBar;
      final remaining = math.min(end, barEnd) - at;
      final units = values.firstWhere((v) => v <= remaining);
      cells.add(ScoreCell(
        start: at,
        length: units,
        note: note,
        tieStop: note != null && (continuesFrom || at != start),
        tieStart: note != null &&
            (continuesTo || at + units != end),
      ));
      at += units;
    }
    return cells;
  }

  /// This is an evidence-based heuristic, *not* a measured transcription
  /// accuracy against ground-truth notation. Never label it verified.
  int estimatedReliability(InstrumentFamily family) {
    final lane = forFamily(family);
    if (lane.isEmpty) return 0;
    final source = parts.where((p) => p.family == family).firstOrNull;
    final sourceStrength = source?.confidence ?? 0.4;
    final signalConfidence = lane.map((n) => n.evidence)
        .reduce((a, b) => a + b) / lane.length;
    final issues = List.generate(barCount,
        (i) => hasOverflow(family, i)).where((bad) => bad).length;
    final raw = 100 * (0.55 * signalConfidence.clamp(0.0, 1.0) +
        0.45 * sourceStrength.clamp(0.0, 1.0)) -
        issues * 8;
    return raw.round().clamp(0, 100);
  }
}

/// MusicXML 4.0 partwise export with actual 4/4 measures, rests,
/// correctly split durations and ties over barlines. Supports standard
/// notation tools and can later be rendered using Verovio/OSMD.
class MusicXmlWriter {
  static String export(ScoreProject score) {
    final out = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln('<!DOCTYPE score-partwise  PUBLIC "-//Recordare//DTD '
          'MusicXML 4.0 Partwise//EN" '
          '"http://www.musicxml.org/dtds/partwise.dtd">')
      ..writeln('<score-partwise version="4.0">')
      ..writeln('<work><work-title>AmpyScore Studio</work-title></work>')
      ..writeln('<movement-title>AmpyScore Studio</movement-title>')
      ..writeln('<identification><creator type="software">AmpyScore '
          'AI offline</creator></identification>')
      ..writeln('<defaults><scaling><millimeters>7</millimeters>'
          '<tenths>40</tenths></scaling></defaults>')
      ..writeln('<part-list>');
    for (var i = 0; i < score.parts.length; i++) {
      final p = score.parts[i];
      out.writeln('<score-part id="P${i + 1}"><part-name>'
          '${_xml(p.name)}</part-name><part-abbreviation>'
          '${_xml(p.family.name)}</part-abbreviation>'
          '</score-part>');
    }
    out.writeln('</part-list>');
    for (var i = 0; i < score.parts.length; i++) {
      final part = score.parts[i];
      out.writeln('<part id="P${i + 1}">');
      for (final bar in score.measures(part.family)) {
        out.writeln('<measure number="${bar.index + 1}">');
        if (bar.index == 0) {
          final bass = part.family == InstrumentFamily.bass;
          final percussion = part.percussion;
          out.writeln('<attributes><divisions>480</divisions>'
              '<key><fifths>0</fifths></key>'
              '<time><beats>4</beats><beat-type>4</beat-type></time>'
              '<clef><sign>${percussion ? "percussion" : bass ? "F" : "G"}</sign>'
              '${percussion ? "" : "<line>${bass ? 4 : 2}</line>"}'
              '</clef></attributes>');
          out.writeln('<direction placement="above"><direction-type>'
              '<metronome><beat-unit>quarter</beat-unit>'
              '<per-minute>${score.bpm}</per-minute></metronome>'
              '</direction-type><sound tempo="${score.bpm}"/>'
              '</direction>');
        }
        for (final cell in bar.cells) {
          out.write('<note>');
          if (cell.isRest) {
            out.write('<rest/>');
          } else {
            final pitch = _pitch(cell.note!.midi);
            if (part.percussion) {
              out.write('<unpitched><display-step>D</display-step>'
                  '<display-octave>5</display-octave></unpitched>');
            } else {
              out.write('<pitch>${pitch.$1}${pitch.$2}</pitch>');
            }
          }
          out.write('<duration>${cell.length * midiTicksPerSixteenth}'
              '</duration><type>${_type(cell.length)}</type>');
          if ([3, 6, 12].contains(cell.length)) out.write('<dot/>');
          if (cell.tieStop) out.write('<tie type="stop"/>');
          if (cell.tieStart) out.write('<tie type="start"/>');
          if (cell.tieStop || cell.tieStart) {
            out.write('<notations>');
            if (cell.tieStop) out.write('<tied type="stop"/>');
            if (cell.tieStart) out.write('<tied type="start"/>');
            out.write('</notations>');
          }
          out.writeln('</note>');
        }
        out.writeln('</measure>');
      }
      out.writeln('</part>');
    }
    out.writeln('</score-partwise>');
    return out.toString();
  }

  static String _type(int n) => switch (n) {
    16 => 'whole',
    12 || 8 => 'half',
    6 || 4 => 'quarter',
    3 || 2 => 'eighth',
    _ => '16th',
  };

  static (String, String) _pitch(int midi) {
    const letters = ['C', 'C', 'D', 'D', 'E', 'F',
        'F', 'G', 'G', 'A', 'A', 'B'];
    final index = midi % 12;
    final alter = [1, 3, 6, 8, 10].contains(index) ? '<alter>1</alter>' : '';
    return ('<step>${letters[index]}</step>$alter',
        '<octave>${midi ~/ 12 - 1}</octave>');
  }

  static String _xml(String s) => s.replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;').replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
