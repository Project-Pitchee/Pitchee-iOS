#include "RealtimeAtomics.h"

#include <stdatomic.h>
#include <stdlib.h>

// Never permit a platform where these primitives can fall back to locks in
// libatomic. arm64 iOS devices and arm64/x86_64 simulators satisfy this check.
_Static_assert(__atomic_always_lock_free(sizeof(uint64_t), 0),
               "Realtime capture requires always-lock-free 64-bit atomics");

struct PitcheeAudioAtomicUInt64 {
    _Atomic(uint64_t) value;
};

PitcheeAudioAtomicUInt64 *pitchee_audio_atomic_create(uint64_t initial_value) {
    PitcheeAudioAtomicUInt64 *atomic = malloc(sizeof(*atomic));
    if (atomic != NULL) atomic_init(&atomic->value, initial_value);
    return atomic;
}

void pitchee_audio_atomic_destroy(PitcheeAudioAtomicUInt64 *atomic) {
    free(atomic);
}

uint64_t pitchee_audio_atomic_load_acquire(const PitcheeAudioAtomicUInt64 *atomic) {
    return atomic_load_explicit(&atomic->value, memory_order_acquire);
}

void pitchee_audio_atomic_store_release(PitcheeAudioAtomicUInt64 *atomic, uint64_t value) {
    atomic_store_explicit(&atomic->value, value, memory_order_release);
}

uint64_t pitchee_audio_atomic_compare_exchange_acq_rel(PitcheeAudioAtomicUInt64 *atomic,
                                                       uint64_t expected, uint64_t desired) {
    atomic_compare_exchange_strong_explicit(&atomic->value, &expected, desired,
                                            memory_order_acq_rel, memory_order_acquire);
    return expected;
}

void pitchee_audio_atomic_or_acq_rel(PitcheeAudioAtomicUInt64 *atomic, uint64_t mask) {
    atomic_fetch_or_explicit(&atomic->value, mask, memory_order_acq_rel);
}

void pitchee_audio_atomic_and_release(PitcheeAudioAtomicUInt64 *atomic, uint64_t mask) {
    atomic_fetch_and_explicit(&atomic->value, mask, memory_order_release);
}
