#!/bin/bash

# EventAnalytics Setup Verification Script
echo "🔍 EventAnalytics Setup Verification"
echo "===================================="
echo ""

# Check Docker
echo "1️⃣  Checking Docker..."
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please install Docker first."
    exit 1
fi
echo "✅ Docker found: $(docker --version)"
echo ""

# Check Docker Compose
echo "2️⃣  Checking Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose not found."
    exit 1
fi
echo "✅ Docker Compose found: $(docker-compose --version)"
echo ""

# Check if containers are running
echo "3️⃣  Checking containers..."
if docker ps | grep -q analytics_db; then
    echo "✅ PostgreSQL container is running"
else
    echo "⚠️  PostgreSQL container not running"
    echo "   Run: docker-compose up -d"
fi

if docker ps | grep -q analytics_cache; then
    echo "✅ Redis container is running"
else
    echo "⚠️  Redis container not running"
fi
echo ""

# Test database connection
echo "4️⃣  Testing PostgreSQL connection..."
if docker exec analytics_db psql -U analytics_user -d analytics -c "SELECT 1" &> /dev/null; then
    echo "✅ PostgreSQL connection successful"
    
    # Check tables
    echo ""
    echo "5️⃣  Checking database schema..."
    TABLE_COUNT=$(docker exec analytics_db psql -U analytics_user -d analytics -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';")
    echo "   Found $TABLE_COUNT tables"
    
    # Check partitions
    PARTITION_COUNT=$(docker exec analytics_db psql -U analytics_user -d analytics -t -c "SELECT COUNT(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace JOIN pg_inherits i ON i.inhrelid = c.oid JOIN pg_class p ON p.oid = i.inhparent WHERE p.relname = 'events' AND n.nspname = 'public';")
    echo "   Found $PARTITION_COUNT event partitions"
    
    if [ "$PARTITION_COUNT" -gt 0 ]; then
        echo "✅ Partitions created successfully"
    else
        echo "⚠️  No partitions found. Schema might not have initialized."
    fi
else
    echo "❌ Cannot connect to PostgreSQL"
    echo "   Try: docker-compose logs postgres"
fi
echo ""

# Test Redis
echo "6️⃣  Testing Redis connection..."
if docker exec analytics_cache redis-cli PING &> /dev/null; then
    echo "✅ Redis connection successful"
else
    echo "❌ Cannot connect to Redis"
fi
echo ""

# Show useful commands
echo "📋 Useful Commands:"
echo "===================="
echo "Connect to database:"
echo "  docker exec -it analytics_db psql -U analytics_user -d analytics"
echo ""
echo "View logs:"
echo "  docker-compose logs -f postgres"
echo ""
echo "Stop containers:"
echo "  docker-compose down"
echo ""
echo "Restart containers:"
echo "  docker-compose restart"
echo ""
echo "Check performance:"
echo "  docker exec -it analytics_db psql -U analytics_user -d analytics -c 'SELECT * FROM performance_report();'"
echo ""
echo "🎉 Setup verification complete!"
