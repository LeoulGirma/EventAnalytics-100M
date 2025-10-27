-- ============================================================
-- MANUAL PARTITION FIX
-- ============================================================
-- Run this if the auto-initialization failed
-- Connect: docker exec -it analytics_db psql -U analytics_user -d analytics
-- Then: \i /path/to/this/file.sql

-- Create partitions for the date range
SELECT create_partitions_for_range(
    (CURRENT_DATE - INTERVAL '6 months')::DATE,
    (CURRENT_DATE + INTERVAL '6 months')::DATE
);

-- Verify partitions were created
SELECT 
    partition_name,
    row_count,
    total_size,
    date_range
FROM list_partitions();

-- Should see output like:
--  partition_name | row_count | total_size |         date_range          
-- ----------------+-----------+------------+-----------------------------
--  events_2024_04 |         0 | 0 bytes    | FOR VALUES FROM ('2024-04-01') TO ('2024-05-01')
--  events_2024_05 |         0 | 0 bytes    | FOR VALUES FROM ('2024-05-01') TO ('2024-06-01')
--  ... etc

\echo 'Partitions created successfully!'
