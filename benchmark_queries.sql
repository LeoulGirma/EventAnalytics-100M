-- EventAnalytics Benchmark Queries
-- Tests various aspects of database performance at scale

-- Q1: Simple COUNT - Tests basic index efficiency
SELECT COUNT(*) FROM events;

-- Q2: Time-range filter - Tests partition pruning
SELECT COUNT(*) FROM events WHERE event_time >= NOW() - INTERVAL '7 days';

-- Q3: GROUP BY - Tests aggregation performance
SELECT event_type, COUNT(*) FROM events
WHERE event_time >= NOW() - INTERVAL '24 hours'
GROUP BY event_type;

-- Q4: Complex aggregation - Tests query planning
SELECT user_id, COUNT(*) as events
FROM events WHERE event_time >= NOW() - INTERVAL '30 days'
GROUP BY user_id ORDER BY events DESC LIMIT 100;

-- Q5: JSONB query - Tests GIN index
SELECT COUNT(*) FROM events WHERE properties @> '{"test": true}'::jsonb;

-- Q6: Multi-filter stress test - Tests everything together
SELECT DATE(event_time), country_code, COUNT(*)
FROM events WHERE event_time >= NOW() - INTERVAL '7 days'
GROUP BY DATE(event_time), country_code
ORDER BY DATE(event_time) DESC LIMIT 50;