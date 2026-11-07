#!/bin/sh
# Source after setting project_directory and test_directory. The two exported
# paths are explicit swiftc arguments so directories containing spaces work.
core_scoring_module_directory="$project_directory/Dependencies/PitcheeCore/platform/ios"
core_scoring_object="$test_directory/pitchee-scoring.o"
core_scoring_abi_source="$test_directory/pitchee-scoring-abi.cpp"
core_scoring_abi_object="$test_directory/pitchee-scoring-abi.o"
xcrun clang++ -std=c++17 -O2 -mmacosx-version-min=14.0 \
    -I "$project_directory/Dependencies/PitcheeCore/src" \
    -I "$project_directory/Dependencies/PitcheeCore/include" \
    -c "$project_directory/Dependencies/PitcheeCore/src/scoring.cpp" \
    -o "$core_scoring_object"

# The standalone scoring source contains the implementation used by Core, but
# its C ABI adapters live in analyzer.cpp. Pulling that full analyzer into
# small Swift tests would also pull model/runtime dependencies they never use.
# Keep the test fixture's adapter local and behaviorally identical to Core's
# public composite-score entry points.
cat > "$core_scoring_abi_source" <<'EOF'
#include "internal.hpp"
#include "pitchee/pitchee.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace {

bool valid_score_profile(pitchee_score_profile_t profile) {
    return profile == PITCHEE_SCORE_PROFILE_FEMINIZATION
        || profile == PITCHEE_SCORE_PROFILE_MASCULINIZATION;
}

}  // namespace

extern "C" pitchee_status_t pitchee_score(
    pitchee_score_profile_t score_profile,
    double vfp_standard_score,
    double naturalness_score,
    double f0_hz,
    pitchee_score_result_t* out_score
) {
    if (!valid_score_profile(score_profile) || !out_score) {
        return PITCHEE_ERROR_INVALID_ARGUMENT;
    }
    const auto score = pitchee::calculate_composite_score(
        score_profile,
        vfp_standard_score,
        naturalness_score,
        std::isfinite(f0_hz) && f0_hz > 0.0,
        f0_hz
    );
    out_score->base_score = score.base_score;
    out_score->final_score = score.final_score;
    out_score->has_score_cap = score.has_score_cap ? 1 : 0;
    out_score->score_cap = score.score_cap;
    out_score->score_limited = score.score_limited ? 1 : 0;
    out_score->score_boosted = score.score_boosted ? 1 : 0;
    std::memset(out_score->score_rule, 0, sizeof(out_score->score_rule));
    std::memcpy(
        out_score->score_rule,
        score.score_rule.c_str(),
        std::min(sizeof(out_score->score_rule) - 1, score.score_rule.size())
    );
    return PITCHEE_SUCCESS;
}

extern "C" double pitchee_composite_score_value(
    pitchee_score_profile_t score_profile,
    double vfp_standard_score,
    double naturalness_score,
    double f0_hz
) {
    if (!valid_score_profile(score_profile)) {
        return std::numeric_limits<double>::quiet_NaN();
    }
    const bool has_f0 = std::isfinite(f0_hz) && f0_hz > 0.0;
    return pitchee::calculate_composite_score(
        score_profile,
        vfp_standard_score,
        naturalness_score,
        has_f0,
        f0_hz
    ).final_score;
}
EOF

xcrun clang++ -std=c++17 -O2 -mmacosx-version-min=14.0 \
    -I "$project_directory/Dependencies/PitcheeCore/src" \
    -I "$project_directory/Dependencies/PitcheeCore/include" \
    -c "$core_scoring_abi_source" \
    -o "$core_scoring_abi_object"

xcrun ld -r "$core_scoring_object" "$core_scoring_abi_object" \
    -o "$test_directory/pitchee-scoring-combined.o"
core_scoring_object="$test_directory/pitchee-scoring-combined.o"
