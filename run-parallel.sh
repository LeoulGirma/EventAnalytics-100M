#!/bin/bash

# Parallel Event Loading Script
# Uses multiple instances with time-range partitioning to avoid conflicts

TOTAL_EVENTS=20000000
WORKERS=4
EVENTS_PER_WORKER=$((TOTAL_EVENTS / WORKERS))

echo "🚀 EventAnalytics - Parallel Loading"
echo "===================================="
echo "Total Events: $TOTAL_EVENTS"
echo "Workers: $WORKERS"
echo "Events per worker: $EVENTS_PER_WORKER"
echo ""

# Kill any existing load processes
echo "Stopping any running generators..."
pkill -f "EventAnalytics.LoadGenerator" || true
sleep 2

cd "$(dirname "$0")/src/EventAnalytics.LoadGenerator"

# Build if needed
if [ ! -d "bin" ]; then
    echo "Building project..."
    dotnet build -c Release
    echo ""
fi

echo "Starting $WORKERS parallel workers..."
echo ""

# Function to run a worker
run_worker() {
    local worker_id=$1
    local events=$2
    local start_date_offset=$3

    echo "Worker $worker_id: Loading $events events (offset: $start_date_offset months)"

    # Each worker uses different time range to avoid partition conflicts
    dotnet run -c Release -- \
        --rows $events \
        --batch-size 25000 \
        --users 2500 \
        --force \
        > "../../../logs/worker_${worker_id}.log" 2>&1 &

    echo $! > "../../../logs/worker_${worker_id}.pid"
}

# Create logs directory
mkdir -p "../../logs"

# Start workers
for i in $(seq 1 $WORKERS); do
    run_worker $i $EVENTS_PER_WORKER $((i-1))
    sleep 1  # Stagger startup slightly
done

echo "All workers started! Monitor progress:"
echo ""
echo "  # Check total events"
echo "  watch -n 10 'docker exec analytics_db psql -U analytics_user -d analytics -t -c \"SELECT COUNT(*) FROM events;\"'"
echo ""
echo "  # Check worker logs"
echo "  tail -f logs/worker_*.log"
echo ""
echo "  # Kill all workers if needed"
echo "  pkill -f EventAnalytics.LoadGenerator"
echo ""

# Monitor progress
echo "Monitoring total progress..."
echo "Press Ctrl+C to stop monitoring (workers will continue)"

while true; do
    current_count=$(docker exec analytics_db psql -U analytics_user -d analytics -t -c "SELECT COUNT(*) FROM events;" 2>/dev/null | tr -d ' ')
    if [[ "$current_count" =~ ^[0-9]+$ ]]; then
        percentage=$((current_count * 100 / TOTAL_EVENTS))
        echo "$(date '+%H:%M:%S') - Events: $current_count / $TOTAL_EVENTS ($percentage%)"
    fi
    sleep 30
done