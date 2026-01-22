#!/bin/bash

# Build script for MP3 Editor macOS app bundle
set -e

# Change to the directory where this script is located
cd "$(dirname "$0")"

# Load shell profile to get proper PATH (needed when launched from Finder)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if [[ -f "$HOME/.zprofile" ]]; then
    source "$HOME/.zprofile" 2>/dev/null || true
fi

EXECUTABLE_NAME="MP3Editor"
BUILD_DIR=".build/release"
APP_BUNDLE="MP3 Editor.app"
VENV_DIR="${APP_BUNDLE}/Contents/Resources/venv"

echo "Building MP3 Editor in release mode..."
swift build -c release

echo "Creating app bundle structure..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

echo "Copying executable..."
cp "${BUILD_DIR}/${EXECUTABLE_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

echo "Copying Info.plist..."
cp Info.plist "${APP_BUNDLE}/Contents/"

echo "Copying Python script..."
cp mp3processor.py "${APP_BUNDLE}/Contents/Resources/"

echo "Creating Python virtual environment..."
if command -v uv &> /dev/null; then
    echo "Using uv: $(which uv)"
    uv venv "${VENV_DIR}"
    uv pip install --python "${VENV_DIR}/bin/python" -r requirements.txt
else
    echo "Using python3: $(which python3)"
    python3 -m venv "${VENV_DIR}"
    "${VENV_DIR}/bin/pip" install -r requirements.txt
fi
echo "Venv Python: ${VENV_DIR}/bin/python"

echo "Pre-downloading ffmpeg binaries..."
"${VENV_DIR}/bin/python" -c "import static_ffmpeg; static_ffmpeg.add_paths()"

echo "Creating PkgInfo..."
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

echo ""
echo "Build complete! App bundle created at: ${APP_BUNDLE}"
echo ""
echo "You can now:"
echo "  1. Double-click ${APP_BUNDLE} to run"
echo "  2. Move it to /Applications"
echo "  3. Run: open ${APP_BUNDLE}"
