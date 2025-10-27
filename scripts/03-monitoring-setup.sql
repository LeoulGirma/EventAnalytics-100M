-- ============================================================
-- MONITORING & PERFORMANCE TRACKING
-- ============================================================
-- These views help you answer:
-- - Which queries are slow?
-- - Which indexes are used?
-- - Is autovacuum keeping up?
-- - Where is disk space going?

-- ============================================================
-- VIEW 1: Slow Queries (from pg_stat_statements)
-- ============================================================
CREATE OR REPLACE VIEW slow_queries AS
SELECT 
    LEFT(query, 100) as query_preview,
    calls,
    ROUND(total_exec_time::numeric, 2) as total_time_ms,
    ROUND(mean_exec_time::numeric, 2) as avg_time_ms,
    ROUND(max_exec_time::numeric, 2) as max_time_ms,
    ROUND(stddev_exec_time::numeric, 2) as stddev_time_ms,
    rows as rows_returned,
    ROUND(100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0), 2) as cache_hit_ratio
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY mean_exec_time DESC
LIMIT 20;

COMMENT ON VIEW slow_queries IS 'Top 20 slowest queries by average execution time';

-- ============================================================
-- VIEW 2: Index Usage Statistics
-- ============================================================
CREATE OR REPLACE VIEW index_usage AS
SELECT 
    schemaname,
    relname as tablename,
    indexrelname as indexname,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
    CASE 
        WHEN idx_scan = 0 THEN 'UNUSED'
        WHEN idx_scan < 100 THEN 'RARELY_USED'
        ELSE 'ACTIVE'
    END as usage_status
FROM pg_stat_user_indexes
ORDER BY idx_scan ASC, pg_relation_size(indexrelid) DESC;

COMMENT ON VIEW index_usage IS 'Index usage stats - find unused or rarely-used indexes';

-- ============================================================
-- VIEW 3: Table Bloat Estimation
-- ============================================================
CREATE OR REPLACE VIEW table_bloat_stats AS
SELECT 
    schemaname || '.' || relname as table_name,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) as total_size,
    n_live_tup as live_rows,
    n_dead_tup as dead_rows,
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) as dead_row_percent,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
WHERE n_live_tup > 0
ORDER BY n_dead_tup DESC;

COMMENT ON VIEW table_bloat_stats IS 'Table bloat monitoring - watch dead_row_percent at scale';

-- ============================================================
-- VIEW 4: Cache Hit Ratio (Should be > 99% at steady state)
-- ============================================================
CREATE OR REPLACE VIEW cache_hit_ratio AS
SELECT 
    'index hit rate' as metric,
    ROUND(100.0 * sum(idx_blks_hit) / NULLIF(sum(idx_blks_hit + idx_blks_read), 0), 2) as ratio
FROM pg_statio_user_indexes
UNION ALL
SELECT 
    'table hit rate' as metric,
    ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit + heap_blks_read), 0), 2) as ratio
FROM pg_statio_user_tables;

COMMENT ON VIEW cache_hit_ratio IS 'Cache efficiency - should be > 99% after warm-up';

-- ============================================================
-- VIEW 5: Query Performance by Type
-- ============================================================
CREATE OR REPLACE VIEW query_stats_by_type AS
SELECT 
    CASE 
        WHEN query LIKE 'SELECT%' THEN 'SELECT'
        WHEN query LIKE 'INSERT%' THEN 'INSERT'
        WHEN query LIKE 'UPDATE%' THEN 'UPDATE'
        WHEN query LIKE 'DELETE%' THEN 'DELETE'
        ELSE 'OTHER'
    END as query_type,
    COUNT(*) as query_count,
    SUM(calls) as total_calls,
    ROUND(SUM(total_exec_time)::numeric, 2) as total_time_ms,
    ROUND(AVG(mean_exec_time)::numeric, 2) as avg_time_ms,
    SUM(rows) as total_rows
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat%'
GROUP BY query_type
ORDER BY total_time_ms DESC;

COMMENT ON VIEW query_stats_by_type IS 'Query performance grouped by operation type';

-- ============================================================
-- VIEW 6: Database Size Summary
-- ============================================================
CREATE OR REPLACE VIEW database_size_summary AS
SELECT 
    pg_database.datname as database_name,
    pg_size_pretty(pg_database_size(pg_database.datname)) as size
FROM pg_database
WHERE datname = current_database();

-- ============================================================
-- FUNCTION: Complete Performance Report
-- ============================================================
CREATE OR REPLACE FUNCTION performance_report()
RETURNS TABLE (
    section TEXT,
    metric TEXT,
    value TEXT
) AS $$
BEGIN
    -- Database size
    RETURN QUERY
    SELECT 
        'DATABASE SIZE'::TEXT,
        'Total size'::TEXT,
        pg_size_pretty(pg_database_size(current_database()))
    UNION ALL
    SELECT 
        'DATABASE SIZE'::TEXT,
        'Events table size'::TEXT,
        pg_size_pretty(pg_total_relation_size('events'))
    
    -- Row counts
    UNION ALL
    SELECT 
        'ROW COUNTS'::TEXT,
        'Total events'::TEXT,
        n_live_tup::TEXT
    FROM pg_stat_user_tables 
    WHERE relname = 'events'
    UNION ALL
    SELECT 
        'ROW COUNTS'::TEXT,
        'Total sessions'::TEXT,
        n_live_tup::TEXT
    FROM pg_stat_user_tables 
    WHERE relname = 'sessions'
    
    -- Cache performance
    UNION ALL
    SELECT
        'CACHE PERFORMANCE'::TEXT,
        chr.metric::TEXT,
        chr.ratio::TEXT || '%'
    FROM cache_hit_ratio chr
    
    -- Partition info
    UNION ALL
    SELECT 
        'PARTITIONS'::TEXT,
        'Total partitions'::TEXT,
        COUNT(*)::TEXT
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_inherits i ON i.inhrelid = c.oid
    JOIN pg_class p ON p.oid = i.inhparent
    WHERE p.relname = 'events'
    AND n.nspname = 'public';
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- FUNCTION: Benchmark Query (for testing)
-- ============================================================
CREATE OR REPLACE FUNCTION benchmark_query(
    query_text TEXT,
    iterations INT DEFAULT 10
)
RETURNS TABLE (
    iteration INT,
    execution_time_ms NUMERIC,
    rows_returned BIGINT
) AS $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    i INT;
    row_count BIGINT;
BEGIN
    FOR i IN 1..iterations LOOP
        start_time := clock_timestamp();
        
        -- Execute the query
        EXECUTE query_text;
        GET DIAGNOSTICS row_count = ROW_COUNT;
        
        end_time := clock_timestamp();
        
        iteration := i;
        execution_time_ms := EXTRACT(MILLISECONDS FROM (end_time - start_time));
        rows_returned := row_count;
        
        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Reset statistics (useful when testing)
-- ============================================================
CREATE OR REPLACE FUNCTION reset_query_stats()
RETURNS void AS $$
BEGIN
    -- Reset pg_stat_statements
    PERFORM pg_stat_statements_reset();
    
    -- Reset table/index stats
    PERFORM pg_stat_reset();
    
    RAISE NOTICE 'All statistics have been reset';
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Show initial status
-- ============================================================
SELECT * FROM performance_report();
