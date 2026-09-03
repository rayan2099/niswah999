import 'package:equatable/equatable.dart';

import '../entities/cycle_log.dart';

/// One [CycleLog.symptoms] list, decoded into its actual fields.
///
/// The entity itself is just `List<String>` — the real structure is a
/// colon-encoded mix of reserved keys (`energy`, `sleep`, `color`, `mood`,
/// `notes`, all lowercase) and named symptom severities (e.g. `Cramps:2`),
/// packed together by `cycle_log_form_sheet.dart`'s `_save()`. Nothing
/// decoded this before — this is the first reader of that encoding.
class DecodedCycleEntry extends Equatable {
  const DecodedCycleEntry({
    required this.date,
    this.energy,
    this.sleep,
    this.bloodColor,
    this.mood,
    this.notes,
    this.symptomSeverities = const {},
  });

  final DateTime date;
  final int? energy;
  final int? sleep;
  final String? bloodColor;
  final int? mood;
  final String? notes;

  /// Named symptom (e.g. "Cramps") -> severity (0-3), as tapped in the
  /// cycle-log symptom picker. Excludes the 5 reserved keys above.
  final Map<String, int> symptomSeverities;

  @override
  List<Object?> get props => [
    date,
    energy,
    sleep,
    bloodColor,
    mood,
    notes,
    symptomSeverities,
  ];
}

class NotedEntry extends Equatable {
  const NotedEntry({required this.date, required this.text});
  final DateTime date;
  final String text;

  @override
  List<Object?> get props => [date, text];
}

class SymptomAggregate extends Equatable {
  const SymptomAggregate({
    required this.name,
    required this.occurrenceCount,
    required this.averageSeverity,
  });

  final String name;
  final int occurrenceCount;
  final double averageSeverity;

  @override
  List<Object?> get props => [name, occurrenceCount, averageSeverity];
}

class CycleSymptomDecoder {
  const CycleSymptomDecoder._();

  static DecodedCycleEntry decode(CycleLog log) {
    int? energy;
    int? sleep;
    String? bloodColor;
    int? mood;
    String? notes;
    final symptomSeverities = <String, int>{};

    for (final raw in log.symptoms) {
      final separatorIndex = raw.indexOf(':');
      if (separatorIndex < 0) continue;

      final key = raw.substring(0, separatorIndex);
      final value = raw.substring(separatorIndex + 1);

      switch (key) {
        case 'energy':
          energy = int.tryParse(value);
        case 'sleep':
          sleep = int.tryParse(value);
        case 'color':
          bloodColor = value;
        case 'mood':
          mood = int.tryParse(value);
        case 'notes':
          notes = value;
        default:
          final severity = int.tryParse(value);
          if (severity != null) symptomSeverities[key] = severity;
      }
    }

    return DecodedCycleEntry(
      date: log.date,
      energy: energy,
      sleep: sleep,
      bloodColor: bloodColor,
      mood: mood,
      // Prefer the dedicated field; fall back to the legacy 'notes:' entry
      // in symptoms for logs saved before notes had their own column.
      notes: log.notes ?? notes,
      symptomSeverities: symptomSeverities,
    );
  }

  static List<DecodedCycleEntry> decodeAll(List<CycleLog> logs) =>
      logs.map(decode).toList();

  /// Aggregates named symptoms across a log history — occurrence count and
  /// average severity per symptom, sorted most-frequent first. Entries
  /// with severity 0 are excluded (cycling back to 0 in the picker means
  /// "not currently experiencing this").
  static List<SymptomAggregate> aggregateSymptoms(List<CycleLog> logs) {
    final totals = <String, int>{};
    final counts = <String, int>{};

    for (final entry in decodeAll(logs)) {
      for (final MapEntry(key: symptom, value: severity)
          in entry.symptomSeverities.entries) {
        if (severity <= 0) continue;
        totals[symptom] = (totals[symptom] ?? 0) + severity;
        counts[symptom] = (counts[symptom] ?? 0) + 1;
      }
    }

    final aggregates = [
      for (final symptom in counts.keys)
        SymptomAggregate(
          name: symptom,
          occurrenceCount: counts[symptom]!,
          averageSeverity: totals[symptom]! / counts[symptom]!,
        ),
    ]..sort((a, b) => b.occurrenceCount.compareTo(a.occurrenceCount));

    return aggregates;
  }

  /// Recent non-empty notes across [logs], newest first, capped at [limit].
  static List<NotedEntry> recentNotes(List<CycleLog> logs, {int limit = 10}) {
    final entries = decodeAll(logs)
        .where((entry) => entry.notes != null && entry.notes!.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return entries
        .take(limit)
        .map((entry) => NotedEntry(date: entry.date, text: entry.notes!))
        .toList();
  }

  /// Recent logged blood/discharge colors across [logs], newest first,
  /// capped at [limit]. Includes both preset ids (red/dark/brown/pink/
  /// other) and free-text custom descriptions entered when "Other" was
  /// selected — both are stored the same way by the `color:` encoding, so
  /// this doesn't need to distinguish them.
  static List<NotedEntry> recentBloodColors(
    List<CycleLog> logs, {
    int limit = 10,
  }) {
    final entries = decodeAll(logs)
        .where(
          (entry) =>
              entry.bloodColor != null && entry.bloodColor!.trim().isNotEmpty,
        )
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return entries
        .take(limit)
        .map((entry) => NotedEntry(date: entry.date, text: entry.bloodColor!))
        .toList();
  }
}
