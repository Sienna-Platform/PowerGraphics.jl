# Pinning tests for the fuel-stack and demand data contracts. These assert the
# CURRENT behavior of the PowerAnalytics pipeline that `plot_fuel` and
# `plot_demand` are built on, so the migration to the PowerAnalytics metrics
# API can prove it preserves category naming, column ordering, and sign
# conventions. Expected values are derived from the old PA API, which remains
# exported and maintained, so these tests stay valid as a cross-check after
# PowerGraphics' internals migrate.

@testset "pin categorize_data category naming and signs" begin
    timestamps =
        collect(range(DateTime("2024-01-01T00:00:00"); step = Hour(1), length = 4))
    data = Dict{Symbol, DataFrame}(
        :ActivePowerVariable__ThermalStandard =>
            DataFrame("DateTime" => timestamps, "gen1" => [1.0, 2.0, 3.0, 4.0]),
        :ActivePowerVariable__RenewableDispatch =>
            DataFrame("DateTime" => timestamps, "wind1" => [0.4, 0.3, 0.2, 0.1]),
        :ActivePowerVariable__RenewableDispatch__Curtailment =>
            DataFrame("DateTime" => timestamps, "wind1" => [0.1, 0.2, 0.0, 0.0]),
        :ActivePowerInVariable__EnergyReservoirStorage =>
            DataFrame("DateTime" => timestamps, "batt" => [0.5, 0.0, 1.0, 0.25]),
        :ActivePowerOutVariable__EnergyReservoirStorage =>
            DataFrame("DateTime" => timestamps, "batt" => [0.0, 0.75, 0.0, 0.5]),
        :SystemBalanceSlackUp__System =>
            DataFrame("DateTime" => timestamps, "System" => [0.0, 0.0, 0.1, 0.0]),
        :SystemBalanceSlackDown__System =>
            DataFrame("DateTime" => timestamps, "System" => [0.2, 0.0, 0.0, 0.0]),
    )
    aggregation = Dict(
        "Thermal" => [("ThermalStandard", "gen1")],
        "Wind" => [("RenewableDispatch", "wind1")],
        "Storage" => [("EnergyReservoirStorage", "batt")],
    )

    fuel = categorize_data(data, aggregation; curtailment = true, slacks = true)

    # Categories holding components with ActivePowerIn/Out variables split into
    # "<category> In"/"<category> Out"; slack variables map to their fixed
    # display names; all curtailment keys collapse into one "Curtailment".
    @test Set(keys(fuel)) == Set([
        "Thermal",
        "Wind",
        "Storage In",
        "Storage Out",
        "Curtailment",
        "Unserved Energy",
        "Over Generation",
    ])
    # Charging is sign-flipped so it stacks below zero; discharging is unchanged.
    @test fuel["Storage In"].batt == [-0.5, 0.0, -1.0, -0.25]
    @test fuel["Storage Out"].batt == [0.0, 0.75, 0.0, 0.5]
    @test fuel["Curtailment"].wind1 == [0.1, 0.2, 0.0, 0.0]
    @test fuel["Unserved Energy"].System == [0.0, 0.0, 0.1, 0.0]
    @test fuel["Over Generation"].System == [0.2, 0.0, 0.0, 0.0]

    # Disabling curtailment/slacks drops exactly those categories.
    fuel_min = categorize_data(data, aggregation; curtailment = false, slacks = false)
    @test Set(keys(fuel_min)) == Set(["Thermal", "Wind", "Storage In", "Storage Out"])
end

@testset "pin fuel stack behavior on simulation results" begin
    (results_uc, results_ed) = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)

    gen_uc = get_generation_data(results_uc)
    fuel_uc = categorize_data(
        gen_uc.data,
        make_fuel_dictionary(PSI.get_system(results_uc)),
    )

    @test haskey(fuel_uc, "Storage In")
    @test haskey(fuel_uc, "Storage Out")
    @test haskey(fuel_uc, "Curtailment")
    # Charging columns are non-positive, discharging non-negative, and
    # curtailment (forecast minus dispatch) non-negative up to solver tolerance.
    @test all(<=(1e-6), Matrix(no_datetime(fuel_uc["Storage In"])))
    @test all(>=(-1e-6), Matrix(no_datetime(fuel_uc["Storage Out"])))
    @test all(>=(-1e-4), Matrix(no_datetime(fuel_uc["Curtailment"])))

    # The ED template runs with `use_slacks = true`, so the slack categories
    # must appear under their fixed display names.
    gen_ed = get_generation_data(results_ed)
    fuel_ed = categorize_data(
        gen_ed.data,
        make_fuel_dictionary(PSI.get_system(results_ed)),
    )
    @test haskey(fuel_ed, "Unserved Energy")
    @test haskey(fuel_ed, "Over Generation")

    # Column-order contract: palette categories first (in palette order), then
    # the sorted remainder. Plots must present traces in exactly this order.
    palette_categories = PG.get_palette_category(PG.PALETTE)
    matched = intersect(palette_categories, keys(fuel_uc))
    unmatched = sort(collect(setdiff(keys(fuel_uc), palette_categories)))
    expected_order = vcat(matched, unmatched)
    @test issubset(["Storage In", "Storage Out", "Curtailment"], matched)
    fuel_agg = PA.combine_categories(fuel_uc; names = expected_order)
    @test names(fuel_agg) == expected_order

    # Plot-level pin (PlotlyLight bar mode preserves trace order): fuel
    # categories in contract order, then the net-load overlay named "Load".
    p_bar = plot_fuel_plotly(results_uc; set_display = false, bar = true, stack = true)
    @test [t.name for t in p_bar.data] == vcat(expected_order, ["Load"])

    # Stacked-area fuel plot: same trace set (order-insensitive because the
    # backend draws negative series first); the storage-charging trace must be
    # non-positive so it renders below the axis.
    p_area = plot_fuel_plotly(results_uc; set_display = false, stack = true)
    @test sort([t.name for t in p_area.data]) == sort(vcat(expected_order, ["Load"]))
    in_trace = only([t for t in p_area.data if t.name == "Storage In"])
    @test all(<=(1e-6), collect(in_trace.y))

    # Backends must agree on the number of series.
    p_cm = plot_fuel(results_uc; set_display = false, stack = true)
    @test p_cm.series_count == length(p_area.data)
