#!/bin/bash

# Phase 3: 100M Rows - The Reality Check
echo "🚀 EventAnalytics Challenge - Phase 3"
echo "========================================"
echo "Target: 100 Million Events"
echo "Expected Time: ~10-15 minutes"
echo "Expected Size: ~20-30 GB"
echo ""
echo "🔥 THE BIG ONE - This is where data gets REAL!"
echo ""
echo "⚠️  WARNING:"
echo "   - Ensure you have 60+ GB free disk space"
echo "   - This will take 10-15 minutes"
echo "   - System may be slow during load"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 1
fi

cd "$(dirname "$0")/src/EventAnalytics.LoadGenerator"

if [ ! -d "bin" ]; then
    echo "Building project..."
    dotnet build -c Release
    echo ""
fi

echo ""
echo "🔥 Starting 100M row load..."
echo "💡 Tip: Open another terminal and run:"
echo "   watch -n 5 'docker exec analytics_db psql -U analytics_user -d analytics -t -c \"SELECT COUNT(*) FROM events;\"'"
echo ""
sleep 3

dotnet run -c Release -- --rows 100000000 --batch-size 50000 --users 20000

echo ""
echo "🎉 🎉 🎉 PHASE 3 COMPLETE! 🎉 🎉 🎉"
echo ""
echo "You just loaded 100 MILLION rows!"
echo "Now you understand what production scale feels like."
echo ""
echo "📊 Next Steps:"
echo "   1. Run benchmark queries"
echo "   2. Check query performance: docker exec -it analytics_db psql -U analytics_user -d analytics -c 'SELECT * FROM slow_queries;'"
echo "   3. Monitor bloat: docker exec -it analytics_db psql -U analytics_user -d analytics -c 'SELECT * FROM table_bloat_stats;'"
echo "   4. Write your blog post!"
echo ""
