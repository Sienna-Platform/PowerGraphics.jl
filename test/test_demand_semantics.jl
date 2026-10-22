# Demand on `IS.Results` with controllable (`PowerLoadInterruption`) loads, where
# the served load differs from the forecast and the forecast parameter has the
# opposite sign to `StaticPowerLoad`.

# `n_interruptible` of the three 5-bus loads are rebuilt as
# `InterruptiblePowerLoad`; `capacity_scale` throttles thermal capacity so that
# the solver actually sheds load and served ≠ forecast.
function build_interruptible_load_system(; n_interruptible::Int, capacity_scale::Float64)
    sys = deepcopy(PSB.build_system(PSB.PSITestSystems, "c_sys5_uc"))
    for old in collect(get_components(PowerLoad, sys))[1:n_interruptible]
        new = InterruptiblePowerLoad(;
            name = get_name(old),
            available = true,
            bus = get_bus(old),
            active_power = get_active_power(old),
            reactive_power = get_reactive_power(old),
            max_active_power = get_max_active_power(old),
            max_reactive_power = get_max_reactive_power(old),
            base_power = get_base_power(old),
            operation_cost = LoadCost(;
                variable = CostCurve(LinearCurve(1000.0)),
                fixed = 0.0,
            ),
        )
        add_component!(sys, new)
        copy_time_series!(new, old)
        remove_component!(sys, old)
    end
    for g in get_components(ThermalStandard, sys)
        lims = get_active_power_limits(g)
        set_active_power_limits!(g, (min = 0.0, max = lims.max * capacity_scale))
        set_rating!(g, get_rating(g) * capacity_scale)
    end
    return sys
end

function solve_interruptible_load_problem(sys)
    template = ProblemTemplate(NetworkModel(CopperPlatePowerModel; use_slacks = false))
    set_device_model!(template, ThermalStandard, ThermalBasicUnitCommitment)
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, RenewableNonDispatch, FixedOutput)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, InterruptiblePowerLoad, PowerLoadInterruption)
    prob = DecisionModel(
        template,
        sys;
        optimizer = optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01),
        horizon = Hour(12),
    )
    build!(prob; output_dir = mktempdir())
    solve!(prob)
    return OptimizationProblemResults(prob)
end

# Reference total demand per timestep from `PA.get_load_data`, skipping empty
# categories.
function old_api_demand(res; filter_func = nothing)
    data = if isnothing(filter_func)
        get_load_data(res)
    else
        get_load_data(res; filter_func = filter_func)
    end
    total = Float64[]
    for (_, df) in data.data
        cols = no_datetime(df)
        ncol(cols) == 0 && continue
        vals = vec(sum(Matrix(cols); dims = 2))
        if isempty(total)
            total = vals
        else
            total .+= vals
        end
    end
    return total
end

demand_trace(p) = series_values(p, "Load")

# The `PSY.System` path aggregates per load rather than into a single "Load"
# column, so its window has to be read off the summed traces.
total_trace(p) = sum(series_ydata(p))

# Float-noise slack on comparisons of MW totals: 1e-6 MW is 1 W, i.e. 1e-8 per
# unit on the 100 MVA system base, far below anything the solver resolves.
const DEMAND_MW_TOL = 1.0e-6

@testset "demand on a mixed static + controllable load system" begin
    res = solve_interruptible_load_problem(
        build_interruptible_load_system(; n_interruptible = 2, capacity_scale = 0.55),
    )
    p = plot_demand(res; backend = PG.PlotlyLightBackend(), set_display = false)
    plotted = demand_trace(p)

    # Demand is non-negative.
    @test all(>=(0.0), plotted)

    # Matches `get_load_data` per timestep.
    @test plotted ≈ old_api_demand(res)

    # The solver sheds load in at least one period.
    forecast =
        -get_data_vec(
            PA.compute(
                PA.Metrics.calc_load_forecast,
                res,
                make_selector(InterruptiblePowerLoad; groupby = :all),
            ),
        )
    served = get_data_vec(
        PA.compute(
            PA.Metrics.calc_active_power,
            res,
            make_selector(InterruptiblePowerLoad; groupby = :all),
        ),
    )
    @test all(served .<= forecast .+ DEMAND_MW_TOL)
    @test any(served .< forecast .- DEMAND_MW_TOL)

    # A whole-pool read throws because static loads have no `ActivePowerVariable`.
    @test_throws Exception PA.compute(
        PA.Metrics.calc_active_power,
        res,
        rebuild_selector(PA.Selectors.all_loads; groupby = :all),
    )

    # `filter_func` restricts the pool.
    only_bus2 = x -> get_name(x) == "Bus2"
    p_f = plot_demand(
        res;
        backend = PG.PlotlyLightBackend(),
        set_display = false,
        filter_func = only_bus2,
    )
    @test demand_trace(p_f) ≈ old_api_demand(res; filter_func = only_bus2)
    @test sum(demand_trace(p_f)) < sum(plotted)
