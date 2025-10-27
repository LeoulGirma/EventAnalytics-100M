using Bogus;

namespace EventAnalytics.LoadGenerator;

/// <summary>
/// Generates realistic synthetic event data
/// </summary>
public class DataGenerator
{
    private readonly GeneratorConfig _config;
    private readonly Random _random = new();
    private readonly List<User> _users;
    private readonly List<Session> _sessions;
    
    // Event type distribution (matches real-world analytics)
    private static readonly (string Type, double Weight)[] EventTypes = new[]
    {
        ("page_view", 0.60),      // 60% page views
        ("click", 0.25),          // 25% clicks
        ("form_submit", 0.10),    // 10% form submits
        ("video_play", 0.03),     // 3% video plays
        ("download", 0.02)        // 2% downloads
    };
    
    // Geographic distribution (mimics real traffic)
    private static readonly (string Country, string[] Cities, double Weight)[] Locations = new[]
    {
        ("US", new[] { "New York", "Los Angeles", "Chicago", "Houston", "Phoenix", "Philadelphia", "San Antonio", "San Diego", "Dallas", "San Jose" }, 0.45),
        ("GB", new[] { "London", "Manchester", "Birmingham", "Leeds", "Glasgow", "Liverpool", "Newcastle", "Sheffield" }, 0.12),
        ("CA", new[] { "Toronto", "Montreal", "Vancouver", "Calgary", "Ottawa", "Edmonton" }, 0.10),
        ("DE", new[] { "Berlin", "Munich", "Hamburg", "Frankfurt", "Cologne", "Stuttgart" }, 0.08),
        ("FR", new[] { "Paris", "Lyon", "Marseille", "Toulouse", "Nice", "Nantes" }, 0.07),
        ("AU", new[] { "Sydney", "Melbourne", "Brisbane", "Perth", "Adelaide" }, 0.06),
        ("IN", new[] { "Mumbai", "Delhi", "Bangalore", "Hyderabad", "Chennai", "Kolkata" }, 0.05),
        ("BR", new[] { "São Paulo", "Rio de Janeiro", "Brasília", "Salvador", "Fortaleza" }, 0.04),
        ("JP", new[] { "Tokyo", "Osaka", "Kyoto", "Yokohama", "Nagoya" }, 0.03)
    };
    
    // Device distribution
    private static readonly (string Device, double Weight)[] Devices = new[]
    {
        ("desktop", 0.55),
        ("mobile", 0.40),
        ("tablet", 0.05)
    };
    
    // Browser distribution
    private static readonly (string Browser, double Weight)[] Browsers = new[]
    {
        ("Chrome", 0.65),
        ("Safari", 0.20),
        ("Firefox", 0.08),
        ("Edge", 0.05),
        ("Other", 0.02)
    };

    public DataGenerator(GeneratorConfig config)
    {
        _config = config;
        _users = GenerateUsers();
        _sessions = GenerateSessions();
    }

    /// <summary>
    /// Generate users with Pareto distribution (80/20 rule)
    /// </summary>
    private List<User> GenerateUsers()
    {
        var users = new List<User>(_config.UniqueUsers);
        var heavyUserCount = (int)(_config.UniqueUsers * _config.HeavyUserPercentage);
        
        for (int i = 0; i < _config.UniqueUsers; i++)
        {
            var location = SelectWeighted(Locations.Select(l => (l, l.Weight)).ToArray());
            var isHeavyUser = i < heavyUserCount;

            users.Add(new User
            {
                Id = Guid.NewGuid(),
                CountryCode = location.Country,
                ActivityMultiplier = isHeavyUser ? _config.HeavyUserActivityMultiplier : 1.0
            });
        }
        
        return users;
    }

