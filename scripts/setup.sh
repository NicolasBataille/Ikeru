#!/bin/bash
# Ikeru Project Setup Script
# Run this once after cloning the repository.
# Usage: chmod +x scripts/setup.sh && ./scripts/setup.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=== Ikeru Project Setup ==="
echo ""

# Step 1: Install xcodegen if needed
if ! command -v xcodegen &> /dev/null; then
    echo "Installing XcodeGen..."
    brew install xcodegen
else
    echo "XcodeGen already installed."
fi

# Step 2: Install SwiftLint if needed
if ! command -v swiftlint &> /dev/null; then
    echo "Installing SwiftLint..."
    brew install swiftlint
else
    echo "SwiftLint already installed."
fi

# Step 3: Download fonts
echo ""
echo "Downloading Noto Serif JP fonts..."
FONT_DIR="$PROJECT_ROOT/Ikeru/Resources/Fonts"
mkdir -p "$FONT_DIR"

if [ ! -f "$FONT_DIR/NotoSerifJP-Bold.otf" ]; then
    curl -L -o "$FONT_DIR/NotoSerifJP-Bold.otf" \
        "https://github.com/googlefonts/noto-cjk/raw/main/Serif/OTF/Japanese/NotoSerifJP-Bold.otf"
    echo "  Downloaded NotoSerifJP-Bold.otf"
else
    echo "  NotoSerifJP-Bold.otf already exists."
fi

if [ ! -f "$FONT_DIR/NotoSerifJP-Medium.otf" ]; then
    curl -L -o "$FONT_DIR/NotoSerifJP-Medium.otf" \
        "https://github.com/googlefonts/noto-cjk/raw/main/Serif/OTF/Japanese/NotoSerifJP-Medium.otf"
    echo "  Downloaded NotoSerifJP-Medium.otf"
else
    echo "  NotoSerifJP-Medium.otf already exists."
fi

# Step 4: Create Secrets.xcconfig if needed
if [ ! -f "$PROJECT_ROOT/Secrets.xcconfig" ]; then
    echo ""
    echo "Creating Secrets.xcconfig from template..."
    cp "$PROJECT_ROOT/Secrets.xcconfig.example" "$PROJECT_ROOT/Secrets.xcconfig"
    echo "  Created Secrets.xcconfig — fill in your values."
fi

# Step 5: Generate Xcode project
echo ""
echo "Generating Xcode project with XcodeGen..."
xcodegen generate --spec project.yml
echo "  Xcode project generated."

# Step 6: Build IkeruCore package
echo ""
echo "Building IkeruCore package..."
cd "$PROJECT_ROOT/IkeruCore"
swift build
echo "  IkeruCore built successfully."

# Step 7: Run IkeruCore tests
echo ""
echo "Running IkeruCore tests..."
swift test
echo "  All IkeruCore tests passed."

echo ""
echo "=== Setup Complete ==="
echo "Open Ikeru.xcodeproj in Xcode and build."
