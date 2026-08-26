# Behavioral tests for the fuel-stack and demand data contracts. `plot_fuel` is
# built on the PowerAnalytics metrics/selectors API, but reimplements the storage
# "In"/"Out" split, curtailment and the system-balance slacks by hand, so those
# categories need a numeric pin rather than a sign-only one. The old
# PowerAnalytics aggregation (`get_generation_data`/`categorize_data`, still
# exported and maintained) serves as the independent oracle: PowerGraphics no
# longer calls it, which is exactly what makes it a valid cross-check.
#
# Every value assertion runs against BOTH backends through the helpers in
# `plot_introspection.jl`. Writing them against `PlotlyLight.Plot.data` alone is
# what let PR #140's bar-plot defect be fixed in one backend and stay broken in
# the other; a backend-specific assertion below is marked with the reason it
# cannot be stated for both.

const FUEL_BACKENDS =
    (("cairomakie", CairoMakieBackend()), ("plotlylight", PlotlyLightBackend()))

# `run_test_sim` deserializes the shared simulation store, so it is read once for
# the whole file rather than per testset.
(fuel_results_uc, fuel_results_ed) = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)

# The old-API aggregation appears here only to derive the expected column order;
# its values are pinned by the equivalence testset below.
fuel_uc_old = categorize_data(
    get_generation_data(fuel_results_uc).data,
    make_fuel_dictionary(PSI.get_system(fuel_results_uc)),
)

# Column-order contract: palette categories first (in palette order), then the
# sorted remainder. Plots must present traces in exactly this order.
fuel_matched = intersect(PG.get_palette_category(PG.PALETTE), keys(fuel_uc_old))
fuel_expected_order =
    vcat(fuel_matched, sort(collect(setdiff(keys(fuel_uc_old), fuel_matched))))

@testset "fuel column-order contract" begin
    # The fixture must exercise the hand-written storage and curtailment
    # categories, or nothing below has teeth.
    @test issubset(["Storage In", "Storage Out", "Curtailment"], fuel_matched)
    @test names(PA.combine_categories(fuel_uc_old; names = fuel_expected_order)) ==
          fuel_expected_order
end

