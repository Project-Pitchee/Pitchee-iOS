import copy
from dataclasses import replace
import importlib.util
import json
import math
from pathlib import Path
import random
import tempfile
import unittest

from Research.score_study_protocol import (
    DIMENSIONS, EVIDENCE, FIELDS, SCALE, AnalysisPolicy, DraftStudy, PrivacyPlan,
    compose_epsilon, contribution, noise_envelope, postprocess,
)

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "Research/score-study-v1.draft.json"


def summary(deltas=(), responses=None, analyses=None, screened=None):
    histogram = [0] * 9
    for delta in deltas:
        histogram[delta + 4] += 1
    invited = sum(responses) if responses is not None else len(deltas)
    return {"screened": invited if screened is None else screened, "invited": invited,
            "responses": list(responses) if responses is not None else [invited, 0, 0, 0, 0],
            "analyses": list(analyses) if analyses is not None else [invited, 0, 0, 0],
            "lossDifferences": histogram}


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.study = DraftStudy.load(MANIFEST)
        self.manifest = json.loads(MANIFEST.read_text())

    def test_draft_never_grants_online_collection(self):
        self.assertFalse(self.study.readiness["online_collection_allowed"])
        self.assertEqual(set(self.study.readiness["missing_evidence"]), set(EVIDENCE))
        for key, value in (("mode", "online"), ("baseline_id", "other"), ("schema_version", True)):
            bad = copy.deepcopy(self.manifest)
            bad[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                DraftStudy.from_dict(bad)

    def test_transport_and_unverified_approval_cannot_be_added(self):
        bad = copy.deepcopy(self.manifest)
        bad["endpoint"] = "https://example.invalid"
        with self.assertRaises(ValueError):
            DraftStudy.from_dict(bad)
        bad = copy.deepcopy(self.manifest)
        bad["launch_evidence"][EVIDENCE[0]] = "approved"
        with self.assertRaises(ValueError):
            DraftStudy.from_dict(bad)

    def test_json_duplicate_size_and_nonfinite_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.json"
            path.write_text('{"mode":"offline_design_only","mode":"offline_design_only"}')
            with self.assertRaises(ValueError):
                DraftStudy.load(path)
            path.write_text(" " * 16385)
            with self.assertRaises(ValueError):
                DraftStudy.load(path)
        for bad_value in (float("nan"), float("inf"), -1, True):
            bad = copy.deepcopy(self.manifest)
            bad["privacy"]["epsilon_cap"] = bad_value
            with self.subTest(value=bad_value), self.assertRaises(ValueError):
                DraftStudy.from_dict(bad)

    def test_assumptions_must_match_sensitivity_proof(self):
        for section, field, value in (("privacy", "adjacency", "replace"),
                                     ("privacy", "unit", "person"),
                                     ("privacy", "use_sampling_amplification", True),
                                     ("vector", "dimensions", 25),
                                     ("vector", "l2_bound", True),
                                     ("sampling", "max_invitations", 6)):
            bad = copy.deepcopy(self.manifest)
            bad[section][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                DraftStudy.from_dict(bad)

    def test_direction_order_and_sign_are_fixed(self):
        vector = contribution([summary([-4]), summary([4])])
        self.assertEqual(len(vector), 26)
        self.assertAlmostEqual(vector[11] * SCALE, -1)
        self.assertAlmostEqual(vector[24] * SCALE, 1)
        self.assertAlmostEqual(vector[12] * SCALE, 1)
        self.assertAlmostEqual(sum(v*v for v in vector), 1)

    def test_empty_and_unselected_observations_carry_no_private_counts(self):
        self.assertEqual(contribution([summary(screened=100), summary()]), (0.0,) * 26)

    def test_high_frequency_installations_do_not_get_extra_mean_weight(self):
        once = contribution([summary([-2]), summary()])
        repeated = contribution([summary([-2] * 5), summary()])
        self.assertEqual(once, repeated)

    def test_squared_mean_is_between_installation_not_within_recording_moment(self):
        vector = contribution([summary([-4, 4]), summary()])
        self.assertEqual(vector[11], 0)
        self.assertEqual(vector[12], 0)
        self.assertAlmostEqual(vector[10] * SCALE, 1)

    def test_all_missing_retains_invited_denominator_without_fabricating_pairs(self):
        value = summary(responses=[0, 1, 1, 1, 1], analyses=[1, 1, 1, 1])
        vector = contribution([value, summary()])
        self.assertAlmostEqual(vector[0] * SCALE, 1)
        self.assertAlmostEqual(vector[2] * SCALE, 0.25)
        self.assertAlmostEqual(vector[7] * SCALE, 0.25)
        self.assertEqual(vector[9:13], (0, 0, 0, 0))

    def test_unfinished_or_impossible_intersections_are_rejected(self):
        pending = summary([-1])
        pending["analyses"] = [0, 0, 0, 0]
        impossible = summary([-1])
        impossible["lossDifferences"] = [0]*9
        for value in (pending, impossible):
            with self.assertRaises(ValueError):
                contribution([value, summary()])

    def test_no_extra_identity_audio_or_arbitrary_fields(self):
        for key in ("audio", "recordingID", "feedback", "timestamp", "transcript"):
            bad = summary([-1])
            bad[key] = "not-permitted"
            with self.subTest(key=key), self.assertRaises(ValueError):
                contribution([bad, summary()])

    def test_counts_are_strict_and_limits_apply_across_directions(self):
        for key, value in (("invited", True), ("screened", 101), ("invited", 1.0)):
            bad = summary([-1])
            bad[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                contribution([bad, summary()])
        with self.assertRaises(ValueError):
            contribution([summary([-1]*3), summary([-1]*3)])
        with self.assertRaises(ValueError):
            contribution([summary(screened=60), summary(screened=60)])

    def test_norm_bound_for_reproducible_generated_terminal_states(self):
        rng = random.Random(42)
        for _ in range(2000):
            values = [summary(), summary()]
            for _ in range(rng.randrange(6)):
                target = values[rng.randrange(2)]
                target["screened"] += 1
                target["invited"] += 1
                response, analysis = rng.randrange(5), rng.randrange(4)
                target["responses"][response] += 1
                target["analyses"][analysis] += 1
                if response == analysis == 0:
                    target["lossDifferences"][rng.randrange(9)] += 1
            vector = contribution(values)
            self.assertLessEqual(sum(v*v for v in vector), 1 + 1e-12)

    def test_gaussian_composition_has_known_values(self):
        self.assertAlmostEqual(compose_epsilon([0.5], 1e-7), 0.5 + 2*math.sqrt(0.5*math.log(1e7)))
        plan = self.study.privacy
        self.assertEqual(plan.epsilon_after(0), 0)
        self.assertAlmostEqual(plan.epsilon_after(13), 2, places=12)
        self.assertLess(plan.epsilon_after(1), 2)
        self.assertAlmostEqual(1/(2*plan.sigma**2), plan.per_release_rho)
        single = replace(plan, max_releases=1)
        self.assertAlmostEqual(plan.sigma / single.sigma, math.sqrt(13))

    def test_budget_does_not_treat_extra_queries_as_free(self):
        plan = self.study.privacy
        with self.assertRaises(ValueError):
            plan.epsilon_after(14)
        self.assertGreater(compose_epsilon([plan.per_release_rho]*14, plan.delta), 2)
        self.assertGreater(compose_epsilon([plan.total_rho]*2, plan.delta), 2)
        for cost in (float("nan"), -1, True):
            with self.assertRaises(ValueError):
                compose_epsilon([cost], plan.delta)

    def test_large_negative_counts_and_empty_groups_are_suppressed(self):
        for vector in ([0.0]*26, [-1000.0]*26):
            report = postprocess(vector, self.study.privacy, self.study.analysis)
            self.assertEqual(report, {direction: {"status":"suppressed"} for direction in ("feminine", "masculine")})

    def test_gate_uses_noisy_lower_bound_instead_of_raw_point_count(self):
        radius = noise_envelope(self.study.privacy, self.study.analysis)
        vector = [0.0]*26
        vector[0] = (100/SCALE) + radius - 0.001
        report = postprocess(vector, self.study.privacy, self.study.analysis)
        self.assertEqual(report["feminine"]["status"], "suppressed")
        vector[0] += 0.002
        report = postprocess(vector, self.study.privacy, self.study.analysis)
        self.assertEqual(report["feminine"]["status"], "descriptive")
        self.assertEqual(report["feminine"]["comparison_status"], "suppressed")

    def test_uncertainty_includes_noise_and_sampling_not_only_higher_scores(self):
        base = contribution([summary([-1]), summary()])
        report = postprocess([20000*v for v in base], self.study.privacy, self.study.analysis)["feminine"]
        self.assertTrue(report["alignment_signal"])
        lo, hi = report["iid_participant_mean_interval"]
        self.assertLess(lo, -1)
        self.assertGreater(hi, -1)
        self.assertLess(hi, -0.25)
        null = contribution([summary([-1,1]), summary()])
        report = postprocess([20000*v for v in null], self.study.privacy, self.study.analysis)["feminine"]
        self.assertFalse(report["alignment_signal"])

    def test_bad_noisy_releases_are_rejected(self):
        for vector in ([0.0]*25, [float("nan")]*26, [True]*26):
            with self.assertRaises(ValueError):
                postprocess(vector, self.study.privacy, self.study.analysis)
        with self.assertRaises(ValueError):
            AnalysisPolicy(100, 0.25, 0.03, 0.03)

    def test_synthetic_fast_sum_matches_real_encoder_on_toy_population(self):
        spec = importlib.util.spec_from_file_location("simulate", ROOT / "Scripts/evaluate-score-study.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        for alternative in (False, True):
            deltas = [-1, -1, 0 if alternative else 1]
            population = [contribution([summary([delta]), summary()]) for delta in deltas]
            population.extend([contribution([summary(responses=[0,1,0,0,0]), summary()])]*3)
            actual = [math.fsum(vector[i] for vector in population) for i in range(DIMENSIONS)]
            expected = module.synthetic_sum(3, 6, 2, alternative)
            for left, right in zip(actual, expected):
                self.assertAlmostEqual(left, right)


if __name__ == "__main__":
    unittest.main()
