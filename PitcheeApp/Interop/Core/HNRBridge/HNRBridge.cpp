#include "HNRBridge.h"
#include "internal.hpp"
#include "wav_reader.hpp"

#include <cstdio>
#include <cstring>
#include <stdexcept>

static_assert(pitchee::kMaximumSeconds == std::numeric_limits<double>::infinity(),
              "Mirror Core input truncation before changing its duration cap.");

namespace {
pitchee_status_t fail(pitchee_status_t status, const char* message, char* error, size_t capacity) {
    if (error && capacity > 0) std::snprintf(error, capacity, "%s", message);
    return status;
}
}

pitchee_status_t pitchee_app_hnr_analyze_pcm(
    const float* samples, size_t sample_count, int32_t sample_rate, int32_t channels,
    const pitchee_hnr_vad_segment_t* vad_segments, size_t vad_segment_count,
    pitchee_hnr_window_callback_t callback, void* context,
    pitchee_hnr_summary_t* summary, char* error_message, size_t error_capacity
) {
    try {
        const auto pcm = pitchee::resample_mono(
            samples, sample_count, channels, sample_rate, pitchee::kSampleRate
        );
        const auto status = pitchee_hnr_analyze(
            pcm.data(), pcm.size(), vad_segments, vad_segment_count, callback, context, summary
        );
        if (status != PITCHEE_SUCCESS) {
            return fail(status, "Invalid HNR arguments.", error_message, error_capacity);
        }
        return status;
    } catch (const std::invalid_argument& error) {
        return fail(PITCHEE_ERROR_INVALID_ARGUMENT, error.what(), error_message, error_capacity);
    } catch (const std::exception& error) {
        return fail(PITCHEE_ERROR_INTERNAL, error.what(), error_message, error_capacity);
    } catch (...) {
        return fail(PITCHEE_ERROR_INTERNAL, "Unable to analyze HNR.", error_message, error_capacity);
    }
}

pitchee_status_t pitchee_app_hnr_analyze_wav(
    const char* path,
    const pitchee_hnr_vad_segment_t* vad_segments, size_t vad_segment_count,
    pitchee_hnr_window_callback_t callback, void* context,
    pitchee_hnr_summary_t* summary, char* error_message, size_t error_capacity
) {
    if (!path) return fail(PITCHEE_ERROR_INVALID_ARGUMENT, "Invalid WAV path.", error_message, error_capacity);
    try {
        const auto wav = pitchee::read_wav(path);
        return pitchee_app_hnr_analyze_pcm(
            wav.samples.data(), wav.samples.size(), wav.sample_rate, wav.channels,
            vad_segments, vad_segment_count, callback, context, summary, error_message, error_capacity
        );
    } catch (const std::exception& error) {
        const auto status = std::strstr(error.what(), "unsupported WAV") ? PITCHEE_ERROR_UNSUPPORTED_FORMAT
            : std::strstr(error.what(), "WAV") ? PITCHEE_ERROR_IO : PITCHEE_ERROR_INTERNAL;
        return fail(status, error.what(), error_message, error_capacity);
    } catch (...) {
        return fail(PITCHEE_ERROR_INTERNAL, "Unable to read HNR audio.", error_message, error_capacity);
    }
}
