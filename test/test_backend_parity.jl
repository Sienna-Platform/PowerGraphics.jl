# Regression tests for the two refactors that unified the backends:
#
#   1. the `_plotly`-suffixed API collapsed into a `backend` key word, with the
#      old names kept as deprecated shims, and
#   2. eight per-plot behaviors (fill default, line width, line style, draw
#      order, title sentinel, empty input, default save format, palette
#      selection) resolved once in `src/call_plots.jl` instead of twice in the
#      recipes.
#
# Both refactors are only worth anything if the two backends now agree, so the
# assertions here are written through the backend-agnostic helpers in
# `plot_introspection.jl` and compare CairoMakie against PlotlyLight directly.

const PARITY_BACKENDS =
    (("cairomakie", CairoMakieBackend()), ("plotlylight", PlotlyLightBackend()))
const PARITY_EXTENSION = Dict("cairomakie" => ".png", "plotlylight" => ".html")

parity_time() =
    collect(range(DateTime("2024-01-01T00:00:00"); step = Hour(1), length = 6))

# All-positive columns, so the draw order is the column order and the palette
# selection can be checked position by position.
function parity_dataframe()
    return DataFrame(
        "alpha" => [1.0, 2.0, 3.0, 4.0, 5.0, 6.0],
        "beta" => [6.0, 5.0, 4.0, 3.0, 2.0, 1.0],
        "gamma" => [0.5, 0.5, 0.5, 0.5, 0.5, 0.5],
    )
end

# Mixed signs: "charge" and "spill" are net-negative, so both backends must draw
# them first (they stack below the zero axis and would otherwise be hidden
# behind the positive bands).
function parity_signed_dataframe()
    return DataFrame(
        "thermal" => [5.0, 6.0, 7.0, 8.0, 9.0, 10.0],
        "charge" => [-1.0, -2.0, 0.0, -1.0, -0.5, -0.5],
        "wind" => [2.0, 2.0, 2.0, 2.0, 2.0, 2.0],
        "spill" => [0.0, -1.0, -1.0, 0.0, -2.0, -1.0],
    )
end

function parity_dataframe_with_time()
    df = parity_dataframe()
    DataFrames.insertcols!(df, 1, "DateTime" => parity_time())
    return df
end

# `plot_results` consumes a dict of DataFrames that each carry their own
# DateTime column.
function parity_results_dict()
    df = parity_dataframe_with_time()
    return Dict{String, DataFrames.DataFrame}(
        "Thermal" => df[!, ["DateTime", "alpha", "beta"]],
        "Wind" => df[!, ["DateTime", "gamma"]],
    )
end

# Two plots are "the same plot" when they draw the same series, in the same
# order, with the same colors and the same values. That is exactly the contract
# a deprecated shim owes its replacement.
function assert_same_plot(a, b)
    @test series_labels(a) == series_labels(b)
    @test series_colors(a) == series_colors(b)
    ya, yb = series_ydata(a), series_ydata(b)
    @test length(ya) == length(yb)
    for (va, vb) in zip(ya, yb)
        @test va ≈ vb
    end
end

# Call `f` asserting that it logs a deprecation warning, and return its value.
# `@test_logs` swallows the record, which also keeps the deprecation noise out
# of the suite's log-event tracker.
test_deprecated(f::Function) = @test_logs (:warn, r"deprecated") match_mode = :any f()

