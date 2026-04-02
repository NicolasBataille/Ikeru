#!/bin/bash
# Download Noto Serif JP fonts from Google Fonts
# Run this script from the project root: ./scripts/download-fonts.sh

FONT_DIR="Ikeru/Resources/Fonts"
mkdir -p "$FONT_DIR"

echo "Downloading Noto Serif JP Bold..."
curl -L -o "$FONT_DIR/NotoSerifJP-Bold.otf" \
  "https://github.com/googlefonts/noto-cjk/raw/main/Serif/OTF/Japanese/NotoSerifJP-Bold.otf"

echo "Downloading Noto Serif JP Medium..."
curl -L -o "$FONT_DIR/NotoSerifJP-Medium.otf" \
  "https://github.com/googlefonts/noto-cjk/raw/main/Serif/OTF/Japanese/NotoSerifJP-Medium.otf"

echo "Done! Fonts saved to $FONT_DIR"
ls -la "$FONT_DIR"
