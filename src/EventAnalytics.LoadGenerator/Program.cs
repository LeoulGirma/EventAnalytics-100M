using System.CommandLine;
using System.Diagnostics;
using Spectre.Console;

namespace EventAnalytics.LoadGenerator;

class Program
{
    static async Task<int> Main(string[] args)
    {
        var rootCommand = new RootCommand("EventAnalytics Load Generator - Generate millions of realistic events");

        var rowsOption = new Option<long>(
            aliases: new[] { "--rows", "-r" },
            description: "Number of events to generate",
            getDefaultValue: () => 1_000_000);

        var batchOption = new Option<int>(
            aliases: new[] { "--batch-size", "-b" },
            description: "Batch size for bulk inserts",
            getDefaultValue: () => 50_000);

        var usersOption = new Option<int>(
            aliases: new[] { "--users", "-u" },
            description: "Number of unique users",
            getDefaultValue: () => 10_000);

        var connectionOption = new Option<string>(
            aliases: new[] { "--connection", "-c" },
            description: "PostgreSQL connection string",
            getDefaultValue: () => "Host=localhost;Port=5432;Database=analytics;Username=analytics_user;Password=dev_password_123;SSL Mode=Disable");

        var forceOption = new Option<bool>(
            aliases: new[] { "--force", "-f" },
            description: "Skip confirmation prompts",
            getDefaultValue: () => false);

        rootCommand.AddOption(rowsOption);
        rootCommand.AddOption(batchOption);
        rootCommand.AddOption(usersOption);
        rootCommand.AddOption(connectionOption);
        rootCommand.AddOption(forceOption);

        rootCommand.SetHandler(async (long rows, int batchSize, int users, string connection, bool force) =>
        {
            await RunGeneratorAsync(rows, batchSize, users, connection, force);
        }, rowsOption, batchOption, usersOption, connectionOption, forceOption);

        return await rootCommand.InvokeAsync(args);
    }