function test_fuel_stack(backend_pkg::String, backend::PG.PlottingBackend)
    @testset "pin $backend_pkg fuel stack behavior on simulation results" begin
        # Bar mode preserves trace order on both backends: PlotlyLight emits one
        # trace per category and CairoMakie one vector-labeled `barplot!` that
        # the introspection helper flattens back into per-category series.
        p_bar = plot_fuel(
            fuel_results_uc;
            backend = backend,
            set_display = false,
            bar = true,
            stack = true,
        )
        @test series_labels(p_bar) == vcat(fuel_expected_order, ["Load"])

        # Stacked-area fuel plot: same trace set (order-insensitive because both
        # backends draw net-negative series first).
        p_area =
            plot_fuel(fuel_results_uc; backend = backend, set_display = false,
                stack = true)
        @test sort(series_labels(p_area)) == sort(vcat(fuel_expected_order, ["Load"]))

        # Sign contract on PowerGraphics' own traces: storage charging renders
        # below the axis, discharging above it, and curtailment (forecast minus
        # dispatch) is non-negative up to solver tolerance.
        @test all(<=(1e-6), series_values(p_area, "Storage In"))
        @test all(>=(-1e-6), series_values(p_area, "Storage Out"))
        @test all(>=(-1e-4), series_values(p_area, "Curtailment"))

        # CairoMakie tracks its own series counter to rebuild the legend across
        # layered calls; cross-check it against the marks actually on the axis.
        @test series_count(p_area) == length(fuel_expected_order) + 1
    end

    @testset "$backend_pkg fuel net-load overlay includes storage charging" begin
        # With unit auto-scaling disabled all traces are in raw MW, so the "Load"
        # overlay must equal demand plus the magnitude of the (negative) storage
        # charging trace — the net-load line coincides with the top of the
        # generation stack.
        #
        # The overlay is drawn by a separate single-column `_plot_dataframe!`
        # call, so CairoMakie's stacked-line envelope for it is the raw demand
        # series and compares directly with the PlotlyLight trace.
        p = plot_fuel(
            fuel_results_uc;
            backend = backend,
            set_display = false,
            stack = true,
            auto_units = false,
        )
        load_y = series_values(p, "Load")
        in_y = series_values(p, "Storage In")
        demand = PA.combine_categories(get_load_data(fuel_results_uc).data)[!, "Load"]
        # The battery actually charges in the test solution, so this has teeth.
        @test sum(in_y) < 0
        @test load_y ≈ demand .- in_y
    end

    @testset "$backend_pkg fuel trace values match the old-API aggregation" begin
        # Numeric equivalence contract between the migrated metrics-API pipeline
        # and the old PowerAnalytics aggregation, over EVERY category the old API
        # emits. The categories PowerGraphics reimplements by hand — the
        # "<category> In"/"Out" storage split, "Curtailment" and the "Unserved
        # Energy"/"Over Generation" slacks — are the ones most likely to carry a
        # wrong sign, a doubled contribution or a dropped component, so they are
        # pinned by value and not merely by sign. UC solves with
        # `use_slacks = false` and ED with `use_slacks = true`, so the pair also
        # covers the slack categories.
        for result in (fuel_results_uc, fuel_results_ed)
            fuel_old = categorize_data(
                get_generation_data(result).data,
                make_fuel_dictionary(PSI.get_system(result)),
            )
            @test !isempty(fuel_old)

            # `auto_units = false` keeps every trace in raw MW, so no unit
            # scaling sits between the two pipelines.
            p = plot_fuel(
                result;
                backend = backend,
                set_display = false,
                stack = true,
                auto_units = false,
            )
            # "Load" is the net-load overlay, not a fuel category, so it is the
            # one trace legitimately absent from `fuel_old`. Every other trace
            # must have a counterpart, and no old-API category may be missing
            # from the plot: a one-sided category is a migration defect, not a
            # representational difference.
            traces = filter(kv -> first(kv) != "Load", series_map(p))
            @test Set(keys(traces)) == Set(keys(fuel_old))

            for k in sort(collect(intersect(keys(traces), keys(fuel_old))))
                expected = vec(sum(Matrix(no_datetime(fuel_old[k])); dims = 2))
                @test traces[k] ≈ expected
            end
        end
    end

    @testset "$backend_pkg fuel category toggles drop exactly their categories" begin
        # ED holds storage and solves with `use_slacks = true`, so every optional
        # category family is present by default and each kwarg has something to
        # drop.
        labels =
            kwargs -> sort(
                series_labels(
                    plot_fuel(
                        fuel_results_ed;
                        backend = backend,
                        set_display = false,
                        stack = true,
                        kwargs...,
                    ),
                ),
            )
        names_default = labels(())
        names_nocurtailment = labels((:curtailment => false,))
        names_noslacks = labels((:slacks => false,))
        names_nostorage = labels((:storage => false,))

        @test issubset(
            [
                "Storage In",
                "Storage Out",
                "Curtailment",
                "Unserved Energy",
                "Over Generation",
            ],
            names_default,
        )
        # `setdiff` preserves the (sorted) order of its first argument.
        @test setdiff(names_default, names_nocurtailment) == ["Curtailment"]
        @test setdiff(names_default, names_noslacks) ==
              ["Over Generation", "Unserved Energy"]
        @test setdiff(names_default, names_nostorage) == ["Storage In", "Storage Out"]
    end

    @testset "$backend_pkg unmatched components route to Other with an error log" begin
        incomplete_mapping =
            joinpath(TEST_DIR, "test_yamls", "generator_mapping_incomplete.yaml")

        p_inc =
            @test_logs (:error, r"No category in the generator mapping") match_mode = :any plot_fuel(
                fuel_results_uc;
                backend = backend,
                set_display = false,
                stack = true,
                auto_units = false,
                generator_mapping_file = incomplete_mapping,
            )
        @test "Other" in series_labels(p_inc)

        # The unmatched hydro generation lands intact in "Other": same total as
        # the "Hydropower" category under the default mapping.
        p_def = plot_fuel(
            fuel_results_uc;
            backend = backend,
            set_display = false,
            stack = true,
            auto_units = false,
        )
        @test sum(series_values(p_inc, "Other")) ≈
              sum(series_values(p_def, "Hydropower"))
    end

    @testset "pin $backend_pkg demand plot behavior on simulation results" begin
        load_uc = get_load_data(fuel_results_uc)
        expected = PA.combine_categories(load_uc.data)

        # The results-path demand frame is a single non-negative "Load" column.
        @test names(expected) == ["Load"]
        @test all(>=(-1e-6), expected[!, "Load"])
        @test length(load_uc.time) == nrow(expected)

        p = plot_demand(fuel_results_uc; backend = backend, set_display = false)
        @test series_labels(p) == ["Load"]
        @test series_values(p, "Load") ≈ expected[!, "Load"]

        # The time-window kwargs must keep slicing through the migration.
        p_h = plot_demand(
            fuel_results_uc;
            backend = backend,
            set_display = false,
            horizon = 3,
        )
        @test series_values(p_h, "Load") ≈ expected[1:3, "Load"]

        # Index 25 is the start of the second simulation step, a timestamp that
        # is valid under both the old and the new results readers.
        t0 = load_uc.time[25]
        p_it = plot_demand(
            fuel_results_uc;
            backend = backend,
            set_display = false,
            initial_time = t0,
            horizon = 2,
        )
        @test series_values(p_it, "Load") ≈ expected[25:26, "Load"]

        # A `Dates.Period` horizon means the same thing as the equivalent integer
        # count of time periods. The `PSY.System` path has always accepted one
        # (PowerAnalytics converts it); the results path used to raise a
        # MethodError deep in the stack.
        resolution = load_uc.time[2] - load_uc.time[1]
        @test resolution == Hour(1)  # the fixture the horizons below assume
        p_p = plot_demand(
            fuel_results_uc;
            backend = backend,
            set_display = false,
            horizon = Hour(3),
        )
        @test series_values(p_p, "Load") ≈ series_values(p_h, "Load")

        p_pit = plot_demand(
            fuel_results_uc;
            backend = backend,
            set_display = false,
            initial_time = t0,
            horizon = Hour(2),
        )
        @test series_values(p_pit, "Load") ≈ expected[25:26, "Load"]

        # A horizon that is not a whole multiple of the resolution is rejected up
        # front, not as an InexactError from the underlying division.
        @test_throws ArgumentError plot_demand(
            fuel_results_uc;
            backend = backend,
            set_display = false,
            horizon = Minute(90),
        )

        # A `Dates.Period` horizon needs two timestamps to infer the resolution;
        # an integer horizon does not.
        @test_throws ArgumentError PG._time_window_indices(
            load_uc.time[1:1],
            Dict(:horizon => Hour(1)),
        )
        @test PG._time_window_indices(load_uc.time[1:1], Dict(:horizon => 1)) == 1:1

        # filter_func restricts which loads are included.
        only_bus2 = x -> get_name(get_bus(x)) == "bus2"
        expected_f = PA.combine_categories(
            get_load_data(fuel_results_uc; filter_func = only_bus2).data,
        )
        p_f = plot_demand(
            fuel_results_uc;
            backend = backend,
            set_display = false,
            filter_func = only_bus2,
        )
        @test series_values(p_f, "Load") ≈ expected_f[!, "Load"]
        @test sum(expected_f[!, "Load"]) < sum(expected[!, "Load"])
    end

    @testset "$backend_pkg fuel plot slices the requested time window" begin
        # `_fuel_data` applies the same `_time_window_indices` slicing as the
        # demand path, but nothing exercised it through `plot_fuel`, so a
        # regression in the fuel window would only have surfaced on demand plots.
        palette_categories = PG.get_palette_category(PG.PALETTE)
        (_, fuel_time) = PG._fuel_data(fuel_results_uc, palette_categories)
        # Index 25 starts the second simulation step, as in the demand testset.
        t0 = fuel_time[25]
        window = 25:28

        (_, windowed_time) = PG._fuel_data(
            fuel_results_uc,
            palette_categories;
            initial_time = t0,
            horizon = length(window),
        )
        @test length(fuel_time) > length(window)
        @test windowed_time == fuel_time[window]

        p_full = plot_fuel(
            fuel_results_uc;
            backend = backend,
            set_display = false,
            stack = true,
            auto_units = false,
        )
        p_win = plot_fuel(
            fuel_results_uc;
            backend = backend,
            set_display = false,
            stack = true,
            auto_units = false,
            initial_time = t0,
            horizon = length(window),
        )

        # Empty categories are dropped before windowing, so the trace set is
        # unchanged; only the number of points may differ.
        @test sort(series_labels(p_win)) == sort(series_labels(p_full))
        @test all(s -> length(s.values) == length(window), plot_series(p_win))
        @test any(s -> length(s.values) > length(window), plot_series(p_full))

        # The net-load overlay is windowed with the stack rather than left at
        # full length, and holds the values the full plot draws over the window.
        @test series_values(p_win, "Load") ≈ series_values(p_full, "Load")[window]
    end