end

@testset "fuel plot demand line tracks served load when load is shed" begin
    res = solve_interruptible_load_problem(
        build_interruptible_load_system(; n_interruptible = 3, capacity_scale = 0.55),
    )
    p = plot_fuel(
        res;
        backend = PG.PlotlyLightBackend(),
        set_display = false,
        auto_units = false,
    )
    netload = demand_trace(p)
    @test all(>=(0.0), netload)

    # With a copper-plate network, no slacks and no storage, generation equals
    # served load, so the demand line sits on top of the generation stack.
    generation = zeros(Float64, length(netload))
    for s in get_plot_series(p)
        s.label in ("Load", "Curtailment") && continue
        generation .+= s.values
    end
    @test generation ≈ netload
end

@testset "plot_demand accepts a Dates.Period horizon on the PSY.System path" begin
    sys = deepcopy(PSB.build_system(PSB.PSITestSystems, "c_sys5_uc"))
    initial_times = collect(get_forecast_initial_times(sys))
    t0 = initial_times[2]
    # The `Hour(3)` and `3` horizons below only mean the same thing on an hourly
    # axis, so pin the fixture's resolution rather than assume it.
    axis = last(PG._demand_data(sys))
    @test axis[2] - axis[1] == Hour(1)

    windowed = total_trace(
        plot_demand(
            sys;
            backend = PG.PlotlyLightBackend(),
            set_display = false,
            initial_time = t0,
            horizon = 3,
        ),
    )
    @test length(windowed) == 3
    @test length(
        total_trace(
            plot_demand(sys; backend = PG.PlotlyLightBackend(),
                set_display = false),
        ),
    ) > 3

    # A `Dates.Period` horizon selects the same rows as the integer count.
    @test windowed ≈ total_trace(
        plot_demand(
            sys;
            backend = PG.PlotlyLightBackend(),
            set_display = false,
            initial_time = t0,
            horizon = Hour(3),
        ),
    )
end

@testset "demand data window key words slice on the PSY.System path" begin
    sys = deepcopy(PSB.build_system(PSB.PSITestSystems, "c_sys5_uc"))
    t0 = collect(get_forecast_initial_times(sys))[2]

    (full, _) = PG._demand_data(sys)
    (windowed, windowed_time) = PG._demand_data(sys; initial_time = t0, horizon = 3)
    @test DataFrames.nrow(windowed) == 3
    @test length(windowed_time) == 3
    @test DataFrames.nrow(full) > 3

    # The `System` path groups columns, so `aggregate` has to reach the reader.
    @test names(first(PG._demand_data(sys; aggregate = "System"))) !=
          names(first(PG._demand_data(sys; aggregate = "Bus")))
end

# The fuel plot demand line is end-use load only, without storage charging.
(storage_results_uc, _) = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)

@testset "$backend_pkg fuel plot demand line is end-use load only" for (
    backend_pkg,
    backend,
) in TEST_BACKENDS
    p = plot_fuel(
        storage_results_uc;
        backend = backend,
        set_display = false,
        stack = true,
        auto_units = false,
    )
    # The battery charges in the test solution.
    @test sum(series_values(p, "Storage In")) < 0
    end_use = series_values(
        plot_demand(storage_results_uc; backend = backend, set_display = false),
        "Load",
    )
    @test series_values(p, "Load") ≈ end_use
    @test end_use ≈ old_api_demand(storage_results_uc)
end
