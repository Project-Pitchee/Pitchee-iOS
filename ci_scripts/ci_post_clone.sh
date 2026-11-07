#!/bin/sh
# Dependency setup belongs before package resolution/build, once per Cloud action.
set -eu
export GIT_TRACE=0
cd "${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud repository path is missing}"
test -f Pitchee.xcodeproj/xcshareddata/xcschemes/Pitchee.xcscheme || {
    echo 'error: Shared Pitchee scheme is missing.' >&2
    exit 1
}
test -f Scripts/bootstrap-native-dependencies.sh || {
    echo 'error: Native dependency bootstrap is missing.' >&2
    exit 1
}
sh Scripts/bootstrap-native-dependencies.sh
git submodule status --recursive
python3 Scripts/build-voice-training-library.py --check
