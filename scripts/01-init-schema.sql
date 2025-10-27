-- ============================================================
-- EventAnalytics Schema - Designed for 100M+ Rows
-- ============================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- ============================================================
-- MAIN EVENTS TABLE (Partitioned by month)
-- ============================================================
-- Why partition by month?
-- 1. Query performance: Most analytics queries filter by time range
-- 2. Maintenance: Can VACUUM/ANALYZE individual partitions
-- 3. Data lifecycle: Drop old partitions = instant delete (no bloat!)
-- 4. Backup: Can backup recent partitions more frequently

CREATE TABLE events (
    id BIGSERIAL,
    event_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- User tracking
    user_id UUID NOT NULL,
    session_id UUID NOT NULL,
    
    -- Event classification
    event_type VARCHAR(50) NOT NULL,  -- 'page_view', 'click', 'form_submit', etc.
    
    -- Event payload (flexible schema using JSONB)
    -- Example: {"button_id": "signup", "plan": "pro", "value": 49.99}
    properties JSONB NOT NULL DEFAULT '{}',
    
    -- Denormalized columns for common queries (avoid JSONB access)
    page_url TEXT,
    referrer TEXT,
    
    -- Device/browser info
    device_type VARCHAR(20),  -- 'desktop', 'mobile', 'tablet'
    browser VARCHAR(50),
    os VARCHAR(50),
    
    -- Geographic data
    country_code CHAR(2),
    city VARCHAR(100),
    
    -- Metadata
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Partition key MUST be in PRIMARY KEY for partitioned tables
    PRIMARY KEY (id, event_time)
) PARTITION BY RANGE (event_time);

-- ============================================================
-- INDEXES ON PARENT TABLE (applied to all partitions)
-- ============================================================

-- Index 1: User journey queries
-- "Show me all events for user X in the last 7 days"
CREATE INDEX idx_events_user_time ON events (user_id, event_time DESC);

-- Index 2: Session analysis
-- "Get all events in this session"
CREATE INDEX idx_events_session ON events (session_id);

-- Index 3: Event type + time (for funnel analysis)
-- "How many 'purchase' events happened this week?"
CREATE INDEX idx_events_type_time ON events (event_type, event_time DESC);

-- Index 4: Country-based analytics
-- "DAUs by country"
CREATE INDEX idx_events_country_time ON events (country_code, event_time DESC);

-- Index 5: JSONB property queries (GIN index)
-- "Find all events where properties->>'plan' = 'pro'"
-- GIN indexes are large but essential for JSONB
CREATE INDEX idx_events_properties ON events USING GIN (properties);

-- Index 6: BRIN index for time-series scans
-- BRIN = Block Range Index (tiny size, perfect for sorted time data)
-- Only ~1% the size of a B-tree index on event_time!
CREATE INDEX idx_events_time_brin ON events USING BRIN (event_time);

-- ============================================================
-- SESSIONS TABLE (Not partitioned - relatively small)
-- ============================================================
CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    
    -- Time tracking
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,
    duration_seconds INT,
    
    -- Aggregated metrics
    page_views INT DEFAULT 0,
    clicks INT DEFAULT 0,
    form_submits INT DEFAULT 0,
    events_count INT DEFAULT 0,
    
    -- Journey analysis
    landing_page TEXT,
    exit_page TEXT,
    
    -- Device context
    device_type VARCHAR(20),
    browser VARCHAR(50),
    country_code CHAR(2),
    
    -- UTM tracking
    utm_source VARCHAR(100),
    utm_medium VARCHAR(100),
    utm_campaign VARCHAR(100),
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sessions_user_started ON sessions (user_id, started_at DESC);
CREATE INDEX idx_sessions_started ON sessions (started_at);
CREATE INDEX idx_sessions_country ON sessions (country_code, started_at DESC);
CREATE INDEX idx_sessions_utm ON sessions (utm_source, utm_campaign, started_at DESC);

-- ============================================================
-- USERS TABLE (Dimension table)
-- ============================================================
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- User attributes
    email VARCHAR(255),
    first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen TIMESTAMPTZ,
    
    -- Aggregated stats (updated via triggers or batch jobs)
    total_sessions INT DEFAULT 0,
    total_events INT DEFAULT 0,
    
    -- Segmentation
    country_code CHAR(2),
    signup_date DATE,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_last_seen ON users (last_seen DESC);
CREATE INDEX idx_users_country ON users (country_code);

-- ============================================================
-- MATERIALIZED VIEWS FOR DASHBOARD (Pre-aggregated data)
-- ============================================================

-- Daily aggregates (refreshed hourly/daily)
CREATE MATERIALIZED VIEW daily_event_stats AS
SELECT 
    DATE(event_time) as date,
    event_type,
    country_code,
    COUNT(*) as event_count,
    COUNT(DISTINCT user_id) as unique_users,
    COUNT(DISTINCT session_id) as unique_sessions
FROM events
WHERE event_time >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY DATE(event_time), event_type, country_code;

CREATE UNIQUE INDEX idx_daily_stats_date_type ON daily_event_stats (date, event_type, country_code);

-- User engagement summary
CREATE MATERIALIZED VIEW user_engagement_summary AS
SELECT 
    user_id,
    DATE(event_time) as date,
    COUNT(*) as events_count,
    COUNT(DISTINCT session_id) as sessions_count,
    MIN(event_time) as first_event,
    MAX(event_time) as last_event
FROM events
WHERE event_time >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY user_id, DATE(event_time);

CREATE UNIQUE INDEX idx_user_engagement_user_date ON user_engagement_summary (user_id, date);

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

-- Function to refresh materialized views
CREATE OR REPLACE FUNCTION refresh_dashboard_views()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY daily_event_stats;
    REFRESH MATERIALIZED VIEW CONCURRENTLY user_engagement_summary;
END;
$$ LANGUAGE plpgsql;

-- Function to get table size info
CREATE OR REPLACE FUNCTION get_table_stats()
RETURNS TABLE (
    table_name TEXT,
    row_count BIGINT,
    total_size TEXT,
    table_size TEXT,
    indexes_size TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        schemaname || '.' || tablename AS table_name,
        n_live_tup AS row_count,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
        pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS indexes_size
    FROM pg_stat_user_tables
    WHERE schemaname = 'public'
    ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- COMMENTS (Documentation)
-- ============================================================

COMMENT ON TABLE events IS 'Main event tracking table, partitioned by month for scalability';
COMMENT ON TABLE sessions IS 'Session-level aggregated data for analytics';
COMMENT ON TABLE users IS 'User dimension table with aggregated statistics';
COMMENT ON INDEX idx_events_time_brin IS 'BRIN index: ~1% size of B-tree, perfect for time-series data';
COMMENT ON INDEX idx_events_properties IS 'GIN index: enables fast JSONB queries but increases write cost';
