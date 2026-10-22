# Fuel-stack and demand values on both backends, checked against PowerAnalytics'
# `get_generation_data`/`categorize_data` aggregation.

# `run_test_sim` deserializes the shared simulation store, so it is read once for
# the whole file rather than per testset.
(fuel_results_uc, fuel_results_ed) = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)

fuel_uc_old = categorize_data(
    get_generation_data(fuel_results_uc).data,
    make_fuel_dictionary(PSI.get_system(fuel_results_uc)),
)

# Expected column order: palette categories first, then the sorted remainder.
fuel_matched = intersect(PG.get_palette_category(PG.PALETTE), keys(fuel_uc_old))
fuel_expected_order =
    vcat(fuel_matched, sort(collect(setdiff(keys(fuel_uc_old), fuel_matched))))

@testset "fuel column-order contract" begin
    # The fixture includes storage and curtailment.
    @test issubset(["Storage In", "Storage Out", "Curtailment"], fuel_matched)
    @test names(PA.combine_categories(fuel_uc_old; names = fuel_expected_order)) ==
          fuel_expected_order
end

function test_fuel_stack(backend_pkg::String, backend::PG.PlottingBackend)
    @testset "$backend_pkg fuel stack on simulation results" begin
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

        # Storage charging is below zero, discharging and curtailment above.
        @test all(<=(1e-6), series_values(p_area, "Storage In"))
        @test all(>=(-1e-6), series_values(p_area, "Storage Out"))
        @test all(>=(-1e-4), series_values(p_area, "Curtailment"))

        @test series_count(p_area) == length(fuel_expected_order) + 1
    end

    @testset "$backend_pkg fuel trace values match categorize_data" begin
        # UC has no slacks and ED has slacks, so both cases are covered.
        for result in (fuel_results_uc, fuel_results_ed)
            fuel_old = categorize_data(
                get_generation_data(result).data,
                make_fuel_dictionary(PSI.get_system(result)),
            )
            @test !isempty(fuel_old)

            # Raw MW, no unit scaling.
            p = plot_fuel(
                result;
                backend = backend,
                set_display = false,
                stack = true,
                auto_units = false,
            )
            # Every category except the "Load" line matches one-to-one.
            traces = filter(kv -> first(kv) != "Load", series_map(p))
            @test Set(keys(traces)) == Set(keys(fuel_old))

            for k in sort(collect(intersect(keys(traces), keys(fuel_old))))
                expected = vec(sum(Matrix(no_datetime(fuel_old[k])); dims = 2))
                @test traces[k] ≈ expected
            end
        end
    end

    @testset "$backend_pkg fuel category toggles drop exactly their categories" begin
        # ED has storage and slacks, so every toggle has something to drop.
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

    @testset "$backend_pkg demand plot on simulation results" begin
        load_uc = get_load_data(fuel_results_uc)
        expected = PA.combine_categories(load_uc.data)

        # The results-path demand frame is a single non-negative "Load" column.
        @test names(expected) == ["Load"]
        @test all(>=(-1e-6), expected[!, "Load"])
        @test length(load_uc.time) == nrow(expected)

        p = plot_demand(fuel_results_uc; backend = backend, set_display = false)
        @test series_labels(p) == ["Load"]
        @test series_values(p, "Load") ≈ expected[!, "Load"]

        # Time-window kwargs slice the trace.
        p_h = plot_demand(
            fuel_results_uc;
            backend = backend,
            set_display = false,
            horizon = 3,
        )
        @test series_values(p_h, "Load") ≈ expected[1:3, "Load"]

        # Index 25 starts the second simulation step.
        t0 = load_uc.time[25]
        p_it = plot_demand(
            fuel_results_uc;
            backend = backend,
            set_display = false,
            initial_time = t0,
            horizon = 2,
        )
        @test series_values(p_it, "Load") ≈ expected[25:26, "Load"]

        # A `Dates.Period` horizon equals the equivalent integer count.
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

        # A horizon that is not a whole multiple of the resolution is rejected.
        @test_throws ArgumentError plot_demand(
            fuel_results_uc;
            backend = backend,
            set_display = false,
            horizon = Minute(90),
        )

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
        @test all(s -> length(s.values) == length(window), get_plot_series(p_win))
        @test any(s -> length(s.values) > length(window), get_plot_series(p_full))

        # The load line is windowed with the stack rather than left at full
        # length, and holds the values the full plot draws over the window.
        @test series_values(p_win, "Load") ≈ series_values(p_full, "Load")[window]
    end
end

for (backend_pkg, backend) in TEST_BACKENDS
    test_fuel_stack(backend_pkg, backend)
end

@testset "fuel stack is identical across backends" begin
    plots = Dict(
        pkg => plot_fuel(
            fuel_results_uc;
            backend = backend,
            set_display = false,
            stack = true,
            auto_units = false,
        ) for (pkg, backend) in TEST_BACKENDS
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

    # The `" "` title saves under the untitled name.
    untitled_dir = joinpath(save_root, "untitled")
    mkpath(untitled_dir)
    plot_fuel(fuel_results_uc; set_display = false, title = " ", save = untitled_dir)
    @test readdir(untitled_dir) == ["dataframe.png"]

    # `plot_results` saves under its title, or the untitled name without one.
    results = Dict(
        "Load" => DataFrames.DataFrame(
            "DateTime" => DateTime(2024, 1, 1):Hour(1):DateTime(2024, 1, 1, 3),
            "x" => [1.0, 2.0, 3.0, 4.0],
        ),
    )
    results_dir = joinpath(save_root, "results")
    mkpath(results_dir)
    plot_results(results; set_display = false, title = "My Results", save = results_dir)
    plot_results(results; set_display = false, save = results_dir)
    @test sort(readdir(results_dir)) == ["My_Results.png", "dataframe.png"]
    @test get_plot_title(
        plot_results(results; backend = PlotlyLightBackend(), set_display = false,
            title = "My Results"),
    ) == "My Results"

    @info("removing test files")
    rm(save_root; recursive = true)
end
