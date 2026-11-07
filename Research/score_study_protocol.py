"""Offline design reference. No network, app-state loader or production DP release.

The Gaussian/zCDP calculations describe an ideal mathematical mechanism. They
are not a finite-precision or distributed-noise implementation. Simulation uses
seeded PRNGs elsewhere and must never be used to protect real contributions.
"""

from dataclasses import dataclass
import json
import math
from pathlib import Path
from statistics import NormalDist


DIRECTIONS = ("feminine", "masculine")
FIELDS = (
    "invited_installation", "rated_fraction", "unable_fraction",
    "skipped_fraction", "timed_out_fraction", "response_interrupted_fraction",
    "analysis_unavailable_fraction", "analysis_failed_fraction",
    "analysis_interrupted_fraction", "paired_installation", "pair_coverage",
    "mean_delta_over_four", "squared_installation_mean",
)
DIMENSIONS = len(DIRECTIONS) * len(FIELDS)
SCALE = math.sqrt(12)
EVIDENCE = (
    "frozen_model_core_and_rule_identity", "separate_online_consent",
    "reviewed_secure_aggregation_and_noise", "unlinked_eligibility_and_replay_prevention",
    "durable_cross_study_privacy_accounting", "fixed_schedule_and_threshold_transcript_review",
    "device_storage_and_withdrawal_validation", "independent_label_and_power_review",
)


def _keys(value, expected):
    if type(value) is not dict or set(value) != set(expected):
        raise ValueError("Unexpected or missing fields in fixed schema")


def _integer(value, lower, upper):
    if type(value) is not int or not lower <= value <= upper:
        raise ValueError("Integer outside registered bounds")
    return value


def _number(value, lower, upper):
    if type(value) not in (int, float) or not math.isfinite(value) or not lower <= value <= upper:
        raise ValueError("Nonfinite or out-of-range number")
    return float(value)


def _json_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON field")
        result[key] = value
    return result


@dataclass(frozen=True)
class PrivacyPlan:
    epsilon_cap: float
    delta: float
    max_releases: int

    def __post_init__(self):
        _number(self.epsilon_cap, 0.01, 2)
        _number(self.delta, 1e-12, 1e-7)
        _integer(self.max_releases, 1, 13)

    @property
    def total_rho(self):
        # Stable form of (sqrt(log(1/delta) + epsilon) - sqrt(log(1/delta)))**2.
        log_delta = math.log(1 / self.delta)
        return (self.epsilon_cap / (math.sqrt(log_delta + self.epsilon_cap) + math.sqrt(log_delta))) ** 2

    @property
    def per_release_rho(self):
        return self.total_rho / self.max_releases

    @property
    def sigma(self):
        # Add/remove one installation with whole-vector L2 norm <= 1.
        return 1 / math.sqrt(2 * self.per_release_rho)

    def epsilon_after(self, releases):
        _integer(releases, 0, self.max_releases)
        return compose_epsilon([self.per_release_rho] * releases, self.delta)


def compose_epsilon(rho_costs, delta):
    """Cross-query/study mathematical composition, not a durable budget ledger."""
    _number(delta, 1e-12, 1e-7)
    costs = [_number(cost, 0, 1e6) for cost in rho_costs]
    rho = math.fsum(costs)
    return rho + 2 * math.sqrt(rho * math.log(1 / delta))


@dataclass(frozen=True)
class AnalysisPolicy:
    minimum_installations: int
    practical_margin_ordinal: float
    noise_family_alpha: float
    sampling_family_alpha: float

    def __post_init__(self):
        _integer(self.minimum_installations, 100, 1000000)
        _number(self.practical_margin_ordinal, 0, 4)
        _number(self.noise_family_alpha, 1e-6, 0.049)
        _number(self.sampling_family_alpha, 1e-6, 0.049)
        if self.noise_family_alpha + self.sampling_family_alpha > 0.05 + 1e-12:
            raise ValueError("Family uncertainty allowance exceeds 0.05")