    static async Task RunGeneratorAsync(long totalRows, int batchSize, int uniqueUsers, string connectionString, bool force = false)
    {
        // Display banner
        AnsiConsole.Write(new FigletText("EventAnalytics").Color(Color.Cyan1));
        AnsiConsole.WriteLine();
        
        var panel = new Panel(
            $"[bold]Load Generator Configuration[/]\n\n" +
            $"Target Events:    [cyan1]{totalRows:N0}[/]\n" +
            $"Batch Size:       [cyan1]{batchSize:N0}[/]\n" +
            $"Unique Users:     [cyan1]{uniqueUsers:N0}[/]\n" +
            $"Connection:       [cyan1]{connectionString.Split(';')[0]}[/]")
        {
            Border = BoxBorder.Rounded,
            Padding = new Padding(2, 1)
        };
        AnsiConsole.Write(panel);
        AnsiConsole.WriteLine();

        // Initialize
        AnsiConsole.Status()
            .Start("Initializing data generator...", ctx =>
            {
                ctx.Spinner(Spinner.Known.Dots);
                ctx.SpinnerStyle(Style.Parse("cyan1"));
                Thread.Sleep(1000);
            });

        var config = new GeneratorConfig
        {
            TotalEvents = totalRows,
            BatchSize = batchSize,
            UniqueUsers = uniqueUsers,
            ConnectionString = connectionString,
            StartDate = DateTime.UtcNow.AddMonths(-6),
            EndDate = DateTime.UtcNow
        };

        var generator = new DataGenerator(config);
        AnsiConsole.MarkupLine("[green]✓[/] Data generator initialized");
        AnsiConsole.MarkupLine($"[dim]Generated {uniqueUsers:N0} users with Pareto distribution (80/20 rule)[/]");
        AnsiConsole.WriteLine();

        // Test connection
        try
        {
            using var testInserter = new BulkInserter(connectionString);
            var stats = await testInserter.GetStatsAsync();
            AnsiConsole.MarkupLine($"[green]✓[/] Database connected");
            AnsiConsole.MarkupLine($"[dim]Current events: {stats.TotalEvents:N0}, DB size: {stats.DatabaseSize}[/]");
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[red]✗[/] Connection failed: {ex.Message}");
            return;
        }

        AnsiConsole.WriteLine();

        // Confirm before loading large datasets
        if (totalRows >= 10_000_000 && !force)
        {
            if (!AnsiConsole.Confirm($"[yellow]About to load {totalRows:N0} events. This will take ~{EstimateTime(totalRows)} minutes. Continue?[/]"))
            {
                AnsiConsole.MarkupLine("[yellow]Cancelled[/]");
                return;
            }
            AnsiConsole.WriteLine();
        }

        // Start loading
        var stopwatch = Stopwatch.StartNew();
        long eventsLoaded = 0;

        await AnsiConsole.Progress()
            .Columns(new ProgressColumn[]
            {
                new TaskDescriptionColumn(),
                new ProgressBarColumn(),
                new PercentageColumn(),
                new RemainingTimeColumn(),
                new SpinnerColumn(),
            })
            .StartAsync(async ctx =>
            {
                var task = ctx.AddTask("[cyan1]Loading events[/]", maxValue: totalRows);

                using var inserter = new BulkInserter(connectionString);

                while (eventsLoaded < totalRows)
                {
                    var batchCount = (int)Math.Min(batchSize, totalRows - eventsLoaded);
                    var batch = generator.GenerateBatch(batchCount).ToList();

                    await inserter.InsertEventsAsync(batch);

                    eventsLoaded += batchCount;
                    task.Value = eventsLoaded;

                    // Update description with current rate
                    var currentRate = eventsLoaded / Math.Max(stopwatch.Elapsed.TotalSeconds, 1);
                    task.Description = $"[cyan1]Loading events[/] [dim]({currentRate:N0}/sec)[/]";
                }

                task.StopTask();
            });

        stopwatch.Stop();
        AnsiConsole.WriteLine();

        // Final statistics
        using var finalInserter = new BulkInserter(connectionString);
        
        AnsiConsole.Status()
            .Start("Analyzing database...", ctx =>
            {
                ctx.Spinner(Spinner.Known.Dots);
                finalInserter.AnalyzeAsync().Wait();
            });

        var finalStats = await finalInserter.GetStatsAsync();
        var partitions = await finalInserter.GetPartitionsAsync();

        // Display results
        var table = new Table()
            .Border(TableBorder.Rounded)
            .AddColumn("[bold]Metric[/]")
            .AddColumn("[bold]Value[/]");

        table.AddRow("Events Loaded", $"[cyan1]{eventsLoaded:N0}[/]");
        table.AddRow("Total Time", $"[cyan1]{stopwatch.Elapsed:hh\\:mm\\:ss}[/]");
        table.AddRow("Events/Second", $"[cyan1]{eventsLoaded / stopwatch.Elapsed.TotalSeconds:N0}[/]");
        table.AddRow("Database Size", $"[cyan1]{finalStats.DatabaseSize}[/]");
        table.AddRow("Events Table Size", $"[cyan1]{finalStats.TableSize}[/]");
        table.AddRow("Partitions Used", $"[cyan1]{partitions.Count(p => p.RowCount > 0)}[/]");

        AnsiConsole.Write(new Panel(table)
        {
            Header = new PanelHeader("[bold green]✓ Load Complete[/]"),
            Border = BoxBorder.Double
        });

        // Show partition distribution
        AnsiConsole.WriteLine();
        var partitionTable = new Table()
            .Border(TableBorder.Rounded)
            .AddColumn("[bold]Partition[/]")
            .AddColumn("[bold]Rows[/]", column => column.RightAligned())
            .AddColumn("[bold]Size[/]", column => column.RightAligned());

        foreach (var partition in partitions.Where(p => p.RowCount > 0).OrderByDescending(p => p.RowCount))
        {
            partitionTable.AddRow(
                partition.Name,
                $"{partition.RowCount:N0}",
                partition.Size
            );
        }

        AnsiConsole.Write(new Panel(partitionTable)
        {
            Header = new PanelHeader("[bold]Partition Distribution[/]")
        });

        // Next steps
        AnsiConsole.WriteLine();
        var nextSteps = new Panel(
            "[bold]Next Steps:[/]\n\n" +
            "1. Run benchmark queries:\n" +
            "   [cyan1]docker exec -it analytics_db psql -U analytics_user -d analytics -c \"SELECT COUNT(*) FROM events;\"[/]\n\n" +
            "2. Check query performance:\n" +
            "   [cyan1]docker exec -it analytics_db psql -U analytics_user -d analytics -c \"SELECT * FROM slow_queries;\"[/]\n\n" +
            "3. Monitor cache hit ratio:\n" +
            "   [cyan1]docker exec -it analytics_db psql -U analytics_user -d analytics -c \"SELECT * FROM cache_hit_ratio;\"[/]\n\n" +
            "4. View performance report:\n" +
            "   [cyan1]docker exec -it analytics_db psql -U analytics_user -d analytics -c \"SELECT * FROM performance_report();\"[/]")
        {
            Border = BoxBorder.Rounded,
            Padding = new Padding(2, 1)
        };
        AnsiConsole.Write(nextSteps);
    }

    static int EstimateTime(long rows)
    {
        // Rough estimate: ~500K events/second on modern hardware
        return (int)(rows / 500_000.0);
    }
}
