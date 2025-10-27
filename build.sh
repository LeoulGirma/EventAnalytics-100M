#!/bin/bash

# Build the Load Generator
echo "🔨 Building EventAnalytics Load Generator"
echo "=========================================="
echo ""

cd "$(dirname "$0")/src/EventAnalytics.LoadGenerator"

# Check .NET SDK
if ! command -v dotnet &> /dev/null; then
    echo "❌ .NET SDK not found"
    echo "   Download from: https://dotnet.microsoft.com/download"
    exit 1
fi

echo "✅ .NET SDK found: $(dotnet --version)"
echo ""

# Restore packages
echo "📦 Restoring NuGet packages..."
dotnet restore

if [ $? -ne 0 ]; then
    echo "❌ Package restore failed"
    exit 1
fi

echo ""
echo "🔨 Building Release configuration..."
dotnet build -c Release

if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

echo ""
echo "✅ Build successful!"
echo ""
echo "Run the generator:"
echo "  ./run-test.sh          # 100K events (quick test)"
echo "  ./run-phase1.sh        # 20M events"
echo "  ./run-phase2.sh        # 50M events"
echo "  ./run-phase3.sh        # 100M events (the big one!)"
echo ""
echo "Or directly:"
echo "  cd src/EventAnalytics.LoadGenerator"
echo "  dotnet run -c Release -- --rows 1000000"
echo ""