@testset "deprecated _plotly shims forward to the PlotlyLight backend" begin
    (results_uc, _) = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)
    gen_uc = get_generation_data(results_uc)
    df = parity_dataframe()
    df_dt = parity_dataframe_with_time()
    time = parity_time()
    results_dict = parity_results_dict()
    plotly = PlotlyLightBackend()
    fresh() = PG._empty_plot(plotly)

    # Every shim must produce exactly what the un-suffixed function with
    # `backend = PlotlyLightBackend()` produces, and must say it is deprecated.
    assert_same_plot(
        test_deprecated(() -> plot_dataframe_plotly(df_dt; set_display = false)),
        plot_dataframe(df_dt; backend = plotly, set_display = false),
    )
    assert_same_plot(
        test_deprecated(() -> plot_dataframe_plotly(df, time; set_display = false)),
        plot_dataframe(df, time; backend = plotly, set_display = false),
    )
    assert_same_plot(
        test_deprecated(
            () -> plot_dataframe_plotly!(fresh(), df_dt; set_display = false),
        ),
        plot_dataframe!(fresh(), df_dt; backend = plotly, set_display = false),
    )
    assert_same_plot(
        test_deprecated(
            () -> plot_dataframe_plotly!(fresh(), df, time; set_display = false),
        ),
        plot_dataframe!(fresh(), df, time; backend = plotly, set_display = false),
    )
    assert_same_plot(
        test_deprecated(() -> plot_results_plotly(results_dict; set_display = false)),
        plot_results(results_dict; backend = plotly, set_display = false),
    )
    assert_same_plot(
        test_deprecated(
            () -> plot_results_plotly!(fresh(), results_dict; set_display = false),
        ),
        plot_results!(fresh(), results_dict; backend = plotly, set_display = false),
    )
    assert_same_plot(
        test_deprecated(() -> plot_demand_plotly(results_uc; set_display = false)),
        plot_demand(results_uc; backend = plotly, set_display = false),
    )
    assert_same_plot(
        test_deprecated(
            () -> plot_demand_plotly!(fresh(), results_uc; set_display = false),
        ),
        plot_demand!(fresh(), results_uc; backend = plotly, set_display = false),
    )
    assert_same_plot(
        test_deprecated(() -> plot_fuel_plotly(results_uc; set_display = false)),
        plot_fuel(results_uc; backend = plotly, set_display = false),
    )
    assert_same_plot(
        test_deprecated(
            () -> plot_fuel_plotly!(fresh(), results_uc; set_display = false),
        ),
        plot_fuel!(fresh(), results_uc; backend = plotly, set_display = false),
    )
    # `plot_powerdata` is deprecated twice over, so both layers warn.
    assert_same_plot(
        test_deprecated(() -> PG.plot_powerdata_plotly(gen_uc; set_display = false)),
        test_deprecated(
            () -> PG.plot_powerdata(gen_uc; backend = plotly, set_display = false),
        ),
    )
    assert_same_plot(
        test_deprecated(
            () -> PG.plot_powerdata_plotly!(fresh(), gen_uc; set_display = false),
        ),
        test_deprecated(
            () -> PG.plot_powerdata!(
                fresh(),
                gen_uc;
                backend = plotly,
                set_display = false,
            ),
        ),
    )

    # A shim carries its backend in its name, so accepting a `backend` key word
    # too would leave the name and the key word free to disagree. Rejecting it
    # is the contract; silently overriding the caller would be worse.
    @test_throws ArgumentError plot_dataframe_plotly(df, time; backend = plotly)
    @test_throws ArgumentError plot_dataframe_plotly(df_dt; backend = plotly)
    @test_throws ArgumentError plot_dataframe_plotly!(fresh(), df_dt; backend = plotly)
    @test_throws ArgumentError plot_dataframe_plotly!(
        fresh(),
        df,
        time;
        backend = plotly,
    )
    @test_throws ArgumentError plot_results_plotly(results_dict; backend = plotly)
    @test_throws ArgumentError plot_results_plotly!(
        fresh(),
        results_dict;
        backend = plotly,
    )
    @test_throws ArgumentError plot_demand_plotly(results_uc; backend = plotly)
    @test_throws ArgumentError plot_demand_plotly!(fresh(), results_uc; backend = plotly)
    @test_throws ArgumentError plot_fuel_plotly(results_uc; backend = plotly)
    @test_throws ArgumentError plot_fuel_plotly!(fresh(), results_uc; backend = plotly)
    @test_throws ArgumentError PG.plot_powerdata_plotly(gen_uc; backend = plotly)
    @test_throws ArgumentError PG.plot_powerdata_plotly!(
        fresh(),
        gen_uc;
        backend = plotly,
    )
    # Passing a CairoMakie backend to a `_plotly` name must be rejected on the
    # same grounds, not quietly honored.
    @test_throws ArgumentError plot_dataframe_plotly(
        df,
        time;
        backend = CairoMakieBackend(),
    )
end

