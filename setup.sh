#!/bin/bash

# EventAnalytics Master Setup Script
set -e  # Exit on error

echo "🚀 EventAnalytics - Complete Setup"
echo "===================================="
echo ""
echo "This will set up your complete analytics environment."
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

step_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

step_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

step_error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Step 1: Check prerequisites
echo "📋 Step 1: Checking Prerequisites"
echo "=================================="

if ! command -v docker &> /dev/null; then
    step_error "Docker not found. Please install Docker first."
fi
step_success "Docker found"

if ! command -v docker-compose &> /dev/null; then
    step_error "Docker Compose not found. Please install it first."
fi
step_success "Docker Compose found"

echo ""

# Step 2: Clean old containers if any
echo "🧹 Step 2: Cleaning Old Containers"
echo "==================================="

if docker ps -a | grep -q analytics_; then
    step_info "Found existing containers, cleaning up..."
    docker-compose down -v 2>/dev/null || true
    step_success "Old containers removed"
else
    step_info "No existing containers found"
fi

echo ""

# Step 3: Start containers
echo "🐳 Step 3: Starting Containers"
echo "==============================="

step_info "Starting PostgreSQL, Redis, and pgAdmin..."
docker-compose up -d

if [ $? -ne 0 ]; then
    step_error "Failed to start containers. Check docker-compose.yml"
fi

step_success "Containers started"

echo ""

# Step 4: Wait for PostgreSQL
echo "⏳ Step 4: Waiting for Database"
echo "==============================="

MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker exec analytics_db pg_isready -U analytics_user -d analytics &> /dev/null; then
        step_success "Database is ready!"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo -n "."
    sleep 2
done

echo ""

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    step_error "Database failed to start. Check logs with: docker-compose logs postgres"
fi

echo ""

# Step 5: Verify schema
echo "🔍 Step 5: Verifying Schema"
echo "============================"

# Check tables
TABLE_COUNT=$(docker exec analytics_db psql -U analytics_user -d analytics -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';" 2>/dev/null | xargs)

if [ "$TABLE_COUNT" -ge 3 ]; then
    step_success "Found $TABLE_COUNT tables"
else
    step_error "Schema not initialized properly. Expected at least 3 tables, found $TABLE_COUNT"
fi

# Check partitions
PARTITION_COUNT=$(docker exec analytics_db psql -U analytics_user -d analytics -t -c "SELECT COUNT(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace JOIN pg_inherits i ON i.inhrelid = c.oid JOIN pg_class p ON p.oid = i.inhparent WHERE p.relname = 'events' AND n.nspname = 'public';" 2>/dev/null | xargs)

if [ "$PARTITION_COUNT" -ge 10 ]; then
    step_success "Found $PARTITION_COUNT partitions"
else
    step_error "Partitions not created. Expected at least 10, found $PARTITION_COUNT"
fi

# Check views
VIEW_COUNT=$(docker exec analytics_db psql -U analytics_user -d analytics -t -c "SELECT COUNT(*) FROM pg_views WHERE schemaname = 'public';" 2>/dev/null | xargs)

if [ "$VIEW_COUNT" -ge 5 ]; then
    step_success "Found $VIEW_COUNT monitoring views"
else
    step_error "Monitoring views not created. Expected at least 5, found $VIEW_COUNT"
fi

echo ""

# Step 6: Load test data
echo "📊 Step 6: Loading Test Data"
echo "============================="

if [ -f "scripts/test-data.sql" ]; then
    step_info "Inserting 1000 test events..."
    docker exec -i analytics_db psql -U analytics_user -d analytics < scripts/test-data.sql > /tmp/test_data.log 2>&1
    
    if [ $? -eq 0 ]; then
        EVENT_COUNT=$(docker exec analytics_db psql -U analytics_user -d analytics -t -c "SELECT COUNT(*) FROM events;" 2>/dev/null | xargs)
        step_success "Loaded $EVENT_COUNT test events"
    else
        step_info "Test data load failed (optional)"
    fi
else
    step_info "test-data.sql not found, skipping"
fi

echo ""

# Step 7: Performance test
echo "⚡ Step 7: Quick Performance Test"
echo "=================================="

step_info "Testing INSERT performance..."
START=$(date +%s%N)
docker exec analytics_db psql -U analytics_user -d analytics -q -c "INSERT INTO events (user_id, session_id, event_type, properties, page_url, device_type, country_code) VALUES (gen_random_uuid(), gen_random_uuid(), 'page_view', '{\"test\": true}'::jsonb, '/test', 'desktop', 'US');" &> /dev/null
END=$(date +%s%N)
ELAPSED=$(( ($END - $START) / 1000000 ))
step_success "INSERT: ${ELAPSED}ms"

step_info "Testing SELECT performance..."
START=$(date +%s%N)
docker exec analytics_db psql -U analytics_user -d analytics -q -c "SELECT COUNT(*) FROM events WHERE event_type = 'page_view';" &> /dev/null
END=$(date +%s%N)
ELAPSED=$(( ($END - $START) / 1000000 ))
step_success "SELECT: ${ELAPSED}ms"

echo ""

# Final summary
echo "🎉 Setup Complete!"
echo "==================="
echo ""
echo "📊 Database Statistics:"
docker exec analytics_db psql -U analytics_user -d analytics -t -c "
SELECT '  Events: ' || COALESCE(SUM(n_live_tup), 0) FROM pg_stat_user_tables WHERE schemaname = 'public' AND relname LIKE 'events%'
UNION ALL
SELECT '  Partitions: ' || COUNT(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace JOIN pg_inherits i ON i.inhrelid = c.oid JOIN pg_class p ON p.oid = i.inhparent WHERE p.relname = 'events' AND n.nspname = 'public'
UNION ALL
SELECT '  Database Size: ' || pg_size_pretty(pg_database_size('analytics'));
"

echo ""
echo "🔗 Access Points:"
echo "  PostgreSQL:  localhost:5432"
echo "  Database:    analytics"
echo "  Username:    analytics_user"
echo "  Password:    dev_password_123"
echo ""
echo "  pgAdmin:     http://localhost:5050"
echo "  Login:       admin@analytics.local / admin123"
echo ""
echo "  Redis:       localhost:6379"
echo ""

echo "📝 Next Steps:"
echo "  1. Connect to database:"
echo "     docker exec -it analytics_db psql -U analytics_user -d analytics"
echo ""
echo "  2. View performance stats:"
echo "     docker exec -it analytics_db psql -U analytics_user -d analytics -c 'SELECT * FROM performance_report();'"
echo ""
echo "  3. Check partitions:"
echo "     docker exec -it analytics_db psql -U analytics_user -d analytics -c 'SELECT * FROM list_partitions();'"
echo ""
echo "  4. Ready to load data! Next: Build the C# data generator"
echo ""

step_success "All systems operational! 🚀"
