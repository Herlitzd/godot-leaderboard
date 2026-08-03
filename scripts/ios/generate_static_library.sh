#!/bin/bash
set -e

cd ios

PLUGIN=$1
TARGET=$2
VERSION=$3

# lib<plugin>.<arch>-<simulator|ios>.<target>.a
if [[ "$VERSION" == "3.x" ]]; then
    DEVICE_SUFFIX="iphone"
else
    DEVICE_SUFFIX="ios"
fi

# Device slices
scons target=$TARGET arch=arm64 plugin=$PLUGIN version=$VERSION
if [[ "$VERSION" == "3.x" ]]; then
    # armv7 only needed for Godot 3.x / 32-bit devices; iOS 26 SDK dropped 32-bit support
    scons target=$TARGET arch=armv7 plugin=$PLUGIN version=$VERSION
fi

# Simulator slices (arm64 for Apple Silicon Macs, x86_64 for Intel)
scons target=$TARGET arch=arm64 simulator=yes plugin=$PLUGIN version=$VERSION
scons target=$TARGET arch=x86_64 simulator=yes plugin=$PLUGIN version=$VERSION

# Fat device library
if [[ "$VERSION" == "3.x" ]]; then
    lipo -create \
        "./bin/lib${PLUGIN}.arm64-${DEVICE_SUFFIX}.${TARGET}.a" \
        "./bin/lib${PLUGIN}.armv7-${DEVICE_SUFFIX}.${TARGET}.a" \
        -output "./bin/${PLUGIN}.device.${TARGET}.a"
else
    # Godot 4.x — arm64 only, no armv7
    cp "./bin/lib${PLUGIN}.arm64-${DEVICE_SUFFIX}.${TARGET}.a" \
       "./bin/${PLUGIN}.device.${TARGET}.a"
fi

# Fat simulator library (arm64-simulator + x86_64-simulator)
lipo -create \
    "./bin/lib${PLUGIN}.arm64-simulator.${TARGET}.a" \
    "./bin/lib${PLUGIN}.x86_64-simulator.${TARGET}.a" \
    -output "./bin/${PLUGIN}.simulator.${TARGET}.a"

# Stage slices with a consistent basename so xcodebuild embeds "leaderboard.a"
# as the BinaryPath inside each xcframework slice (not "leaderboard.device.release.a")
rm -rf "./bin/xcf_stage_device_${TARGET}" "./bin/xcf_stage_sim_${TARGET}"
mkdir -p "./bin/xcf_stage_device_${TARGET}" "./bin/xcf_stage_sim_${TARGET}"
cp "./bin/${PLUGIN}.device.${TARGET}.a"    "./bin/xcf_stage_device_${TARGET}/${PLUGIN}.a"
cp "./bin/${PLUGIN}.simulator.${TARGET}.a" "./bin/xcf_stage_sim_${TARGET}/${PLUGIN}.a"

# XCFramework — bundles device and simulator with correct platform tags
# so Xcode can link the right slice without conflict
rm -rf "./bin/${PLUGIN}.${TARGET}.xcframework"
xcodebuild -create-xcframework \
    -library "./bin/xcf_stage_device_${TARGET}/${PLUGIN}.a" \
    -library "./bin/xcf_stage_sim_${TARGET}/${PLUGIN}.a" \
    -output "./bin/${PLUGIN}.${TARGET}.xcframework"

rm -rf "./bin/xcf_stage_device_${TARGET}" "./bin/xcf_stage_sim_${TARGET}"

cd ..
