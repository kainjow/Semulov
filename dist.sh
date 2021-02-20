set -e

BUILD_DIR=$(pwd)/Build
RELEASE_DIR="${BUILD_DIR}/Release"
APP="Semulov"

rm -rf Dependencies "${BUILD_DIR}"
xcodebuild -scheme "Semulov Release" "SYMROOT=${BUILD_DIR}"
pushd "${RELEASE_DIR}"

EXE=${APP}.app/Contents/MacOS/${APP}
if [[ "$(lipo -info ${EXE})" != *"x86_64 arm64"* ]]; then
    echo "A universal build must be created. Use Xcode 12.2 or greater."
    exit 1
fi

zip -ry "${APP}.zip" "${APP}.app"
popd
