#!/bin/bash
set -e

echo "Building aerospace-focus..."
swift build -c release

# Install binary
mkdir -p ~/.local/bin
cp .build/release/aerospace-focus ~/.local/bin/
echo "Installed binary to ~/.local/bin/aerospace-focus"

# Install default config
mkdir -p ~/.config/aerospace-focus
if [ ! -f ~/.config/aerospace-focus/config.toml ]; then
    cp config.example.toml ~/.config/aerospace-focus/config.toml
    echo "Installed default config to ~/.config/aerospace-focus/config.toml"
else
    echo "Config already exists at ~/.config/aerospace-focus/config.toml"
fi

echo ""
echo "Installation complete!"
echo ""
echo "Add to your aerospace.toml:"
echo ""
echo "after-startup-command = ["
echo "    'exec-and-forget aerospace-focus daemon'"
echo "]"
echo ""
echo "on-focus-changed = ['exec-and-forget aerospace-focus update']"
