namespace EventAnalytics.LoadGenerator;

/// <summary>
/// Event model matching the events table schema
/// </summary>
public record Event
{
    public DateTime EventTime { get; init; }
    public Guid UserId { get; init; }
    public Guid SessionId { get; init; }
    public string EventType { get; init; } = string.Empty;
    public string Properties { get; init; } = "{}"; // JSON string
    public string? PageUrl { get; init; }
    public string? Referrer { get; init; }
    public string? DeviceType { get; init; }
    public string? Browser { get; init; }
    public string? Os { get; init; }
    public string? CountryCode { get; init; }
    public string? City { get; init; }
}

/// <summary>
/// Session model for generating user sessions
/// </summary>
public record Session
{
    public Guid Id { get; init; }
    public Guid UserId { get; init; }
    public DateTime StartedAt { get; init; }
    public string DeviceType { get; init; } = string.Empty;
    public string Browser { get; init; } = string.Empty;
    public string CountryCode { get; init; } = string.Empty;
    public string City { get; init; } = string.Empty;
    public int EventsInSession { get; init; }
}

/// <summary>
/// User model for Pareto distribution (80/20 rule)
/// </summary>
public record User
{
    public Guid Id { get; init; }
    public string CountryCode { get; init; } = string.Empty;
    public double ActivityMultiplier { get; init; } // Heavy users have higher multiplier
}

/// <summary>
/// Configuration for data generation
/// </summary>
public record GeneratorConfig
{
    public long TotalEvents { get; init; }
    public int BatchSize { get; init; } = 50000;
    public int UniqueUsers { get; init; } = 10000;
    public DateTime StartDate { get; init; } = DateTime.UtcNow.AddMonths(-6);
    public DateTime EndDate { get; init; } = DateTime.UtcNow;
    public string ConnectionString { get; init; } = string.Empty;
    
    // Data distribution settings
    public double HeavyUserPercentage { get; init; } = 0.2; // Top 20% of users
    public double HeavyUserActivityMultiplier { get; init; } = 4.0; // Create 80% of events
}

/// <summary>
/// Performance statistics
/// </summary>
public record LoadStats
{
    public long TotalEvents { get; init; }
    public long EventsLoaded { get; init; }
    public TimeSpan Elapsed { get; init; }
    public double EventsPerSecond { get; init; }
    public TimeSpan EstimatedTimeRemaining { get; init; }
    
    public static LoadStats Calculate(long total, long loaded, TimeSpan elapsed)
    {
        var eventsPerSec = loaded / Math.Max(elapsed.TotalSeconds, 1);
        var remaining = (total - loaded) / Math.Max(eventsPerSec, 1);
        
        return new LoadStats
        {
            TotalEvents = total,
            EventsLoaded = loaded,
            Elapsed = elapsed,
            EventsPerSecond = eventsPerSec,
            EstimatedTimeRemaining = TimeSpan.FromSeconds(remaining)
        };
    }
}
