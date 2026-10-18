#!/usr/bin/env python3
"""Research only: fixed-coverage candidate comparisons and grouped validation.

Consumes the minimized EXTERNAL output of export_cycle_evaluation_folds.dart.
Only aggregate statistics are printed. This does not change the app model.
"""
import argparse
import hashlib
import json
import math
import random
from collections import defaultdict
from pathlib import Path
from statistics import mean, median

METHODS = ('currentMean6', 'median6', 'mean3', 'median3', 'trimmedMean6',
           'exponentialMeanHalf', 'lastInterval', 'boundedLinearTrend6',
           'historicalWindowCenter3', 'personalExpert')
BASELINE_VERSION = 'cycle-prediction-v2-history-review-2026-10-17'
FROZEN_PROTOCOL_SHA256 = '9e371a4fc3a478f442ed051b66eaf57a337f3bddf87e2c9f781a45237b6f0dfa'
DEFAULT_PROTOCOL = Path(__file__).resolve().parents[1] / 'docs/validation/prediction-accuracy-program-2026-10-17/protocol.json'


def rounded(value):
    return math.floor(value + 0.5)


def predict_candidates(prior, baseline, prior_errors):
    """Only preceding intervals/errors enter this function; no target input."""
    if not 1 <= len(prior) <= 6 or any(type(x) is not int or not 15 <= x <= 90 for x in prior):
        raise ValueError('Invalid preceding intervals')
    if type(baseline) is not int or baseline != rounded(mean(prior)):
        raise ValueError('Frozen baseline mismatch')
    ordered = sorted(prior)
    trimmed = ordered[1:-1] if len(ordered) >= 5 else ordered
    weights = [0.5 ** i for i in range(len(prior))]
    exponential = sum(x * w for x, w in zip(reversed(prior), weights)) / sum(weights)
    n = len(prior)
    trend = prior[-1]
    if n >= 2:
        center_x = (n - 1) / 2
        slope = sum((i - center_x) * (x - mean(prior)) for i, x in enumerate(prior)) / sum((i - center_x) ** 2 for i in range(n))
        slope = min(1.0, max(-1.0, slope))
        trend = min(90.0, max(15.0, mean(prior) + slope * (n - center_x)))
    window_center = min(range(min(prior) - 3, max(prior) + 4), key=lambda c: (
        -sum(abs(x - c) <= 3 for x in prior), abs(c - median(prior)), c))
    predictions = dict(zip(METHODS[:-1], map(rounded, (
        baseline, median(prior), mean(prior[-3:]), median(prior[-3:]),
        mean(trimmed), exponential, prior[-1], trend, window_center))))
    expert = METHODS[0]
    if len(prior_errors.get(METHODS[0], ())) >= 4:
        expert = min(METHODS[:-1], key=lambda m: (
            -mean(e <= 3 for e in prior_errors[m][-6:]),
            mean(prior_errors[m][-6:]), METHODS.index(m)))
    predictions['personalExpert'] = predictions[expert]
    return predictions


def empty_score():
    return {'n': 0, 'absoluteError': 0, 'within1': 0, 'within3': 0, 'within7': 0}


def add_score(score, error):
    score['n'] += 1
    score['absoluteError'] += error
    for tolerance in (1, 3, 7):
        score[f'within{tolerance}'] += error <= tolerance


def summarize(scores):
    scores = list(scores)
    total = {key: sum(s[key] for s in scores) for key in empty_score()}
    n = total['n']
    nonempty = [s for s in scores if s['n']]
    return {
        'evaluatedPredictions': n,
        'groupsWithPredictions': len(nonempty),
        'meanAbsoluteErrorDays': total['absoluteError'] / n if n else None,
        'fractionWithin1Day': total['within1'] / n if n else None,
        'fractionWithin3Days': total['within3'] / n if n else None,
        'fractionWithin7Days': total['within7'] / n if n else None,
        'equalGroupFractionWithin3Days': mean(s['within3'] / s['n'] for s in nonempty) if nonempty else None,
        'equalGroupMeanAbsoluteErrorDays': mean(s['absoluteError'] / s['n'] for s in nonempty) if nonempty else None,
    }


def assign_group_folds(groups, folds, seed):
    if len(groups) < folds:
        raise ValueError('Insufficient groups for frozen fold count')
    shuffled = sorted(groups)
    random.Random(seed).shuffle(shuffled)
    return {group: i % folds for i, group in enumerate(shuffled)}


