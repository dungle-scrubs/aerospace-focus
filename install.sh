#!/bin/bash
set -e

trap 'echo ""; echo "❌ Installation failed at line $LINENO. Check errors above."; exit 1' ERR

echo "Building aerospace-focus (this may take a few minutes on first run)..."
swift build -c release

# Verify binary works
.build/release/aerospace-focus --help > /dev/null 2>&1

# Install binary
mkdir -p ~/.local/bin
cp .build/release/aerospace-focus ~/.local/bin/
chmod +x ~/.local/bin/aerospace-focus
echo "✅ Installed binary to ~/.local/bin/aerospace-focus"

# Check PATH
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo ""
    echo "⚠️  ~/.local/bin is not in your PATH"
    echo "   Add to your shell profile (~/.zshrc or ~/.bashrc):"
    echo "   export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
fi

# Install default config
mkdir -p ~/.config/aerospace-focus
if [ ! -f ~/.config/aerospace-focus/config.toml ]; then
    cp config.example.toml ~/.config/aerospace-focus/config.toml
    echo "✅ Installed default config to ~/.config/aerospace-focus/config.toml"
else
    echo "ℹ️  Config already exists at ~/.config/aerospace-focus/config.toml"
    if ! diff -q config.example.toml ~/.config/aerospace-focus/config.toml > /dev/null 2>&1; then
        echo "   New options may be available. Compare with: diff ~/.config/aerospace-focus/config.toml config.example.toml"
    fi
fi

echo ""
echo "✅ Installation complete!"
echo ""
echo "Add to your ~/.config/aerospace/aerospace.toml:"
echo ""
echo "  after-startup-command = ["
echo "      'exec-and-forget aerospace-focus daemon'"
echo "  ]"
echo ""
echo "  on-focus-changed = ['exec-and-forget aerospace-focus update']"
echo ""
echo "Then reload: aerospace reload-config"
