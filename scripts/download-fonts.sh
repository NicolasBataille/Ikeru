#!/bin/bash
# Download Noto Serif JP fonts from Google Fonts
# Run this script from the project root: ./scripts/download-fonts.sh

FONT_DIR="Ikeru/Resources/Fonts"
mkdir -p "$FONT_DIR"

echo "Downloading Noto Serif JP Bold..."
curl -L -o "$FONT_DIR/NotoSerifJP-Bold.ttf" \
  "https://fonts.gstatic.com/s/notoserifjp/v33/xn71YHs72GKoTvER4Gn3b5eMRtWGkp6o7MjQ2bzWPebA.ttf"

echo "Downloading Noto Serif JP Medium..."
curl -L -o "$FONT_DIR/NotoSerifJP-Medium.ttf" \
  "https://fonts.gstatic.com/s/notoserifjp/v33/xn71YHs72GKoTvER4Gn3b5eMRtWGkp6o7MjQ2bwDOubA.ttf"

echo "Done! Fonts saved to $FONT_DIR"
ls -la "$FONT_DIR"
