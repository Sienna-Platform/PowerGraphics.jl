# Time window key words and plots layered with the `!` forms, on both backends.

(layer_results_uc, layer_results_ed) = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)
const LAYER_TIMES = collect(PSI.get_realized_timestamps(layer_results_uc))

series_color_map(p) = Dict(s.label => s.color for s in get_plot_series(p))

@testset "removed start_time and len key words throw" begin
    results = Dict(
        "Load" => DataFrames.DataFrame(
            "DateTime" => LAYER_TIMES[1:4],
            "x" => [1.0, 2.0, 3.0, 4.0],
        ),
    )
    t0 = first(LAYER_TIMES)
    for (_, backend) in TEST_BACKENDS
        p = plot_results(results; backend = backend, set_display = false)
        calls = [
            kw -> plot_demand(layer_results_uc; backend = backend, kw...),
            kw -> plot_demand!(p, layer_results_uc; backend = backend, kw...),
            kw -> plot_fuel(layer_results_uc; backend = backend, kw...),
            kw -> plot_fuel!(p, layer_results_uc; backend = backend, kw...),
            kw -> plot_results(results; backend = backend, kw...),
            kw -> plot_results!(p, results; backend = backend, kw...),
        ]
        for call in calls
            @test_throws ArgumentError(
                "The `start_time` key word was removed; use `initial_time` instead.",
            ) call((set_display = false, start_time = t0))
            @test_throws ArgumentError(
                "The `len` key word was removed; use `horizon` instead.",
            ) call((set_display = false, len = 3))
        end
    end
end

@testset "time windows outside the results throw ArgumentError" begin
    t0, t_end = first(LAYER_TIMES), last(LAYER_TIMES)
    step = LAYER_TIMES[2] - t0
    windows = [
        (initial_time = t0 - step,),
        (initial_time = t_end + step,),
        (initial_time = t0 + Minute(30),),
        (initial_time = t_end - step, horizon = 3),
        (horizon = 0,),
    ]
    for (_, backend) in TEST_BACKENDS, window in windows
        @test_throws ArgumentError plot_demand(
            layer_results_uc;
            backend = backend,
            set_display = false,
            window...,
        )
        @test_throws ArgumentError plot_fuel(
            layer_results_uc;
            backend = backend,
            set_display = false,
            window...,
        )
    end
end

@testset "$backend_pkg plots a single time step" for (backend_pkg, backend) in
                                                     TEST_BACKENDS
    t0 = LAYER_TIMES[5]
    for p in (
        plot_demand(
            layer_results_uc;
            backend = backend,
            set_display = false,
            initial_time = t0,
            horizon = 1,
        ),
        plot_fuel(
            layer_results_uc;
            backend = backend,
            set_display = false,
            initial_time = t0,
            horizon = 1,
        ),
    )
        @test series_count(p) > 0
        @test all(s -> length(s.values) == 1, get_plot_series(p))
    end
    full = plot_demand(layer_results_uc; backend = backend, set_display = false)
    single = plot_demand(
        layer_results_uc;
        backend = backend,
        set_display = false,
        initial_time = t0,
        horizon = 1,
    )
    @test series_values(single, "Load") ≈ series_values(full, "Load")[5:5]

    # The `PSY.System` path takes the step from the load forecasts.
    sys = deepcopy(PSB.build_system(PSB.PSITestSystems, "c_sys5_uc"))
    sys_t0 = collect(get_forecast_initial_times(sys))[2]
    p = plot_demand(
        sys;
        backend = backend,
        set_display = false,
        initial_time = sys_t0,
        horizon = 1,
    )
    @test series_count(p) > 0
    @test all(s -> length(s.values) == 1, get_plot_series(p))

    # A single-row `DataFrame` needs the `resolution` key word.
    one_row = DataFrames.DataFrame("a" => [1.0])
    @test_throws ArgumentError(
        "plotting a single time step requires the `resolution` key word",
    ) plot_dataframe(one_row, LAYER_TIMES[1:1]; backend = backend, set_display = false)
    p = plot_dataframe(
        one_row,
        LAYER_TIMES[1:1];
        backend = backend,
        set_display = false,
        resolution = Hour(1),
    )
    @test series_values(p, "a") == [1.0]
end

@testset "$backend_pkg plot_fuel! keeps the fuel colors on a non-empty plot" for (
    backend_pkg,
    backend,
) in TEST_BACKENDS
    standalone = series_color_map(
        plot_fuel(layer_results_uc; backend = backend, set_display = false, load = false),
    )
    p = plot_demand(layer_results_uc; backend = backend, set_display = false)
    plot_fuel!(p, layer_results_uc; backend = backend, set_display = false, load = false)
    layered = series_color_map(p)
    @test length(layered) == length(standalone) + 1
    for (label, color) in standalone
        @test layered[label] == color
    end

    # The default palette continues past the series already drawn.
    df = DataFrames.DataFrame("a" => ones(length(LAYER_TIMES)))
    p = plot_dataframe(df, LAYER_TIMES; backend = backend, set_display = false)
    plot_demand!(p, layer_results_uc; backend = backend, set_display = false)
    @test series_colors(p) == [_canonical_color(c.color) for c in PG.PALETTE[1:2]]
end

@testset "PlotlyLight load line has its own stack group" begin
    p = plot_fuel(layer_results_ed; backend = PlotlyLightBackend(), set_display = false)
    groups = Dict(trace.name => get(trace, :stackgroup, nothing) for trace in p.data)
    @test haskey(groups, "Load")
    @test any(<(0), series_values(p, "Storage In"))
    fuel_groups = [g for (name, g) in groups if name != "Load"]
    @test !isnothing(groups["Load"])
    @test groups["Load"] ∉ fuel_groups
    # Fuel series of the same sign share a stack group.
    @test length(unique(fuel_groups)) == 2

    # A filled unstacked series drawn after ten stacked series, one of them negative,
    # gets a stack group of its own.
    stacked = DataFrames.DataFrame(
        ["c$ix" => fill(ix == 1 ? -1.0 : 1.0, length(LAYER_TIMES)) for ix in 1:10],
    )
    p = plot_dataframe(
        stacked,
        LAYER_TIMES;
        backend = PlotlyLightBackend(),
        set_display = false,
        stack = true,
    )
    plot_dataframe!(
        p,
        DataFrames.DataFrame("line" => ones(length(LAYER_TIMES))),
        LAYER_TIMES;
        backend = PlotlyLightBackend(),
        set_display = false,
        stack = false,
        nofill = false,
    )
    stacked_groups = unique(trace.stackgroup for trace in p.data[1:10])
    @test length(stacked_groups) == 2
    @test p.data[11].stackgroup ∉ stacked_groups
end
