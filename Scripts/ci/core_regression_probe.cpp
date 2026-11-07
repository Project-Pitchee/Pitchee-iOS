// Recompiled against EACH checkpoint's public headers to avoid ctypes ABI guesses.
// Adapted from the line6 analyze-corpus / compare-hnr public-API experiment.
#include <pitchee/pitchee.h>
#include <pitchee/hnr.h>
#include "internal.hpp"
#include "wav_reader.hpp"
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

static void number(double value) {
    if (std::isfinite(value)) std::cout << std::setprecision(17) << value;
    else std::cout << "null";
}

int main(int argc, char** argv) {
    try {
        if (argc < 2) throw std::runtime_error("Missing mode");
        std::string mode(argv[1]);
        if (mode == "full" && argc == 5) {
            char error[2048]{};
            pitchee_analyzer_t* analyzer = nullptr;
            // One CPU thread is repeatable across old/new; this is not a device backend test.
            auto status = pitchee_analyzer_create(argv[2], 1, 0, 0, 0, 0, &analyzer, error, sizeof(error));
            if (status != PITCHEE_SUCCESS || !analyzer) throw std::runtime_error(error);
            char* json = nullptr;
            status = pitchee_analyze_wav_file(analyzer, argv[3],
                static_cast<pitchee_score_profile_t>(std::stoi(argv[4])), nullptr, nullptr,
                &json, error, sizeof(error));
            if (status == PITCHEE_SUCCESS && json) std::cout << json << '\n';
            if (json) pitchee_string_free(json);
            pitchee_analyzer_destroy(analyzer);
            if (status != PITCHEE_SUCCESS) throw std::runtime_error(error);
            return 0;
        }
        if (mode == "hnr" && argc == 4) {
            // Match the App bridge, including Core's PCM16 quantization for
            // Float32 WAV. Never mistake float WAV bytes for integer samples.
            const auto wav = pitchee::read_wav(argv[2]);
            const auto samples = pitchee::resample_mono(wav.samples.data(), wav.samples.size(),
                wav.channels, wav.sample_rate, pitchee::kSampleRate);
            std::ifstream intervals(argv[3]);
            if (!intervals) throw std::runtime_error("Cannot read VAD intervals");
            std::vector<pitchee_hnr_vad_segment_t> vad;
            double start, end;
            while (intervals >> start >> end) vad.push_back({start, end});
            if (!intervals.eof()) throw std::runtime_error("Malformed VAD intervals");
            std::vector<pitchee_hnr_window_t> windows;
            pitchee_hnr_summary_t summary{};
            auto status = pitchee_hnr_analyze(samples.data(), samples.size(), vad.data(), vad.size(),
                [](const pitchee_hnr_window_t* window, void* context) {
                    static_cast<std::vector<pitchee_hnr_window_t>*>(context)->push_back(*window);
                }, &windows, &summary);
            if (status != PITCHEE_SUCCESS) throw std::runtime_error("Independent HNR call failed");
            size_t valid = 0;
            for (const auto& window : windows) if (window.has_hnr) {
                if (!std::isfinite(window.hnr_db)) throw std::runtime_error("Non-finite valid HNR window");
                ++valid;
            }
            if (valid != static_cast<size_t>(summary.hnr_window_count) ||
                bool(summary.has_hnr) != (valid > 0)) throw std::runtime_error("HNR count invariant failed");
            if (summary.has_hnr && (!std::isfinite(summary.hnr_db) || !std::isfinite(summary.hnr_std_db)))
                throw std::runtime_error("Non-finite valid HNR summary");
            std::cout << "{\"hnr_db\":"; number(summary.has_hnr ? summary.hnr_db : NAN);
            std::cout << ",\"hnr_std_db\":"; number(summary.has_hnr ? summary.hnr_std_db : NAN);
            std::cout << ",\"hnr_window_count\":" << summary.hnr_window_count;
            std::cout << ",\"window_seconds\":"; number(summary.window_seconds);
            std::cout << ",\"windows\":[";
            for (size_t i = 0; i < windows.size(); ++i) {
                if (i) std::cout << ',';
                const auto& window = windows[i];
                std::cout << "{\"start_seconds\":"; number(window.start_seconds);
                std::cout << ",\"end_seconds\":"; number(window.end_seconds);
                std::cout << ",\"hnr_db\":"; number(window.has_hnr ? window.hnr_db : NAN);
                std::cout << '}';
            }
            std::cout << "]}\n";
            return 0;
        }
        throw std::runtime_error("Expected full MODELS WAV PROFILE or hnr WAV INTERVALS");
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 2;
    }
}