    /// <summary>
    /// Generate sessions (realistic session behavior)
    /// </summary>
    private List<Session> GenerateSessions()
    {
        // Average 5 sessions per user, but weighted by user activity
        var totalWeight = _users.Sum(u => u.ActivityMultiplier);
        var sessionsPerUser = _users.Select(u => 
            (int)(5 * u.ActivityMultiplier * (_users.Count / totalWeight))
        ).ToList();
        
        var sessions = new List<Session>();
        
        foreach (var user in _users)
        {
            var userSessions = (int)(5 * user.ActivityMultiplier);
            var location = Locations.First(l => l.Country == user.CountryCode);
            
            for (int i = 0; i < userSessions; i++)
            {
                var device = SelectWeighted(Devices.Select(d => (d, d.Weight)).ToArray());
                var browser = SelectWeighted(Browsers.Select(b => (b, b.Weight)).ToArray());
                var city = location.Cities[_random.Next(location.Cities.Length)];

                sessions.Add(new Session
                {
                    Id = Guid.NewGuid(),
                    UserId = user.Id,
                    StartedAt = RandomDateTime(_config.StartDate, _config.EndDate),
                    DeviceType = device.Device,
                    Browser = browser.Browser,
                    CountryCode = user.CountryCode,
                    City = city,
                    EventsInSession = _random.Next(1, 50) // 1-50 events per session
                });
            }
        }
        
        return sessions;
    }

    /// <summary>
    /// Generate a batch of events
    /// </summary>
    public IEnumerable<Event> GenerateBatch(int count)
    {
        for (int i = 0; i < count; i++)
        {
            yield return GenerateEvent();
        }
    }

    /// <summary>
    /// Generate a single realistic event
    /// </summary>
    private Event GenerateEvent()
    {
        // Select a session (weighted by activity)
        var session = _sessions[_random.Next(_sessions.Count)];
        
        // Events within a session are close in time
        var eventTime = session.StartedAt.AddMinutes(_random.Next(0, 30));
        
        // Apply business hours weighting (9 AM - 5 PM has 3x traffic)
        while (eventTime.Hour < 9 || eventTime.Hour > 17)
        {
            if (_random.NextDouble() < 0.33) break; // 33% chance to keep off-hours event
            eventTime = RandomDateTime(_config.StartDate, _config.EndDate);
        }
        
        var eventType = SelectWeighted(EventTypes.Select(e => (e, e.Weight)).ToArray());
        var faker = new Faker();

        // Generate properties based on event type
        var properties = eventType.Type switch
        {
            "click" => $$"""{"button_id":"{{faker.Random.Word()}}","value":{{faker.Random.Double(0, 100):F2}}}""",
            "form_submit" => $$"""{"form_id":"{{faker.Random.Word()}}","fields":{{faker.Random.Int(1, 10)}}}""",
            "video_play" => $$"""{"video_id":"{{faker.Random.AlphaNumeric(10)}}","duration":{{faker.Random.Int(30, 600)}}}""",
            "download" => $$"""{"file_name":"{{faker.System.FileName()}}","size":{{faker.Random.Int(1024, 10485760)}}}""",
            _ => "{}"
        };
        
        return new Event
        {
            EventTime = eventTime,
            UserId = session.UserId,
            SessionId = session.Id,
            EventType = eventType.Type,
            Properties = properties,
            PageUrl = faker.Internet.UrlWithPath(),
            Referrer = _random.NextDouble() < 0.3 ? null : faker.Internet.Url(),
            DeviceType = session.DeviceType,
            Browser = session.Browser,
            Os = session.DeviceType switch
            {
                "desktop" => faker.PickRandom("Windows", "macOS", "Linux"),
                "mobile" => faker.PickRandom("iOS", "Android"),
                "tablet" => faker.PickRandom("iOS", "Android"),
                _ => "Unknown"
            },
            CountryCode = session.CountryCode,
            City = session.City
        };
    }

    /// <summary>
    /// Select an item based on weighted probability
    /// </summary>
    private T SelectWeighted<T>((T Item, double Weight)[] items)
    {
        var totalWeight = items.Sum(i => i.Weight);
        var randomValue = _random.NextDouble() * totalWeight;
        
        double cumulative = 0;
        foreach (var item in items)
        {
            cumulative += item.Weight;
            if (randomValue <= cumulative)
                return item.Item;
        }
        
        return items[^1].Item;
    }

    /// <summary>
    /// Generate a random datetime between two dates
    /// </summary>
    private DateTime RandomDateTime(DateTime start, DateTime end)
    {
        var range = end - start;
        var randomSpan = TimeSpan.FromSeconds(_random.NextDouble() * range.TotalSeconds);
        return start + randomSpan;
    }
}
