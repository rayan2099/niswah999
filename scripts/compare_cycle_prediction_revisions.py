#!/usr/bin/env python3
"""Compare actual default controllers from two checkouts on identical targets.

Input histories stay external. Outputs contain aggregate metrics only. The
baseline checkout must be trusted code; no models are trained or selected.
"""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path

TEMPLATE = r'''
import 'dart:convert';
import 'dart:io';
import '@BASE@/lib/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart' as old;
import '@BASE@/lib/features/cycle_tracking/domain/entities/cycle_log.dart' as oldlog;
import '@CURRENT@/lib/features/cycle_tracking/domain/controllers/cycle_tracking_controller.dart' as current;
import '@CURRENT@/lib/features/cycle_tracking/domain/entities/cycle_log.dart' as currentlog;

int days(DateTime a, DateTime b) => DateTime.utc(a.year,a.month,a.day).difference(DateTime.utc(b.year,b.month,b.day)).inDays;
Map<String, Object?> stats(List<int> errors) => {
  'evaluatedPredictions': errors.length,
  'meanAbsoluteErrorDays': errors.isEmpty ? null : errors.reduce((a,b)=>a+b)/errors.length,
  'fractionWithin3Days': errors.isEmpty ? null : errors.where((x)=>x<=3).length/errors.length,
};
void main(List<String> args) {
  final input = jsonDecode(File(args.single).readAsStringSync()) as List;
  final oldAll=<int>[], newAll=<int>[], oldCommon=<int>[], newCommon=<int>[], newlyWithheldOldErrors=<int>[];
  var eligible=0, bothWithheld=0, newOnly=0;
  for (final raw in input) {
    final starts = (raw as List).map((v) {
      if (v is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) throw FormatException();
      final date=DateTime.parse('${v}T00:00:00Z');
      if (date.toIso8601String().substring(0,10)!=v) throw FormatException();
      return date;
    }).toList();
    for(var i=1;i<starts.length;i++) {
      if (!starts[i].isAfter(starts[i-1])) throw FormatException();
    }
    for(var target=2;target<starts.length;target++) {
      eligible++;
      if ([for(var i=1;i<target;i++) days(starts[i], starts[i-1])].any((d)=>d<15)) {
        bothWithheld++; continue;
      }
      final oldSummary=const old.CycleTrackingController().summarizeHistory([
        for(var i=0;i<target;i++) oldlog.CycleLog(id:'$i',userId:'deidentified',date:starts[i],flow:oldlog.FlowLevel.medium,cycleDay:1),
      ],now:starts[target-1]);
      final newSummary=const current.CycleTrackingController().summarizeHistory([
        for(var i=0;i<target;i++) currentlog.CycleLog(id:'$i',userId:'deidentified',date:starts[i],flow:currentlog.FlowLevel.medium,cycleDay:1),
      ],now:starts[target-1]);
      final oldDate=oldSummary.nextPeriodStart, newDate=newSummary.nextPeriodStart;
      final oldError=oldDate==null ? null : days(oldDate, starts[target]).abs();
      final newError=newDate==null ? null : days(newDate, starts[target]).abs();
      if(oldError!=null) oldAll.add(oldError);
      if(newError!=null) newAll.add(newError);
      if(oldError!=null && newError!=null) {oldCommon.add(oldError);newCommon.add(newError);}
      else if(oldError!=null) {newlyWithheldOldErrors.add(oldError);}
      else if(newError!=null) {newOnly++;}
      else {bothWithheld++;}
    }
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'histories':input.length,'eligibleTargets':eligible,'reviewAnswersAvailable':false,
    'baselineAllEvaluated':stats(oldAll),'updatedAllEvaluated':stats(newAll),
    'baselineOnCommonTargets':stats(oldCommon),'updatedOnCommonTargets':stats(newCommon),
    'baselineOnNewlyWithheldTargets':stats(newlyWithheldOldErrors),
    'bothWithheld':bothWithheld,'newOnlyEvaluated':newOnly,
    'scope':'Development-cohort comparison; same-target results separate recency changes from abstention. Not independent or prospective validation.',
  }));
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline_checkout', type=Path)
    parser.add_argument('histories_json', type=Path)
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--packages', type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    baseline = args.baseline_checkout.resolve()
    code = TEMPLATE.replace('@BASE@', baseline.as_uri()).replace('@CURRENT@', repo.as_uri())
    with tempfile.TemporaryDirectory(prefix='niswah-prediction-comparison-') as temporary:
        script = Path(temporary) / 'compare.dart'
        script.write_text(code)
        command = [args.dart]
        if args.packages:
            command.append('--packages=' + str(args.packages.resolve()))
        command.extend([str(script), str(args.histories_json.resolve())])
        completed = subprocess.run(command, capture_output=True, text=True)
        if completed.returncode:
            parser.exit(1, 'Comparison failed; check trusted checkouts, dependencies and input format. No health records were printed.\n')
        result = json.loads(completed.stdout)
    result['baselineRevision'] = subprocess.check_output(['git', '-C', str(baseline), 'rev-parse', 'HEAD'], text=True).strip()
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
