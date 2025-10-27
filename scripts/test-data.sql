-- ============================================================
-- SAMPLE DATA FOR TESTING
-- ============================================================
-- This inserts 1000 sample events to verify the schema works
-- Run: docker exec -it analytics_db psql -U analytics_user -d analytics -f /path/to/test-data.sql

\echo '🧪 Inserting sample test data...'
\echo ''

-- Create some test users
INSERT INTO users (id, email, first_seen, country_code, signup_date)
SELECT 
    gen_random_uuid(),
    'user' || generate_series || '@test.com',
    NOW() - (random() * INTERVAL '30 days'),
    CASE (random() * 5)::int
        WHEN 0 THEN 'US'
        WHEN 1 THEN 'CA'
        WHEN 2 THEN 'GB'
        WHEN 3 THEN 'DE'
        ELSE 'FR'
    END,
    CURRENT_DATE - (random() * 30)::int
FROM generate_series(1, 100);

\echo '✅ Created 100 test users'

-- Create some test sessions
WITH test_users AS (
    SELECT id FROM users LIMIT 50
)
INSERT INTO sessions (id, user_id, started_at, ended_at, duration_seconds, page_views, device_type, country_code)
SELECT 
    gen_random_uuid(),
    (SELECT id FROM test_users ORDER BY random() LIMIT 1),
    NOW() - (random() * INTERVAL '7 days'),
    NOW() - (random() * INTERVAL '7 days') + INTERVAL '5 minutes',
    (random() * 600)::int,
    (random() * 20)::int,
    CASE (random() * 2)::int
        WHEN 0 THEN 'desktop'
        WHEN 1 THEN 'mobile'
        ELSE 'tablet'
    END,
    CASE (random() * 5)::int
        WHEN 0 THEN 'US'
        WHEN 1 THEN 'CA'
        WHEN 2 THEN 'GB'
        WHEN 3 THEN 'DE'
        ELSE 'FR'
    END
FROM generate_series(1, 200);

\echo '✅ Created 200 test sessions'

-- Create test events (1000 events)
WITH test_sessions AS (
    SELECT id, user_id, started_at, device_type, country_code FROM sessions LIMIT 100
)
INSERT INTO events (
    event_time,
    user_id,
    session_id,
    event_type,
    properties,
    page_url,
    referrer,
    device_type,
    browser,
    os,
    country_code,
    city
)
SELECT 
    s.started_at + (random() * INTERVAL '10 minutes'),
    s.user_id,
    s.id,
    CASE (random() * 10)::int
        WHEN 0, 1, 2, 3, 4, 5 THEN 'page_view'
        WHEN 6, 7, 8 THEN 'click'
        ELSE 'form_submit'
    END,
    jsonb_build_object(
        'button_id', CASE (random() * 3)::int WHEN 0 THEN 'signup' WHEN 1 THEN 'login' ELSE 'checkout' END,
        'value', (random() * 100)::numeric(10,2),
        'test', true
    ),
    CASE (random() * 8)::int
        WHEN 0 THEN '/homepage'
        WHEN 1 THEN '/products'
        WHEN 2 THEN '/pricing'
        WHEN 3 THEN '/about'
        WHEN 4 THEN '/contact'
        WHEN 5 THEN '/blog'
        WHEN 6 THEN '/signup'
        ELSE '/login'
    END,
    CASE (random() * 4)::int
        WHEN 0 THEN 'https://google.com'
        WHEN 1 THEN 'https://facebook.com'
        WHEN 2 THEN NULL
        ELSE 'direct'
    END,
    s.device_type,
    CASE (random() * 3)::int
        WHEN 0 THEN 'Chrome'
        WHEN 1 THEN 'Safari'
        ELSE 'Firefox'
    END,
    CASE (random() * 3)::int
        WHEN 0 THEN 'Windows'
        WHEN 1 THEN 'macOS'
        ELSE 'Linux'
    END,
    s.country_code,
    CASE s.country_code
        WHEN 'US' THEN (ARRAY['New York', 'Los Angeles', 'Chicago', 'Houston', 'Phoenix'])[floor(random() * 5 + 1)]
        WHEN 'GB' THEN (ARRAY['London', 'Manchester', 'Birmingham'])[floor(random() * 3 + 1)]
        WHEN 'DE' THEN (ARRAY['Berlin', 'Munich', 'Hamburg'])[floor(random() * 3 + 1)]
        WHEN 'FR' THEN (ARRAY['Paris', 'Lyon', 'Marseille'])[floor(random() * 3 + 1)]
        ELSE 'Toronto'
    END
FROM test_sessions s
CROSS JOIN generate_series(1, 10);

\echo '✅ Created 1000 test events'
\echo ''

-- Show what we created
\echo '📊 Summary:'
\echo '==========='

SELECT 
    'Users: ' || COUNT(*) 
FROM users;

SELECT 
    'Sessions: ' || COUNT(*) 
FROM sessions;

SELECT 
    'Events: ' || COUNT(*) 
FROM events;

\echo ''
\echo '📈 Events by Type:'
SELECT 
    event_type,
    COUNT(*) as count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) as percentage
FROM events
GROUP BY event_type
ORDER BY count DESC;

\echo ''
\echo '🗺️  Events by Country:'
SELECT 
    country_code,
    COUNT(*) as count
FROM events
GROUP BY country_code
ORDER BY count DESC;

\echo ''
\echo '📱 Events by Device:'
SELECT 
    device_type,
    COUNT(*) as count
FROM events
GROUP BY device_type
ORDER BY count DESC;

\echo ''
\echo '✅ Test data created successfully!'
\echo 'Ready for performance testing.'
