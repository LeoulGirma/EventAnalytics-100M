#!/bin/bash

# Phase 1: 20M Rows - Baseline
echo "🚀 EventAnalytics Challenge - Phase 1"
echo "======================================"
echo "Target: 20 Million Events"
echo "Expected Time: ~2-3 minutes"
echo "Expected Size: ~4-5 GB"
echo ""

cd "$(dirname "$0")/src/EventAnalytics.LoadGenerator"

if [ ! -d "bin" ]; then
    echo "Building project..."
    dotnet build -c Release
    echo ""
fi

echo "Starting load..."
echo ""

dotnet run -c Release -- --rows 20000000 --batch-size 50000 --users 10000 --force

echo ""
echo "✅ Phase 1 Complete!"
echo ""
echo "Next: Run ./run-phase2.sh for 50M rows"
