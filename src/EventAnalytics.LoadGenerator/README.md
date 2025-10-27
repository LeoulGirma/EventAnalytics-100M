# EventAnalytics Load Generator

High-performance data generator for the 100M Row Challenge. Generates realistic synthetic event data using the PostgreSQL COPY command.

## Features

- ✅ **Realistic Data Patterns**
  - Pareto distribution (20% of users create 80% of events)
  - Time-based patterns (business hours have more traffic)
  - Geographic distribution (US-heavy, realistic city distribution)
  - Session-based behavior
  
- ✅ **High Performance**
  - PostgreSQL COPY command (10-100x faster than INSERT)
  - Configurable batch sizes
  - Progress tracking with ETA
  - ~500K-1M events/second on modern hardware

- ✅ **Production-Like Data**
  - Real event types (page_view, click, form_submit, etc.)
  - Device/browser distribution
  - JSONB properties
  - Referrer tracking

## Prerequisites

- .NET 8 SDK
- PostgreSQL running (via Docker Compose)

## Build

```bash
cd src/EventAnalytics.LoadGenerator
dotnet build
```

## Usage

### Quick Start (1M events)

```bash
dotnet run
```

### 20M Events (Phase 1 of Challenge)

```bash
dotnet run -- --rows 20000000
```

### 50M Events (Phase 2 of Challenge)

```bash
dotnet run -- --rows 50000000
```

### 100M Events (Phase 3 of Challenge - The Big One!)

```bash
dotnet run -- --rows 100000000
```

## Command Line Options

```
Options:
  -r, --rows <rows>              Number of events to generate [default: 1000000]
  -b, --batch-size <batch-size>  Batch size for bulk inserts [default: 50000]
  -u, --users <users>            Number of unique users [default: 10000]
  -c, --connection <connection>  PostgreSQL connection string
```

### Examples

```bash
# Generate 5M events with custom batch size
dotnet run -- --rows 5000000 --batch-size 100000

# Generate 10M events with 50K unique users
dotnet run -- --rows 10000000 --users 50000

# Custom connection string
dotnet run -- --connection "Host=localhost;Port=5432;Database=analytics;Username=analytics_user;Password=dev_password_123"
```

## Performance Expectations

| Events | Time (estimate) | Database Size | Partitions |
|--------|----------------|---------------|------------|
| 1M     | ~5 seconds     | ~200 MB       | 1-2        |
| 10M    | ~30 seconds    | ~2 GB         | 2-4        |
| 20M    | ~1 minute      | ~4 GB         | 3-5        |
| 50M    | ~2-3 minutes   | ~10 GB        | 5-8        |
| 100M   | ~5-7 minutes   | ~20 GB        | 8-13       |

*Times vary based on hardware. Your i5-10300H with NVME should be in this range.*

## Data Generation Strategy

### User Distribution (Pareto - 80/20 Rule)
```
Top 20% of users → 80% of events (heavy users)
Bottom 80% of users → 20% of events (casual users)
```

### Time Distribution
```
Business hours (9 AM - 5 PM): 70% of traffic
Off-hours: 30% of traffic
Weekends: 40% of weekday traffic
```

### Geographic Distribution
```
US:  45%  (10 major cities)
UK:  12%  (8 major cities)
CA:  10%  (6 major cities)
DE:  8%   (6 major cities)
FR:  7%   (6 major cities)
AU:  6%   (5 major cities)
IN:  5%   (6 major cities)
BR:  4%   (5 major cities)
JP:  3%   (5 major cities)
```

### Event Type Distribution
```
page_view:    60%
click:        25%
form_submit:  10%
video_play:   3%
download:     2%
```

### Device Distribution
```
Desktop: 55%
Mobile:  40%
Tablet:  5%
```

## Monitoring During Load

### Watch Progress
The generator shows:
- Progress bar with percentage
- Current events/second rate
- Estimated time remaining
- Final statistics

### Monitor Database
In another terminal:

```bash
# Watch events count
watch -n 1 'docker exec analytics_db psql -U analytics_user -d analytics -t -c "SELECT COUNT(*) FROM events;"'

# Check partition distribution
docker exec -it analytics_db psql -U analytics_user -d analytics -c "SELECT * FROM list_partitions();"

# Monitor cache hit ratio
docker exec -it analytics_db psql -U analytics_user -d analytics -c "SELECT * FROM cache_hit_ratio;"
```

## Troubleshooting

### Error: Connection failed
**Solution:** Ensure PostgreSQL is running:
```bash
docker ps | grep analytics_db
# If not running:
docker-compose up -d
```

### Slow performance
**Possible causes:**
1. Low disk space (check with `df -h`)
2. Other processes using CPU/disk
3. Insufficient PostgreSQL memory (check docker-compose.yml settings)

**Solutions:**
- Close other applications
- Reduce batch size: `--batch-size 25000`
- Check PostgreSQL logs: `docker-compose logs postgres`

### Out of memory
**Solution:** Reduce batch size:
```bash
dotnet run -- --rows 100000000 --batch-size 25000
```

## Verifying Data Quality

After loading, verify the data looks realistic:

```sql
-- Check event type distribution
SELECT event_type, COUNT(*), ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) as pct
FROM events
GROUP BY event_type
ORDER BY COUNT(*) DESC;

-- Check geographic distribution
SELECT country_code, COUNT(*), ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) as pct
FROM events
GROUP BY country_code
ORDER BY COUNT(*) DESC;

-- Check time distribution
SELECT EXTRACT(HOUR FROM event_time) as hour, COUNT(*)
FROM events
GROUP BY hour
ORDER BY hour;

-- Check top users (should follow Pareto)
SELECT user_id, COUNT(*) as event_count
FROM events
GROUP BY user_id
ORDER BY event_count DESC
LIMIT 20;
```

## What's Next?

After loading data:

1. **Benchmark Queries** - Test common analytics queries
2. **Optimize Indexes** - Find missing or unused indexes
3. **Monitor Bloat** - Check table/index bloat
4. **Test Backups** - Time a full database backup
5. **Build Dashboard** - Create the ASP.NET Core API

## Architecture

```
DataGenerator (Bogus)
     ↓
Generate realistic events
     ↓
BulkInserter (Npgsql COPY)
     ↓
PostgreSQL (Partitioned Table)
     ↓
Indexes automatically maintained
```

## Performance Tips

1. **Batch Size:** 50K is optimal for most systems. Larger = more memory, smaller = more overhead
2. **Parallel Loading:** Can run multiple instances targeting different time ranges
3. **Index Strategy:** All indexes are created upfront. Could disable/rebuild for faster loads.
4. **Partition Pruning:** Events automatically routed to correct monthly partition

## Source Code

- `Models.cs` - Data models matching database schema
- `DataGenerator.cs` - Bogus-based realistic fake data generation
- `BulkInserter.cs` - PostgreSQL COPY bulk insert implementation
- `Program.cs` - CLI with progress tracking

## License

MIT - Part of the EventAnalytics 100M Row Challenge
