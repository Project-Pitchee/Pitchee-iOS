#ifndef PITCHEE_REALTIME_ATOMICS_H
#define PITCHEE_REALTIME_ATOMICS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Storage is allocated before an audio tap is installed and destroyed only
// after its ring is no longer reachable by either producer or consumer.
typedef struct PitcheeAudioAtomicUInt64 PitcheeAudioAtomicUInt64;
PitcheeAudioAtomicUInt64 *pitchee_audio_atomic_create(uint64_t initial_value);
void pitchee_audio_atomic_destroy(PitcheeAudioAtomicUInt64 *atomic);

uint64_t pitchee_audio_atomic_load_acquire(const PitcheeAudioAtomicUInt64 *atomic);
void pitchee_audio_atomic_store_release(PitcheeAudioAtomicUInt64 *atomic, uint64_t value);
// Returns the observed old value. Equality with expected means exchange
// succeeded; the strong operation never returns a spurious failure.
uint64_t pitchee_audio_atomic_compare_exchange_acq_rel(PitcheeAudioAtomicUInt64 *atomic,
                                                       uint64_t expected, uint64_t desired);
void pitchee_audio_atomic_or_acq_rel(PitcheeAudioAtomicUInt64 *atomic, uint64_t mask);
void pitchee_audio_atomic_and_release(PitcheeAudioAtomicUInt64 *atomic, uint64_t mask);

#ifdef __cplusplus
}
#endif

#endif