@testset "default save format follows the backend" begin
    df = parity_dataframe()
    time = parity_time()
    out_path = joinpath(TEST_OUTPUTS, "parity_save")
    isdir(out_path) && rm(out_path; recursive = true)
    mkpath(out_path)

    for (backend_pkg, backend) in PARITY_BACKENDS
        dir = joinpath(out_path, backend_pkg)
        mkpath(dir)
        # A shared "png" default would make every default-path PlotlyLight save
        # trip the "only supports HTML" warning and silently rewrite the path,
        # so the absence of any warning here is the point of the assertion.
        @test_logs min_level = Logging.Warn plot_dataframe(
            df,
            time;
            backend = backend,
            set_display = false,
            title = "defaulted",
            save = dir,
        )
        @test readdir(dir) == ["defaulted" * PARITY_EXTENSION[backend_pkg]]
    end

    # An explicit `format` still wins over the backend default.
    svg_dir = joinpath(out_path, "explicit_svg")
    mkpath(svg_dir)
    plot_dataframe(
        df,
        time;
        set_display = false,
        title = "explicit",
        save = svg_dir,
        format = "svg",
    )
    @test readdir(svg_dir) == ["explicit.svg"]

    # CairoMakie cannot write HTML at all, so it must say so rather than write a
    # PNG under an .html name.
    cm_plot = plot_dataframe(df, time; set_display = false)
    @test_throws ArgumentError save_plot(cm_plot, joinpath(out_path, "nope.html"))
    @test_throws ArgumentError plot_dataframe(
        df,
        time;
        set_display = false,
        title = "nope",
        save = out_path,
        format = "html",
    )

    # PlotlyLight can only write HTML, so a non-html extension is warned about
    # and rewritten rather than dropped.
    pl_plot =
        plot_dataframe(df, time; backend = PlotlyLightBackend(), set_display = false)
    rewritten = @test_logs (:warn, r"only supports HTML") match_mode = :any save_plot(
        pl_plot,
        joinpath(out_path, "rewritten.pdf"),
    )
    @test rewritten == joinpath(out_path, "rewritten.html")
    @test isfile(rewritten)
    @test !isfile(joinpath(out_path, "rewritten.pdf"))

    # One save per call, and one filename convention for every entry point.
    # `_resolve_save_file` is the only place that builds a save path; when the
    # wrappers built their own instead, `plot_demand` wrote the file twice (once
    # from the delegated `_plot_dataframe!` and once from its own tail) under two
    # different names, because only the wrapper replaced spaces with underscores.
    spaced_dir = joinpath(out_path, "spaced")
    mkpath(spaced_dir)
    plot_dataframe(df, time; set_display = false, title = "My Plot", save = spaced_dir)
    @test readdir(spaced_dir) == ["My_Plot.png"]

    results_dir = joinpath(out_path, "results_save")
    mkpath(results_dir)
    plot_results(
        parity_results_dict();
        set_display = false,
        title = "My Results",
        save = results_dir,
    )
    @test readdir(results_dir) == ["My_Results.png"]

    @info("removing test files")
    rm(out_path; recursive = true)
end

@testset "linewidth is honored by both backends" begin
    df = parity_dataframe()
    time = parity_time()
    # PlotlyLight used to drop `linewidth` on the floor (it only read the
    # PlotlyLight-specific spelling), so a caller got a hairline plot on one
    # backend and a thick one on the other from identical code.
    for (_, backend) in PARITY_BACKENDS
        p = plot_dataframe(
            df,
            time;
            backend = backend,
            set_display = false,
            linewidth = 7,
        )
        @test series_linewidths(p) == [7.0, 7.0, 7.0]
    end

    # The default is 1 on both, so a caller who passes nothing gets matching
    # plots too.
    for (_, backend) in PARITY_BACKENDS
        p = plot_dataframe(df, time; backend = backend, set_display = false)
        @test series_linewidths(p) == [1.0, 1.0, 1.0]
    end
end

