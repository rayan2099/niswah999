import 'package:equatable/equatable.dart';

import '../entities/pregnancy_milestone.dart';

class PregnancyMilestoneSnapshot extends Equatable {
  const PregnancyMilestoneSnapshot({
    required this.week,
    required this.trimester,
    required this.label,
    required this.summary,
  });

  final int week;
  final PregnancyTrimester trimester;
  final String label;
  final String summary;

  @override
  List<Object?> get props => [week, trimester, label, summary];
}

class PregnancyCalculator {
  PregnancyCalculator();

  static int currentWeekFromLmp({
    required DateTime lmp,
    required DateTime now,
  }) {
    final days = now.difference(lmp).inDays;
    return (days / 7).floor().clamp(1, 40);
  }

  static PregnancyMilestoneSnapshot milestoneForDueDate({
    required DateTime dueDate,
    required DateTime now,
  }) {
    final daysRemaining = dueDate.difference(now).inDays;
    final week = ((280 - daysRemaining) / 7).floor().clamp(1, 40);
    final trimester = _trimesterForWeek(week);

    return PregnancyMilestoneSnapshot(
      week: week,
      trimester: trimester,
      label: _labelForWeek(week),
      summary: _summaryForWeek(week),
    );
  }

  static PregnancyTrimester _trimesterForWeek(int week) {
    if (week <= 13) {
      return PregnancyTrimester.first;
    }
    if (week <= 27) {
      return PregnancyTrimester.second;
    }
    return PregnancyTrimester.third;
  }

  static String _labelForWeek(int week) {
    if (week < 13) {
      return 'Early pregnancy';
    }
    if (week < 27) {
      return 'Second trimester progress';
    }
    if (week < 40) {
      return 'Third trimester development';
    }
    return 'Due date window';
  }

  static String _summaryForWeek(int week) {
    if (week < 13) {
      return 'Your baby is beginning to form its key organs and systems.';
    }
    if (week < 27) {
      return 'Your baby is growing steadily and movement may be felt more clearly.';
    }
    if (week < 40) {
      return 'Your baby is preparing for birth and continuing to gain weight.';
    }
    return 'Your due date is close, and the body is preparing for labour.';
  }
}
