using Npgsql;
using System.Globalization;
using System.Text;

namespace EventAnalytics.LoadGenerator;

/// <summary>
/// High-performance bulk inserter using PostgreSQL COPY command
/// </summary>
public class BulkInserter : IDisposable
{
    private readonly NpgsqlConnection _connection;
    private bool _disposed;

    public BulkInserter(string connectionString)
    {
        _connection = new NpgsqlConnection(connectionString);
        _connection.Open();
    }

    /// <summary>
    /// Bulk insert events using COPY command (fastest method)
    /// </summary>
    public async Task InsertEventsAsync(IEnumerable<Event> events, CancellationToken cancellationToken = default)
    {
        // COPY is 10-100x faster than INSERT for bulk loads
        // It bypasses most of PostgreSQL's overhead and writes directly to data files
        
        var copyCommand = @"
            COPY events (
                event_time, user_id, session_id, event_type, properties,
                page_url, referrer, device_type, browser, os,
                country_code, city, created_at
            ) FROM STDIN (FORMAT BINARY)";

        await using var writer = await _connection.BeginBinaryImportAsync(copyCommand, cancellationToken);
        
        foreach (var evt in events)
        {
            if (cancellationToken.IsCancellationRequested)
                break;
                
            await writer.StartRowAsync(cancellationToken);
            
            // Write each column in order
            await writer.WriteAsync(evt.EventTime, NpgsqlTypes.NpgsqlDbType.TimestampTz, cancellationToken);
            await writer.WriteAsync(evt.UserId, NpgsqlTypes.NpgsqlDbType.Uuid, cancellationToken);
            await writer.WriteAsync(evt.SessionId, NpgsqlTypes.NpgsqlDbType.Uuid, cancellationToken);
            await writer.WriteAsync(evt.EventType, NpgsqlTypes.NpgsqlDbType.Varchar, cancellationToken);
            await writer.WriteAsync(evt.Properties, NpgsqlTypes.NpgsqlDbType.Jsonb, cancellationToken);
            await writer.WriteAsync(evt.PageUrl, NpgsqlTypes.NpgsqlDbType.Text, cancellationToken);
            await writer.WriteAsync(evt.Referrer, NpgsqlTypes.NpgsqlDbType.Text, cancellationToken);
            await writer.WriteAsync(evt.DeviceType, NpgsqlTypes.NpgsqlDbType.Varchar, cancellationToken);
            await writer.WriteAsync(evt.Browser, NpgsqlTypes.NpgsqlDbType.Varchar, cancellationToken);
            await writer.WriteAsync(evt.Os, NpgsqlTypes.NpgsqlDbType.Varchar, cancellationToken);
            await writer.WriteAsync(evt.CountryCode, NpgsqlTypes.NpgsqlDbType.Char, cancellationToken);
            await writer.WriteAsync(evt.City, NpgsqlTypes.NpgsqlDbType.Varchar, cancellationToken);
            await writer.WriteAsync(DateTime.UtcNow, NpgsqlTypes.NpgsqlDbType.TimestampTz, cancellationToken);
        }
        
        await writer.CompleteAsync(cancellationToken);
    }

    /// <summary>
    /// Get current database statistics
    /// </summary>
    public async Task<DatabaseStats> GetStatsAsync()
    {
        var query = @"
            SELECT 
                COALESCE(SUM(n_live_tup), 0) as total_events,
                pg_size_pretty(pg_database_size(current_database())) as db_size,
                pg_size_pretty(pg_total_relation_size('events')) as table_size
            FROM pg_stat_user_tables 
            WHERE schemaname = 'public' AND relname LIKE 'events_%'";

        await using var cmd = new NpgsqlCommand(query, _connection);
        await using var reader = await cmd.ExecuteReaderAsync();
        
        if (await reader.ReadAsync())
        {
            return new DatabaseStats
            {
                TotalEvents = reader.GetInt64(0),
                DatabaseSize = reader.GetString(1),
                TableSize = reader.GetString(2)
            };
        }
        
        return new DatabaseStats();
    }

    /// <summary>
    /// Run ANALYZE to update statistics (important for query performance)
    /// </summary>
    public async Task AnalyzeAsync()
    {
        await using var cmd = new NpgsqlCommand("ANALYZE events", _connection);
        await cmd.ExecuteNonQueryAsync();
    }

    /// <summary>
    /// Get partition distribution
    /// </summary>
    public async Task<List<PartitionInfo>> GetPartitionsAsync()
    {
        var query = @"
            SELECT 
                c.relname as partition_name,
                pg_stat_get_live_tuples(c.oid) as row_count,
                pg_size_pretty(pg_total_relation_size(c.oid)) as size
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN pg_inherits i ON i.inhrelid = c.oid
            JOIN pg_class p ON p.oid = i.inhparent
            WHERE p.relname = 'events'
            AND n.nspname = 'public'
            ORDER BY c.relname";

        var partitions = new List<PartitionInfo>();
        
        await using var cmd = new NpgsqlCommand(query, _connection);
        await using var reader = await cmd.ExecuteReaderAsync();
        
        while (await reader.ReadAsync())
        {
            partitions.Add(new PartitionInfo
            {
                Name = reader.GetString(0),
                RowCount = reader.GetInt64(1),
                Size = reader.GetString(2)
            });
        }
        
        return partitions;
    }

    public void Dispose()
    {
        if (_disposed) return;
        
        _connection?.Dispose();
        _disposed = true;
        GC.SuppressFinalize(this);
    }
}

/// <summary>
/// Database statistics
/// </summary>
public record DatabaseStats
{
    public long TotalEvents { get; init; }
    public string DatabaseSize { get; init; } = string.Empty;
    public string TableSize { get; init; } = string.Empty;
}

/// <summary>
/// Partition information
/// </summary>
public record PartitionInfo
{
    public string Name { get; init; } = string.Empty;
    public long RowCount { get; init; }
    public string Size { get; init; } = string.Empty;
}