def select_on_training(scores, training_groups):
    training_groups = list(training_groups)
    metrics = {m: summarize(scores[g][m] for g in training_groups) for m in METHODS}
    if metrics[METHODS[0]]['evaluatedPredictions'] == 0:
        return METHODS[0]
    return min(METHODS, key=lambda m: (
        -metrics[m]['equalGroupFractionWithin3Days'],
        metrics[m]['equalGroupMeanAbsoluteErrorDays'], METHODS.index(m)))


def quantile(values, probability):
    if not values:
        return None
    ordered = sorted(values)
    position = (len(ordered) - 1) * probability
    lo, hi = math.floor(position), math.ceil(position)
    return ordered[lo] * (hi - position) + ordered[hi] * (position - lo) if hi != lo else ordered[lo]


def paired_group_bootstrap(scores, selected, repetitions, seed):
    groups = sorted(scores)
    rng = random.Random(seed)
    distributions = defaultdict(list)
    for _ in range(repetitions):
        sampled = [rng.choice(groups) for _ in groups]
        before = summarize(scores[g][METHODS[0]] for g in sampled)
        after = summarize(selected[g] for g in sampled)
        if not before['evaluatedPredictions']:
            continue
        b, a = before['fractionWithin3Days'], after['fractionWithin3Days']
        bm, am = before['meanAbsoluteErrorDays'], after['meanAbsoluteErrorDays']
        distributions['baselineFractionWithin3Days'].append(b)
        distributions['selectedFractionWithin3Days'].append(a)
        distributions['pairedAccuracyDifference'].append(a - b)
        distributions['baselineMAEDays'].append(bm)
        distributions['selectedMAEDays'].append(am)
        distributions['pairedMAEDifferenceDays'].append(am - bm)
    return {
        'unit': 'Whole declared source/participant group, never individual cycles',
        'interpretation': 'Conditional on fixed out-of-fold predictions; does not include refitting/selection uncertainty or establish generalizability',
        'requestedResamples': repetitions,
        'usableResamples': len(distributions['pairedAccuracyDifference']),
        'percentile95': {k: [quantile(v, .025), quantile(v, .975)] for k, v in distributions.items()},
    }


def score_fold_data(data):
    if data['schemaVersion'] != 1 or data['predictionVersion'] != BASELINE_VERSION:
        raise ValueError('Unexpected baseline/schema version')
    histories = data['histories']
    groups = {row['group'] for row in histories}
    if any(type(g) is not int or g < 0 for g in groups):
        raise ValueError('Invalid group labels')
    scores = {g: {m: empty_score() for m in METHODS} for g in groups}
    strata = {bucket: {m: empty_score() for m in METHODS} for bucket in ('oneInterval', 'twoToFiveIntervals', 'sixIntervals')}
    issued = withheld = 0
    reasons = defaultdict(int)
    for history in histories:
        group = history['group']
        errors = {m: [] for m in METHODS[:-1]}
        last_target = 1
        for fold in history['folds']:
            if type(fold['targetIndex']) is not int or fold['targetIndex'] != last_target + 1:
                raise ValueError('Unordered folds')
            last_target = fold['targetIndex']
            if fold['eligible'] is False:
                withheld += 1
                reasons[fold['reason']] += 1
                errors = {m: [] for m in METHODS[:-1]}
                continue
            if fold['eligible'] is not True:
                raise ValueError('Invalid eligibility')
            actual = fold['actualDays']
            if type(actual) is not int or actual <= 0:
                raise ValueError('Invalid scoring target')
            prior = fold['priorIntervals']
            predictions = predict_candidates(prior, fold['baselineDays'], errors)
            if 'runtimeCandidateDays' in fold:
                runtime = fold['runtimeCandidateDays']
                if set(runtime) != {'currentMean6', 'median6', 'trimmedMean6'} or any(
                        type(value) is not int or predictions[name] != value
                        for name, value in runtime.items()):
                    raise ValueError('Actual app and research candidate differ')
            bucket = 'oneInterval' if len(prior) == 1 else 'twoToFiveIntervals' if len(prior) < 6 else 'sixIntervals'
            for method, value in predictions.items():
                error = abs(value - actual)
                add_score(scores[group][method], error)
                add_score(strata[bucket][method], error)
            # Score current targets only after ALL predictions, including the
            # personal expert, have been issued. Target changes cannot select
            # the expert that predicted those same targets.
            for method in METHODS[:-1]:
                errors[method] = (errors[method] + [abs(predictions[method] - actual)])[-6:]
            issued += 1
    if (issued != data['evaluatedPredictions'] or withheld != data['withheldPredictions']
            or issued + withheld != data['eligibleTargets'] or len(groups) != data['groups']
            or len(histories) != data['sourceHistories'] or dict(reasons) != data['withheldByReason']):
        raise ValueError('Export counts do not reconcile')
    return scores, strata


