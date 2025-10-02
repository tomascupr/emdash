#!/bin/bash
set -e  # Exit on any error

echo "🚀 Setting up emdash workspace..."

# Check for npm (fail-fast if missing)
if ! command -v npm &> /dev/null; then
    echo "❌ Error: npm is not installed or not in PATH"
    echo "Please install Node.js and npm before running this setup script"
    exit 1
fi

echo "✓ npm found: $(npm --version)"

# Install dependencies
echo "📦 Installing npm dependencies..."
npm install

echo "🔧 Rebuilding native modules for Electron..."
# This runs the postinstall script which rebuilds sqlite3, node-pty, keytar
npm run postinstall

echo "🏗️  Building main process..."
npm run build:main

echo ""
echo "✅ Workspace setup complete!"
echo "Click the 'Run' button to start the development server"