end

for (backend_pkg, backend) in FUEL_BACKENDS
    test_fuel_stack(backend_pkg, backend)
end

@testset "fuel stack is identical across backends" begin
    # The per-backend testsets above pin each backend against the same oracle;
    # this compares the two backends directly, so a defect that shifts BOTH in
    # the same direction is still caught by the oracle while a one-sided
    # regression is caught here with a much smaller diff to read.
    plots = Dict(
        pkg => plot_fuel(
            fuel_results_uc;
            backend = backend,
            set_display = false,
            stack = true,
            auto_units = false,
        ) for (pkg, backend) in FUEL_BACKENDS
    )
    cm = plots["cairomakie"]
    pl = plots["plotlylight"]

    @test series_labels(cm) == series_labels(pl)
    @test series_colors(cm) == series_colors(pl)
    for (a, b) in zip(series_ydata(cm), series_ydata(pl))
        @test a ≈ b
    end
end

@testset "plot_demand and plot_fuel save exactly one file" begin
    # `_plot_demand!` used to read `:save` without removing it from the key words
    # it forwarded, so the delegated `_plot_dataframe!` saved the figure and the
    # wrapper then saved it again under a space-sanitized name: one call, two
    # files. `_plot_results!` and `_plot_fuel!` stripped `:save` and did not.
    # Every wrapper now resolves its path once through `_resolve_save_file`.
    save_root = joinpath(TEST_OUTPUTS, "fuel_save")
    isdir(save_root) && rm(save_root; recursive = true)
    mkpath(save_root)

    demand_dir = joinpath(save_root, "demand")
    mkpath(demand_dir)
    plot_demand(
        fuel_results_uc;
        set_display = false,
        title = "My Demand",
        save = demand_dir,
    )
    @test readdir(demand_dir) == ["My_Demand.png"]

    fuel_dir = joinpath(save_root, "fuel")
    mkpath(fuel_dir)
    plot_fuel(fuel_results_uc; set_display = false, title = "My Fuel", save = fuel_dir)
    @test readdir(fuel_dir) == ["My_Fuel.png"]

    @info("removing test files")
    rm(save_root; recursive = true)
end
