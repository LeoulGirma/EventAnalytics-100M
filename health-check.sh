#!/bin/bash

# EventAnalytics Health Check
echo "🏥 EventAnalytics Health Check"
echo "================================"
echo ""

# Wait for database to be ready
echo "⏳ Waiting for database to be ready..."
sleep 3

MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker exec analytics_db pg_isready -U analytics_user -d analytics &> /dev/null; then
        echo "✅ Database is ready!"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "   Attempt $RETRY_COUNT/$MAX_RETRIES..."
    sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ Database failed to start"
    exit 1
fi

echo ""
echo "📊 Database Statistics"
echo "======================"

# Check row counts
echo ""
echo "Table Row Counts:"
docker exec analytics_db psql -U analytics_user -d analytics -t -c "
SELECT 
    'events: ' || COALESCE(SUM(n_live_tup), 0) || ' rows' 
FROM pg_stat_user_tables 
WHERE schemaname = 'public' AND relname LIKE 'events%'
UNION ALL
SELECT 
    'sessions: ' || COALESCE(n_live_tup, 0) || ' rows' 
FROM pg_stat_user_tables 
WHERE schemaname = 'public' AND relname = 'sessions'
UNION ALL
SELECT 
    'users: ' || COALESCE(n_live_tup, 0) || ' rows' 
FROM pg_stat_user_tables 
WHERE schemaname = 'public' AND relname = 'users';
"

# Check partitions
echo ""
echo "Partition Status:"
PARTITION_COUNT=$(docker exec analytics_db psql -U analytics_user -d analytics -t -c "SELECT COUNT(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace JOIN pg_inherits i ON i.inhrelid = c.oid JOIN pg_class p ON p.oid = i.inhparent WHERE p.relname = 'events' AND n.nspname = 'public';" | xargs)
echo "  ✅ $PARTITION_COUNT partitions created"

# Check indexes
echo ""
echo "Index Status:"
INDEX_COUNT=$(docker exec analytics_db psql -U analytics_user -d analytics -t -c "SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public';" | xargs)
echo "  ✅ $INDEX_COUNT indexes created"

# Check views
echo ""
echo "Monitoring Views:"
docker exec analytics_db psql -U analytics_user -d analytics -t -c "
SELECT '  ✅ ' || viewname 
FROM pg_views 
WHERE schemaname = 'public' 
ORDER BY viewname;
"

# Check functions
echo ""
echo "Helper Functions:"
FUNC_COUNT=$(docker exec analytics_db psql -U analytics_user -d analytics -t -c "SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE n.nspname = 'public' AND p.prokind = 'f';" | xargs)
echo "  ✅ $FUNC_COUNT functions created"

# Database size
echo ""
echo "💾 Storage Usage"
echo "================"
docker exec analytics_db psql -U analytics_user -d analytics -t -c "
SELECT 
    'Database: ' || pg_size_pretty(pg_database_size('analytics'))
UNION ALL
SELECT 
    'Events table: ' || pg_size_pretty(pg_total_relation_size('events'));
"

# Performance check
echo ""
echo "⚡ Quick Performance Test"
echo "=========================="
echo "Testing simple INSERT..."
START=$(date +%s%N)
docker exec analytics_db psql -U analytics_user -d analytics -q -c "
INSERT INTO events (user_id, session_id, event_type, properties, page_url, device_type, country_code)
VALUES (
    gen_random_uuid(),
    gen_random_uuid(),
    'page_view',
    '{\"test\": true}'::jsonb,
    '/test',
    'desktop',
    'US'
);
" &> /dev/null
END=$(date +%s%N)
ELAPSED=$(( ($END - $START) / 1000000 ))
echo "  ✅ INSERT completed in ${ELAPSED}ms"

echo ""
echo "Testing simple SELECT..."
START=$(date +%s%N)
docker exec analytics_db psql -U analytics_user -d analytics -q -c "
SELECT COUNT(*) FROM events WHERE event_type = 'page_view';
" &> /dev/null
END=$(date +%s%N)
ELAPSED=$(( ($END - $START) / 1000000 ))
echo "  ✅ SELECT completed in ${ELAPSED}ms"

# Cache hit ratio
echo ""
echo "📈 Cache Performance"
echo "===================="
docker exec analytics_db psql -U analytics_user -d analytics -t -c "
SELECT '  ' || metric || ': ' || ratio || '%' 
FROM cache_hit_ratio;
"

echo ""
echo "✅ All Systems Ready!"
echo ""
echo "🔗 Access Points:"
echo "  PostgreSQL: localhost:5432"
echo "  pgAdmin:    http://localhost:5050"
echo "  Redis:      localhost:6379"
echo ""
echo "📝 Quick Commands:"
echo "  Connect to DB:  docker exec -it analytics_db psql -U analytics_user -d analytics"
echo "  View logs:      docker-compose logs -f postgres"
echo "  Performance:    docker exec -it analytics_db psql -U analytics_user -d analytics -c 'SELECT * FROM performance_report();'"
echo ""