end

@testset "fuel net-load overlay includes storage charging" begin
    (results_uc, _) = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)

    # With unit auto-scaling disabled all traces are in raw MW, so the "Load"
    # overlay must equal demand plus the magnitude of the (negative) storage
    # charging trace — the net-load line coincides with the top of the
    # generation stack.
    p = plot_fuel_plotly(
        results_uc;
        set_display = false,
        stack = true,
        auto_units = false,
    )
    load_y = collect(only([t for t in p.data if t.name == "Load"]).y)
    in_y = collect(only([t for t in p.data if t.name == "Storage In"]).y)
    demand = PA.combine_categories(get_load_data(results_uc).data)[!, "Load"]
    # The battery actually charges in the test solution, so this has teeth.
    @test sum(in_y) < 0
    @test load_y ≈ demand .- in_y
end

@testset "fuel trace values match the old-API aggregation" begin
    (results_uc, _) = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)

    # Numeric equivalence contract between the migrated metrics-API pipeline
    # and the old (still exported) PowerAnalytics aggregation: every plain
    # generator category trace must equal the summed old-API category values.
    fuel_old = categorize_data(
        get_generation_data(results_uc).data,
        make_fuel_dictionary(PSI.get_system(results_uc)),
    )
    categories = [
        k for k in keys(fuel_old) if
        !endswith(k, " In") &&
        !endswith(k, " Out") &&
        k ∉ ("Curtailment", "Unserved Energy", "Over Generation")
    ]
    @test !isempty(categories)

    p = plot_fuel_plotly(
        results_uc;
        set_display = false,
        stack = true,
        auto_units = false,
    )
    for k in categories
        expected = vec(sum(Matrix(no_datetime(fuel_old[k])); dims = 2))
        trace = only([t for t in p.data if t.name == k])
        @test collect(trace.y) ≈ expected
    end
end

@testset "unmatched components route to Other with an error log" begin
    (results_uc, _) = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)
    incomplete_mapping =
        joinpath(TEST_DIR, "test_yamls", "generator_mapping_incomplete.yaml")

    p_inc =
        @test_logs (:error, r"No category in the generator mapping") match_mode = :any plot_fuel_plotly(
            results_uc;
            set_display = false,
            stack = true,
            auto_units = false,
            generator_mapping_file = incomplete_mapping,
        )
    trace_names = [t.name for t in p_inc.data]
    @test "Other" in trace_names

    # The unmatched hydro generation lands intact in "Other": same total as
    # the "Hydropower" category under the default mapping.
    p_def = plot_fuel_plotly(
        results_uc;
        set_display = false,
        stack = true,
        auto_units = false,
    )
    hydro = only([t for t in p_def.data if t.name == "Hydropower"])
    other = only([t for t in p_inc.data if t.name == "Other"])
    @test sum(other.y) ≈ sum(hydro.y)
end

@testset "pin demand plot behavior on simulation results" begin
    (results_uc, _) = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)
    load_uc = get_load_data(results_uc)
    expected = PA.combine_categories(load_uc.data)

    # The results-path demand frame is a single non-negative "Load" column.
    @test names(expected) == ["Load"]
    @test all(>=(-1e-6), expected[!, "Load"])
    @test length(load_uc.time) == nrow(expected)

    p = plot_demand_plotly(results_uc; set_display = false)
    @test length(p.data) == 1
    @test p.data[1].name == "Load"
    @test collect(p.data[1].y) ≈ expected[!, "Load"]

    p_cm = plot_demand(results_uc; set_display = false)
    @test p_cm.series_count == 1

    # Legacy time-window kwargs must keep working through the migration.
    p_h = plot_demand_plotly(results_uc; set_display = false, horizon = 3)
    @test collect(p_h.data[1].y) ≈ expected[1:3, "Load"]

    # Index 25 is the start of the second simulation step, a timestamp that is
    # valid under both the old and the new results readers.
    t0 = load_uc.time[25]
    p_it = plot_demand_plotly(
        results_uc;
        set_display = false,
        initial_time = t0,
        horizon = 2,
    )
    @test collect(p_it.data[1].y) ≈ expected[25:26, "Load"]

    # The start_time/len spellings behave identically to initial_time/horizon.
    p_sl = plot_demand_plotly(
        results_uc;
        set_display = false,
        start_time = t0,
        len = 2,
    )
    @test collect(p_sl.data[1].y) ≈ expected[25:26, "Load"]

    # filter_func restricts which loads are included.
    only_bus2 = x -> get_name(get_bus(x)) == "bus2"
    expected_f =
        PA.combine_categories(get_load_data(results_uc; filter_func = only_bus2).data)
    p_f = plot_demand_plotly(results_uc; set_display = false, filter_func = only_bus2)
    @test collect(p_f.data[1].y) ≈ expected_f[!, "Load"]
    @test sum(expected_f[!, "Load"]) < sum(expected[!, "Load"])
end