@dataclass(frozen=True)
class DraftStudy:
    privacy: PrivacyPlan
    analysis: AnalysisPolicy

    @staticmethod
    def load(path: Path):
        if path.stat().st_size > 16384:
            raise ValueError("Manifest exceeds size limit")
        data = json.loads(path.read_text(), object_pairs_hook=_json_pairs)
        return DraftStudy.from_dict(data)

    @staticmethod
    def from_dict(data):
        _keys(data, ("schema_version", "mode", "study_id", "consent_id", "baseline_id",
                     "candidate_id", "directions", "sampling", "vector", "privacy", "analysis", "launch_evidence"))
        constants = {
            "schema_version": 1, "mode": "offline_design_only",
            "study_id": "pitchee.score-alignment.v1.draft", "consent_id": "online-score-alignment.v1.draft",
            "baseline_id": "direction-score-v1", "candidate_id": "continuous-base-v1",
            "directions": list(DIRECTIONS),
        }
        for key, expected in constants.items():
            if type(data[key]) is not type(expected) or data[key] != expected:
                raise ValueError("Unregistered study definition")
        sampling = {"invitation_probability": 0.25, "max_invitations": 5,
                    "max_screens": 100, "batch_days": 7, "horizon_days": 90}
        vector = {"definition": "installation-means-26-v1", "dimensions": 26,
                  "scale_squared": 12, "l2_bound": 1.0}
        for key, expected in (("sampling", sampling), ("vector", vector)):
            _keys(data[key], expected)
            if any(type(data[key][k]) is not type(v) or data[key][k] != v for k, v in expected.items()):
                raise ValueError("Unregistered sampling/vector definition")
        privacy = data["privacy"]
        _keys(privacy, ("unit", "adjacency", "mechanism", "epsilon_cap", "delta", "max_releases", "use_sampling_amplification"))
        if (privacy["unit"] != "installation" or privacy["adjacency"] != "add_remove"
                or privacy["mechanism"] != "ideal_gaussian_zcdp" or privacy["use_sampling_amplification"] is not False):
            raise ValueError("Unsupported privacy assumptions")
        _keys(data["analysis"], ("minimum_installations", "practical_margin_ordinal", "noise_family_alpha", "sampling_family_alpha"))
        _keys(data["launch_evidence"], EVIDENCE)
        if any(value is not None for value in data["launch_evidence"].values()):
            raise ValueError("Offline tool cannot validate or grant launch approval")
        return DraftStudy(
            PrivacyPlan(privacy["epsilon_cap"], privacy["delta"], privacy["max_releases"]),
            AnalysisPolicy(**data["analysis"]),
        )

    @property
    def readiness(self):
        return {"online_collection_allowed": False, "missing_evidence": list(EVIDENCE)}


def validate_summary(summary):
    """Only completed fixed aggregates; not an app state or arbitrary payload."""
    _keys(summary, ("screened", "invited", "responses", "analyses", "lossDifferences"))
    screened = _integer(summary["screened"], 0, 100)
    invited = _integer(summary["invited"], 0, 5)
    if invited > screened:
        raise ValueError("Invitation denominator exceeds screening count")
    for key, size in (("responses", 5), ("analyses", 4), ("lossDifferences", 9)):
        values = summary[key]
        if type(values) is not list or len(values) != size:
            raise ValueError("Unexpected aggregate dimensions")
        for value in values:
            _integer(value, 0, invited)
    if sum(summary["responses"]) != invited or sum(summary["analyses"]) != invited:
        raise ValueError("Unfinished observations cannot be finalized")
    rated, comparable = summary["responses"][0], summary["analyses"][0]
    paired = sum(summary["lossDifferences"])
    if not max(0, rated + comparable - invited) <= paired <= min(rated, comparable):
        raise ValueError("Inconsistent paired intersection")


