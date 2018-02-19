set -e

BUILD_DIR=$(pwd)/Build
RELEASE_DIR="${BUILD_DIR}/Release"
APP="Semulov"

rm -rf Dependencies "${BUILD_DIR}"
xcodebuild -scheme "Semulov Release" "SYMROOT=${BUILD_DIR}"
pushd "${RELEASE_DIR}"
zip -ry "${APP}.zip" "${APP}.app"
popd