@testset "series draw order is identical across backends" begin
    df = parity_signed_dataframe()
    time = parity_time()
    # Net-negative series first, each group keeping its column order.
    expected = ["charge", "spill", "thermal", "wind"]
    @test PG._series_draw_order(Matrix(df)) == [2, 4, 1, 3]

    # The plain (non-stacked, non-filled) branch is included on purpose:
    # CairoMakie used to reorder only in its stacked branches, so a plain line
    # plot came out in a different order than the same call on PlotlyLight.
    for mode in (
        (),
        (:stack => true,),
        (:stack => true, :nofill => true),
        (:stair => true,),
        (:stack => true, :stair => true),
    )
        for (backend_pkg, backend) in PARITY_BACKENDS
            p = plot_dataframe(
                df,
                time;
                backend = backend,
                set_display = false,
                mode...,
            )
            @test series_labels(p) == expected
        end
    end

    # Bar plots aggregate over time into one value per category and are drawn in
    # column order on both backends, so they must NOT be reordered.
    for (_, backend) in PARITY_BACKENDS
        p = plot_dataframe(
            df,
            time;
            backend = backend,
            set_display = false,
            bar = true,
            stack = true,
        )
        @test series_labels(p) == DataFrames.names(df)
    end
end

@testset "blank and omitted titles are treated as no title" begin
    df = parity_dataframe()
    time = parity_time()
    out_path = joinpath(TEST_OUTPUTS, "parity_title")
    isdir(out_path) && rm(out_path; recursive = true)
    mkpath(out_path)

    for (backend_pkg, backend) in PARITY_BACKENDS
        ext = PARITY_EXTENSION[backend_pkg]
        for (tag, title_kwargs) in (("omitted", ()), ("sentinel", (:title => " ",)))
            dir = joinpath(out_path, backend_pkg * "_" * tag)
            mkpath(dir)
            p = plot_dataframe(
                df,
                time;
                backend = backend,
                set_display = false,
                save = dir,
                title_kwargs...,
            )
            # `" "` is the old spelling of "this plot has no title"; neither it
            # nor an omitted title may reach the rendered figure.
            @test isnothing(plot_title(p))
            # An untitled plot still needs a deterministic file name.
            @test readdir(dir) == ["dataframe" * ext]
        end

        # A real title is kept, both on the figure and in the file name.
        dir = joinpath(out_path, backend_pkg * "_titled")
        mkpath(dir)
        p = plot_dataframe(
            df,
            time;
            backend = backend,
            set_display = false,
            save = dir,
            title = "Real Title",
        )
        @test plot_title(p) == "Real Title"
        # The title reaches the figure verbatim but the file name replaces
        # spaces with underscores, which is what every entry point has always
        # done. Centralizing the path in `_resolve_save_file` briefly dropped
        # that for `plot_dataframe` alone.
        @test readdir(dir) == ["Real_Title" * ext]
    end

    @info("removing test files")
    rm(out_path; recursive = true)
end

@testset "an empty dataframe warns and leaves the plot untouched" begin
    df = parity_dataframe()
    time = parity_time()
    for (_, backend) in PARITY_BACKENDS
        p = plot_dataframe(df, time; backend = backend, set_display = false)
        before_labels = series_labels(p)
        before_values = series_ydata(p)

        returned =
            @test_logs (:warn, r"Plot dataframe empty") match_mode = :any plot_dataframe!(
                p,
                DataFrames.DataFrame(),
                time;
                backend = backend,
                set_display = false,
            )
        # The same handle comes back, with nothing added and nothing redrawn.
        @test returned === p
        @test series_labels(p) == before_labels
        @test series_ydata(p) == before_values
    end
end

@testset "both backends select the same default palette colors" begin
    df = parity_dataframe()
    time = parity_time()
    # The representations differ by design (`Colors.RGBA` for CairoMakie,
    # `"rgba(…)"` strings for PlotlyLight), so the assertion is on the palette
    # *selection*: series `i` takes palette entry `i`, on both backends.
    expected = [_canonical_color(c.color) for c in PG.PALETTE[1:DataFrames.ncol(df)]]
    for (_, backend) in PARITY_BACKENDS
        p = plot_dataframe(df, time; backend = backend, set_display = false)
        @test series_colors(p) == expected
    end

    # More series than palette entries cycles back to the start rather than
    # falling off the end, identically on both backends.
    wide = DataFrames.DataFrame(
        ["c$ix" => fill(Float64(ix), length(time)) for
        ix in 1:(length(PG.PALETTE) + 2)],
    )
    wide_expected =
        [_canonical_color(c.color) for c in vcat(PG.PALETTE, PG.PALETTE[1:2])]
    for (_, backend) in PARITY_BACKENDS
        p = plot_dataframe(wide, time; backend = backend, set_display = false)
        @test series_colors(p) == wide_expected
    end
end
