#ifndef PITCHEE_APP_HNR_BRIDGE_H
#define PITCHEE_APP_HNR_BRIDGE_H

#include "pitchee/hnr.h"

#ifdef __cplusplus
extern "C" {
#endif

// Reuse Core's decoding, resampling and PCM16 quantization before independent HNR.
pitchee_status_t pitchee_app_hnr_analyze_pcm(
    const float* samples, size_t sample_count, int32_t sample_rate, int32_t channels,
    const pitchee_hnr_vad_segment_t* vad_segments, size_t vad_segment_count,
    pitchee_hnr_window_callback_t callback, void* context,
    pitchee_hnr_summary_t* summary, char* error_message, size_t error_capacity
);

pitchee_status_t pitchee_app_hnr_analyze_wav(
    const char* path,
    const pitchee_hnr_vad_segment_t* vad_segments, size_t vad_segment_count,
    pitchee_hnr_window_callback_t callback, void* context,
    pitchee_hnr_summary_t* summary, char* error_message, size_t error_capacity
);

#ifdef __cplusplus
}
#endif

#endif
