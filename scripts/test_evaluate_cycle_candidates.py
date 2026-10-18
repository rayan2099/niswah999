import copy
import json
import unittest
from collections import defaultdict
from scripts.evaluate_cycle_candidates import (
    METHODS, BASELINE_VERSION, DEFAULT_PROTOCOL, assign_group_folds, empty_score,
    add_score, evaluate, paired_group_bootstrap, predict_candidates, rounded,
    score_fold_data, select_on_training,
)


def fixture(withheld=False):
    histories = []
    for group in range(10):
        fold = {'targetIndex': 2, 'eligible': not withheld}
        if withheld:
            fold['reason'] = 'unexplainedGap'
        else:
            fold.update(priorIntervals=[28], baselineDays=28, actualDays=28 + group % 3)
        histories.append({'group': group, 'folds': [fold]})
    return {'schemaVersion': 1, 'predictionVersion': BASELINE_VERSION,
            'groupingAssurance': 'synthetic test groups', 'sourceHistories': 10,
            'groups': 10, 'eligibleTargets': 10,
            'evaluatedPredictions': 0 if withheld else 10,
            'withheldPredictions': 10 if withheld else 0,
            'withheldByReason': {'unexplainedGap': 10} if withheld else {},
            'histories': histories}


class CandidateEvaluationTests(unittest.TestCase):
    def test_half_up_matches_dart(self):
        self.assertEqual(rounded(28.5), 29)
        result = predict_candidates([27, 28, 29, 30], 29, {})
        self.assertEqual(result['median6'], 29)

    def test_every_candidate_issues_for_each_baseline_eligible_case(self):
        for prior in ([28], [15, 16], [27, 28, 29, 30, 31, 32], [90, 90]):
            before = list(prior)
            result = predict_candidates(prior, rounded(sum(prior) / len(prior)), {})
            self.assertEqual(tuple(result), METHODS)
            self.assertTrue(all(type(x) is int and 15 <= x <= 90 for x in result.values()))
            self.assertEqual(prior, before)

    def test_window_center_uses_past_observations_and_deterministic_ties(self):
        result = predict_candidates([25, 25, 26, 27, 38], 28, {})
        self.assertLessEqual(abs(result['historicalWindowCenter3'] - 26), 1)
        self.assertEqual(predict_candidates([28], 28, {})['historicalWindowCenter3'], 28)

    def test_personal_expert_needs_four_past_forecasts(self):
        errors = {m: [10] * 3 for m in METHODS[:-1]}
        errors['lastInterval'] = [0] * 3
        self.assertEqual(predict_candidates([25, 25, 25, 30], 26, errors)['personalExpert'], 26)
        errors = {m: [10] * 4 for m in METHODS[:-1]}
        errors['lastInterval'] = [0] * 4
        self.assertEqual(predict_candidates([25, 25, 25, 30], 26, errors)['personalExpert'], 30)

    def test_heldout_group_outcomes_cannot_choose_training_winner(self):
        scores = {g: {m: empty_score() for m in METHODS} for g in range(3)}
        for g in scores:
            for method in METHODS:
                add_score(scores[g][method], 0 if method == 'median6' else 10)
        first = select_on_training(scores, [0, 1])
        for method in METHODS:
            scores[2][method]['within3'] = 0 if method == 'median6' else 1000000
        self.assertEqual(first, 'median6')
        self.assertEqual(select_on_training(scores, [0, 1]), first)

    def test_all_fragments_of_a_group_are_aggregated_before_splitting(self):
        data = fixture()
        extra = copy.deepcopy(data['histories'][0])
        data['histories'].append(extra)
        data['sourceHistories'] += 1
        data['eligibleTargets'] += 1
        data['evaluatedPredictions'] += 1
        scores, _ = score_fold_data(data)
        self.assertEqual(scores[0]['currentMean6']['n'], 2)
        assignment = assign_group_folds(list(scores), 5, 20261017)
        self.assertEqual(len(assignment), 10)
        self.assertEqual(set(assignment.values()), set(range(5)))
        self.assertEqual(assignment, assign_group_folds(list(scores), 5, 20261017))

    def test_export_counts_and_baseline_must_reconcile(self):
        data = fixture()
        data['histories'][0]['folds'][0]['baselineDays'] = 29
        with self.assertRaises(ValueError):
            score_fold_data(data)
        data = fixture()
        data['evaluatedPredictions'] += 1
        with self.assertRaises(ValueError):
            score_fold_data(data)

    def test_strict_features_reject_malformed_records(self):
        for prior in ([], [True], [14], [91], [28] * 7):
            with self.assertRaises(ValueError):
                predict_candidates(prior, 28, {})

    def test_paired_bootstrap_resamples_groups_and_identical_predictions_have_zero_delta(self):
        scores, _ = score_fold_data(fixture())
        selected = {g: scores[g]['currentMean6'] for g in scores}
        a = paired_group_bootstrap(scores, selected, 100, 12)
        b = paired_group_bootstrap(scores, selected, 100, 12)
        self.assertEqual(a, b)
        self.assertEqual(a['percentile95']['pairedAccuracyDifference'], [0, 0])
        self.assertEqual(a['percentile95']['pairedMAEDifferenceDays'], [0, 0])

    def test_frozen_validation_retains_coverage_and_never_auto_promotes(self):
        protocol = json.loads(DEFAULT_PROTOCOL.read_text())
        result = evaluate(fixture(), protocol)
        self.assertFalse(result['automaticPromotion'])
        self.assertFalse(result['appModelChanged'])
        self.assertFalse(result['ninetyPercentAccuracyClaimSupported'])
        self.assertEqual(result['predictionCoverage'], 1)
        self.assertEqual(result['selectionUsingOtherGroupsOnly']['selectedOutOfFold']['evaluatedPredictions'], 10)
        self.assertTrue(all(s['evaluatedPredictions'] == 10 for s in result['fixedCandidateScoresExploratory'].values()))
        self.assertEqual(sum(f['testGroups'] for f in result['selectionUsingOtherGroupsOnly']['folds']), 10)

    def test_empty_evaluation_never_invents_accuracy(self):
        result = evaluate(fixture(withheld=True), json.loads(DEFAULT_PROTOCOL.read_text()))
        self.assertIsNone(result['selectionUsingOtherGroupsOnly']['selectedOutOfFold']['fractionWithin3Days'])
        self.assertFalse(result['ninetyPercentPointGoalReachedExploratory'])
        self.assertEqual(result['predictionCoverage'], 0)

    def test_missing_intermediate_folds_are_rejected(self):
        data = fixture()
        data['histories'][0]['folds'][0]['targetIndex'] = 3
        with self.assertRaises(ValueError):
            score_fold_data(data)

    def test_bootstrap_does_not_treat_many_cycles_in_two_groups_as_many_people(self):
        scores = {g: {m: empty_score() for m in METHODS} for g in [0, 1]}
        for group in scores:
            for _ in range(100):
                add_score(scores[group]['currentMean6'], 0 if group == 0 else 10)
        selected = {g: scores[g]['currentMean6'] for g in scores}
        result = paired_group_bootstrap(scores, selected, 1000, 20261018)
        self.assertEqual(result['percentile95']['baselineFractionWithin3Days'], [0, 1])

    def test_runtime_prediction_parity_is_point_by_point_and_mismatches_fail(self):
        data = fixture()
        for row in data['histories']:
            row['folds'][0]['runtimeCandidateDays'] = {'currentMean6': 28, 'median6': 28, 'trimmedMean6': 28}
        result = evaluate(data, json.loads(DEFAULT_PROTOCOL.read_text()))
        self.assertEqual(result['runtimePointParityPerCandidate'], {'currentMean6': 10, 'median6': 10, 'trimmedMean6': 10})
        data['histories'][0]['folds'][0]['runtimeCandidateDays']['trimmedMean6'] = 29
        with self.assertRaises(ValueError):
            score_fold_data(data)

    def test_widened_metric_or_changed_coverage_policy_is_rejected(self):
        for key, value in [('primaryAccuracyToleranceDays', 7), ('candidateSpecificWithholding', True)]:
            protocol = json.loads(DEFAULT_PROTOCOL.read_text())
            protocol[key] = value
            with self.assertRaises(ValueError):
                evaluate(fixture(), protocol)


if __name__ == '__main__':
    unittest.main()
