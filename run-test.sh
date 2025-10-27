#!/bin/bash

# Test Load - Quick verification
echo "🧪 EventAnalytics - Test Load"
echo "=============================="
echo "Target: 100,000 Events (quick test)"
echo "Expected Time: ~5 seconds"
echo ""

cd "$(dirname "$0")/src/EventAnalytics.LoadGenerator"

if [ ! -d "bin" ]; then
    echo "Building project..."
    dotnet build -c Release
    echo ""
fi

echo "Starting test load..."
echo ""

dotnet run -c Release -- --rows 100000 --batch-size 10000 --users 1000

echo ""
echo "✅ Test Complete!"
echo ""
echo "Verify data:"
echo "  docker exec -it analytics_db psql -U analytics_user -d analytics -c 'SELECT COUNT(*) FROM events;'"
echo ""
echo "Check distribution:"
echo "  docker exec -it analytics_db psql -U analytics_user -d analytics -c 'SELECT event_type, COUNT(*) FROM events GROUP BY event_type;'"
echo ""
echo "Ready for the real challenge? Run:"
echo "  ./run-phase1.sh  (20M rows)"
echo ""