def contribution(summaries):
    """26 numbers in memory. No identity, recording, timestamps or serialization.

    All valid vectors receive the SAME scale. Data-dependent clipping would
    change installation weights and silently change the intended estimand.
    """
    if type(summaries) is not list or len(summaries) != 2:
        raise ValueError("Both fixed direction slots are required")
    for summary in summaries:
        validate_summary(summary)
    if sum(s["screened"] for s in summaries) > 100 or sum(s["invited"] for s in summaries) > 5:
        raise ValueError("Combined installation contribution limit exceeded")
    vector = []
    for summary in summaries:
        invited = summary["invited"]
        if not invited:
            vector.extend([0.0] * len(FIELDS))
            continue
        histogram = summary["lossDifferences"]
        paired = sum(histogram)
        mean = sum((index - 4) * count for index, count in enumerate(histogram)) / (4 * paired) if paired else 0.0
        vector.extend([
            1.0, *(value / invited for value in summary["responses"]),
            *(value / invited for value in summary["analyses"][1:]),
            float(paired > 0), paired / invited, mean, mean * mean,
        ])
    scaled = tuple(value / SCALE for value in vector)
    if math.fsum(value * value for value in scaled) > 1 + 1e-12:
        raise ValueError("Whole-vector sensitivity bound violated")
    return scaled


def noise_envelope(plan: PrivacyPlan, policy: AnalysisPolicy):
    # Union bound across every coordinate, both directions and all releases.
    tail = policy.noise_family_alpha / (2 * DIMENSIONS * plan.max_releases)
    return plan.sigma * NormalDist().inv_cdf(1 - tail)


def postprocess(noisy_vector, plan: PrivacyPlan, policy: AnalysisPolicy):
    """Consumes ONLY an already noised aggregate, never exact counts.

    This is post-processing of the hypothetical DP release. It does NOT resolve
    leakage from a real secure-aggregation quorum/abort/network transcript.
    """
    if len(noisy_vector) != DIMENSIONS:
        raise ValueError("Wrong release dimensions")
    for value in noisy_vector:
        _number(value, -1e15, 1e15)
    radius = noise_envelope(plan, policy)
    lower_required = policy.minimum_installations / SCALE
    reports = {}
    for offset, direction in enumerate(DIRECTIONS):
        values = noisy_vector[offset * len(FIELDS):(offset + 1) * len(FIELDS)]
        invited_lower = values[0] - radius
        if invited_lower < lower_required:
            reports[direction] = {"status": "suppressed"}
            continue
        result = {"status": "descriptive", "invited_installations_estimate": max(0.0, values[0] * SCALE)}
        for index in range(1, 9):
            result[FIELDS[index]] = min(1.0, max(0.0, values[index] / values[0]))
        result["pair_coverage"] = min(1.0, max(0.0, values[10] / values[0]))
        paired_lower = values[9] - radius
        if paired_lower < lower_required:
            result["comparison_status"] = "suppressed"
            reports[direction] = result
            continue
        denominator = (paired_lower, values[9] + radius)
        numerator = (values[11] - radius, values[11] + radius)
        corners = [4 * num / den for num in numerator for den in denominator]
        noise_interval = [max(-4.0, min(corners)), min(4.0, max(corners))]
        # No feasible bounded mean under this noise envelope: suppress rather
        # than invert an interval. May occur outside the simultaneous tail event.
        if noise_interval[0] > noise_interval[1]:
            result["comparison_status"] = "inconsistent_noisy_statistics"
            reports[direction] = result
            continue
        n_lower = paired_lower * SCALE
        alpha = policy.sampling_family_alpha / (len(DIRECTIONS) * plan.max_releases)
        sampling_radius = 4 * math.sqrt(2 * math.log(2 / alpha) / n_lower)
        interval = [max(-4.0, noise_interval[0] - sampling_radius), min(4.0, noise_interval[1] + sampling_radius)]
        result.update({
            "comparison_status": "estimated",
            "paired_installations_estimate": max(0.0, values[9] * SCALE),
            "mean_delta_ordinal": min(4.0, max(-4.0, 4 * values[11] / values[9])),
            # Descriptive planning estimate only; clipping/ratio noise can bias
            # it. It is never substituted into the conservative inference bound.
            "installation_delta_variance_estimate": 16 * min(1.0, max(0.0,
                values[12] / values[9] - (values[11] / values[9]) ** 2)),
            "sample_mean_noise_interval": noise_interval,
            "iid_participant_mean_interval": interval,
            "alignment_signal": interval[1] < -policy.practical_margin_ordinal,
        })
        reports[direction] = result
    return reports
