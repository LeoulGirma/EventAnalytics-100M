-- ============================================================
-- AUTO-CREATE PARTITIONS FOR EVENTS TABLE
-- ============================================================
-- This script creates partitions for past, current, and future months
-- 
-- Why monthly partitions?
-- - Most queries filter by date range (last 7 days, last 30 days)
-- - Each partition = 3-8 million rows (manageable size)
-- - Can drop old partitions without VACUUM overhead
-- - Partition pruning = query only touches relevant partitions

-- Function to create a partition for a given month
CREATE OR REPLACE FUNCTION create_partition_for_month(partition_date DATE)
RETURNS void AS $$
DECLARE
    partition_name TEXT;
    start_date DATE;
    end_date DATE;
BEGIN
    -- Generate partition name: events_2024_01, events_2024_02, etc.
    partition_name := 'events_' || TO_CHAR(partition_date, 'YYYY_MM');
    
    -- Calculate date range for this partition
    start_date := DATE_TRUNC('month', partition_date);
    end_date := start_date + INTERVAL '1 month';
    
    -- Check if partition already exists
    IF NOT EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = partition_name
        AND n.nspname = 'public'
    ) THEN
        -- Create the partition
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF events FOR VALUES FROM (%L) TO (%L)',
            partition_name,
            start_date,
            end_date
        );
        
        RAISE NOTICE 'Created partition: % (% to %)', 
            partition_name, start_date, end_date;
    ELSE
        RAISE NOTICE 'Partition % already exists', partition_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to auto-create partitions for a date range
CREATE OR REPLACE FUNCTION create_partitions_for_range(
    start_month DATE,
    end_month DATE
)
RETURNS void AS $$
DECLARE
    current_month DATE;
BEGIN
    current_month := DATE_TRUNC('month', start_month);
    
    WHILE current_month <= end_month LOOP
        PERFORM create_partition_for_month(current_month);
        current_month := current_month + INTERVAL '1 month';
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- CREATE PARTITIONS: 6 months back, current, 6 months forward
-- ============================================================
-- This ensures we have partitions ready for:
-- - Historical data loads (backfill)
-- - Current data ingestion
-- - Future data (so inserts don't fail)

SELECT create_partitions_for_range(
    (CURRENT_DATE - INTERVAL '6 months')::DATE,  -- 6 months ago
    (CURRENT_DATE + INTERVAL '6 months')::DATE   -- 6 months from now
);

-- ============================================================
-- PARTITION MAINTENANCE FUNCTION
-- ============================================================
-- Call this monthly (via cron or pg_cron extension) to:
-- 1. Create next month's partition
-- 2. Optionally drop very old partitions

CREATE OR REPLACE FUNCTION maintain_partitions()
RETURNS void AS $$
DECLARE
    partition_name TEXT;
    cutoff_date DATE;
BEGIN
    -- Create next 2 months if they don't exist
    PERFORM create_partition_for_month(CURRENT_DATE + INTERVAL '1 month');
    PERFORM create_partition_for_month(CURRENT_DATE + INTERVAL '2 months');
    
    -- Optional: Drop partitions older than 12 months
    -- (Uncomment when you want data retention policy)
    /*
    cutoff_date := CURRENT_DATE - INTERVAL '12 months';
    
    FOR partition_name IN
        SELECT c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_inherits i ON i.inhrelid = c.oid
        JOIN pg_class p ON p.oid = i.inhparent
        WHERE p.relname = 'events'
        AND n.nspname = 'public'
        AND c.relname LIKE 'events_%'
    LOOP
        -- Extract date from partition name and check if too old
        IF TO_DATE(SUBSTRING(partition_name FROM 'events_(\d{4}_\d{2})'), 'YYYY_MM') < cutoff_date THEN
            EXECUTE format('DROP TABLE %I', partition_name);
            RAISE NOTICE 'Dropped old partition: %', partition_name;
        END IF;
    END LOOP;
    */
    
    RAISE NOTICE 'Partition maintenance completed';
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- HELPER: List all partitions with their size
-- ============================================================
CREATE OR REPLACE FUNCTION list_partitions()
RETURNS TABLE (
    partition_name TEXT,
    row_count BIGINT,
    total_size TEXT,
    date_range TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.relname::TEXT,
        pg_stat_get_live_tuples(c.oid),
        pg_size_pretty(pg_total_relation_size(c.oid)),
        pg_get_expr(c.relpartbound, c.oid)::TEXT
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_inherits i ON i.inhrelid = c.oid
    JOIN pg_class p ON p.oid = i.inhparent
    WHERE p.relname = 'events'
    AND n.nspname = 'public'
    ORDER BY c.relname;
END;
$$ LANGUAGE plpgsql;

-- Show what we just created
SELECT list_partitions();
