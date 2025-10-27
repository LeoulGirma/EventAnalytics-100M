#!/bin/bash

# SQL File Validator
echo "🔍 Validating SQL Scripts"
echo "========================="
echo ""

ERRORS=0

# Function to test SQL file
test_sql_file() {
    local file=$1
    local name=$(basename $file)
    
    echo -n "Testing $name... "
    
    # Check if postgres is running
    if ! docker ps | grep -q analytics_db; then
        echo "⚠️  Skipped (postgres not running)"
        return
    fi
    
    # Try to run the SQL
    if docker exec -i analytics_db psql -U analytics_user -d analytics -v ON_ERROR_STOP=1 < "$file" &> /tmp/sql_test_$$.log; then
        echo "✅ Valid"
    else
        echo "❌ Error"
        echo "   See errors below:"
        tail -5 /tmp/sql_test_$$.log | sed 's/^/   /'
        ERRORS=$((ERRORS + 1))
    fi
    
    rm -f /tmp/sql_test_$$.log
}

# Check if postgres is running
if ! docker ps | grep -q analytics_db; then
    echo "⚠️  PostgreSQL not running. Starting it..."
    docker-compose up -d postgres
    sleep 5
fi

# Test each SQL file
for file in scripts/*.sql; do
    if [ -f "$file" ] && [[ ! $file =~ (test-data|fix-partitions) ]]; then
        test_sql_file "$file"
    fi
done

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "✅ All SQL files are valid!"
else
    echo "❌ Found $ERRORS file(s) with errors"
    exit 1
fi
