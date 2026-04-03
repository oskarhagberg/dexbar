#!/usr/bin/env bash
# WebChart/build.sh
#
# Builds bundle-native.html from src/App.tsx and copies it to the
# parent directory (the Xcode project root) where it is referenced
# by GlucoseWebViewController and included in the app bundle.
#
# Usage:
#   cd WebChart
#   bash build.sh
#
# Requirements: Node 18+, pnpm (npm install -g pnpm)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$SCRIPT_DIR/../bundle-native.html"

cd "$SCRIPT_DIR"

# Install dependencies if node_modules is absent
if [ ! -d "node_modules" ]; then
  echo "📦 Installing dependencies..."
  pnpm install --frozen-lockfile
fi

# Install bundling deps if not present
if ! pnpm list parcel --depth=0 &>/dev/null 2>&1; then
  echo "📦 Installing build tools..."
  pnpm add -D parcel @parcel/config-default parcel-resolver-tspaths html-inline
fi

# Type-check first
echo "🔍 Type checking..."
pnpm exec tsc --noEmit

# Clean previous build
rm -rf dist

# Build with Parcel
echo "🔨 Building..."
pnpm exec parcel build index.html --dist-dir dist --no-source-maps

# Inline all assets into a single HTML file using Python
# (avoids html-inline compatibility issues with newer Node)
echo "📄 Inlining assets..."
python3 - << 'PYEOF'
import glob, re, os, sys

with open('dist/index.html', 'r') as f:
    html = f.read()

js_files = glob.glob('dist/*.js')
css_files = glob.glob('dist/*.css')

if not js_files or not css_files:
    print("ERROR: dist output missing JS or CSS files", file=sys.stderr)
    sys.exit(1)

js = open(js_files[0]).read()
css = open(css_files[0]).read()

html = re.sub(r'<link rel=stylesheet href=[^\s>]+>', lambda m: f'<style>{css}</style>', html)
html = re.sub(r'<script type=module src=[^\s>]+></script>', lambda m: f'<script>{js}</script>', html)
html = html.replace('data-parcel-ignore ', '').replace('&amp;', '&')
html = re.sub(r'<link[^>]*fonts\.googleapis\.com[^>]*>', '', html)
html = re.sub(r'<link[^>]*fonts\.gstatic\.com[^>]*>', '', html)

# Verify no mock data crept in
assert 'generateGlucoseData' not in html, "Mock data function found in bundle — aborting"

with open('bundle-native.html', 'w') as f:
    f.write(html)

size_kb = os.path.getsize('bundle-native.html') // 1024
print(f"✅ bundle-native.html — {size_kb}KB")
PYEOF

# Copy to Xcode project root
cp bundle-native.html "$OUTPUT"
echo "📋 Copied to $(realpath "$OUTPUT")"
echo ""
echo "✅ Done. Replace bundle-native.html in the Xcode target if prompted."
