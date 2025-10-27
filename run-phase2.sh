#!/bin/bash

# Phase 2: 50M Rows - Pressure Test
echo "🚀 EventAnalytics Challenge - Phase 2"
echo "======================================"
echo "Target: 50 Million Events"
echo "Expected Time: ~5-7 minutes"
echo "Expected Size: ~10-12 GB"
echo ""
echo "⚠️  This will stress test your system!"
echo ""

cd "$(dirname "$0")/src/EventAnalytics.LoadGenerator"

if [ ! -d "bin" ]; then
    echo "Building project..."
    dotnet build -c Release
    echo ""
fi

echo "Starting load..."
echo ""

dotnet run -c Release -- --rows 50000000 --batch-size 50000 --users 15000

echo ""
echo "✅ Phase 2 Complete!"
echo ""
echo "Next: Run ./run-phase3.sh for the final 100M rows"