def evaluate(data, protocol):
    if (tuple(protocol['candidateOrder']) != METHODS or protocol['outerGroupFolds'] != 5
            or protocol['bootstrapReplicates'] != 2000 or protocol['primaryAccuracyToleranceDays'] != 3
            or protocol['candidateSpecificWithholding'] is not False
            or protocol['baselinePredictionVersion'] != BASELINE_VERSION):
        raise ValueError('Unsupported changes to frozen protocol')
    scores, strata = score_fold_data(data)
    assignment = assign_group_folds(list(scores), protocol['outerGroupFolds'], protocol['splitSeed'])
    selected = {}
    folds = []
    for k in range(protocol['outerGroupFolds']):
        training = [g for g in scores if assignment[g] != k]
        testing = [g for g in scores if assignment[g] == k]
        method = select_on_training(scores, training)
        for group in testing:
            selected[group] = scores[group][method]
        folds.append({'fold': k, 'trainingGroups': len(training), 'testGroups': len(testing),
                      'selectedOnTrainingGroupsOnly': method,
                      'baselineTest': summarize(scores[g][METHODS[0]] for g in testing),
                      'selectedTest': summarize(selected[g] for g in testing)})
    baseline = summarize(scores[g][METHODS[0]] for g in scores)
    heldout = summarize(selected.values())
    board = {m: summarize(scores[g][m] for g in scores) for m in METHODS}
    if any(v['evaluatedPredictions'] != baseline['evaluatedPredictions'] for v in board.values()):
        raise ValueError('Candidate coverage changed')
    return {
        'protocolVersion': protocol['protocolVersion'], 'protocolFreezeCommit': 'e3e147e', 'predictionVersion': BASELINE_VERSION,
        'dataScope': protocol['dataScope'], 'groupingAssurance': data['groupingAssurance'],
        'sourceHistories': data['sourceHistories'], 'groups': data['groups'],
        'eligibleTargets': data['eligibleTargets'], 'evaluatedPredictionsPerCandidate': baseline['evaluatedPredictions'],
        'withheldPredictionsPerCandidate': data['withheldPredictions'],
        'predictionCoverage': baseline['evaluatedPredictions'] / data['eligibleTargets'] if data['eligibleTargets'] else None,
        'withheldByReason': data['withheldByReason'], 'candidateSpecificWithholding': False,
        'runtimePointParityPerCandidate': {
            name: sum('runtimeCandidateDays' in fold for row in data['histories']
                      for fold in row['folds'] if fold['eligible'])
            for name in ('currentMean6', 'median6', 'trimmedMean6')},
        'fixedCandidateScoresExploratory': board,
        'selectionUsingOtherGroupsOnly': {'folds': folds, 'baseline': baseline, 'selectedOutOfFold': heldout},
        'uncertainty': paired_group_bootstrap(scores, selected, protocol['bootstrapReplicates'], protocol['bootstrapSeed']),
        'byAvailableSelectedHistory': strata,
        'ninetyPercentPointGoalReachedExploratory': heldout['fractionWithin3Days'] >= .90 if heldout['fractionWithin3Days'] is not None else False,
        'ninetyPercentAccuracyClaimSupported': False,
        'automaticPromotion': False, 'appModelChanged': False,
        'limitations': ['Previously examined development cohort; group separation does not undo earlier policy development on this dataset',
                        'Next recorded start may differ from next experienced biological period',
                        'Source-group bootstrap does not prove unique participant identities or representative Saudi performance',
                        'No independent/prospective clinical or fiqh validation'],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('external_folds_json', type=Path)
    parser.add_argument('--protocol', type=Path, default=DEFAULT_PROTOCOL)
    args = parser.parse_args()
    try:
        raw = args.external_folds_json.read_bytes()
        protocol_raw = args.protocol.read_bytes()
        if hashlib.sha256(protocol_raw).hexdigest() != FROZEN_PROTOCOL_SHA256:
            raise ValueError('Protocol differs from the pre-score freeze')
        result = evaluate(json.loads(raw), json.loads(protocol_raw))
        result['foldArtifactSHA256'] = hashlib.sha256(raw).hexdigest()
        result['protocolSHA256'] = hashlib.sha256(protocol_raw).hexdigest()
        print(json.dumps(result, indent=2, allow_nan=False))
    except (ValueError, TypeError, KeyError, OSError, ZeroDivisionError):
        parser.exit(1, 'Evaluation failed. Check frozen protocol, baseline export, group count and input integrity. No health records were printed.\n')


if __name__ == '__main__':
    main()
