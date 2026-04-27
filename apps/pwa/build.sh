#!/bin/bash

# Exit on error
set -e

# --- Configuration ---
FLUTTER_VERSION="3.41.6-stable"
FLUTTER_SDK_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}.tar.xz"

# --- Environment Setup ---
# We store the SDK in a subfolder of the current directory
INSTALL_DIR="$(pwd)/.flutter"
export PATH="$INSTALL_DIR/flutter/bin:$PATH"

# --- Check for Flutter ---
if ! command -v flutter &> /dev/null; then
    echo "--- Flutter SDK not found. Downloading v${FLUTTER_VERSION}... ---"
    
    mkdir -p "$INSTALL_DIR"
    curl -o flutter.tar.xz "$FLUTTER_SDK_URL"
    tar -xf flutter.tar.xz -C "$INSTALL_DIR"
    rm flutter.tar.xz
    
    echo "--- Flutter SDK installed! ---"
fi

# --- Git Trust Fix ---
# Vercel's environment often has permission mismatches. We must tell Git to trust the Flutter directory.
echo "--- Configuring Git trust for Flutter SDK... ---"
git config --global --add safe.directory "$INSTALL_DIR/flutter"

# --- Build Process ---
echo "--- Initializing Flutter... ---"
flutter config --no-analytics
flutter doctor -v

echo "--- Fetching dependencies... ---"
flutter pub get

echo "--- Building Web (Release)... ---"
flutter build web --release --pwa-strategy=offline-first \
  --dart-define=SUPABASE_URL="${NEXT_PUBLIC_SUPABASE_URL:-${SUPABASE_URL:-}}" \
  --dart-define=SUPABASE_ANON_KEY="${NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:-${SUPABASE_ANON_KEY:-}}" \
  --dart-define=SENTRY_DSN="${SENTRY_DSN:-}" \
  --dart-define=FIREBASE_VAPID_KEY="${FIREBASE_VAPID_KEY:-}"

echo "--- Build complete! Output located at: build/web ---"
