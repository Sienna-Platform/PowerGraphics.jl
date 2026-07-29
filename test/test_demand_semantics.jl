# Regression tests for the demand data contract on `IS.Results`.
#
# PowerGraphics reads load variable-first (`calc_active_power`, falling back to
# `calc_load_forecast`), which is what the old `PA.get_load_data` did. The
# fixtures below exist because that order is only observable when a load is
# modeled with a controllable formulation: under `PowerLoadInterruption` the
# `ActivePowerVariable` is the *served* load, while PowerSimulations stores the
# `ActivePowerTimeSeriesParameter` with the opposite sign than it does under
# `StaticPowerLoad`. Reading the forecast alone therefore plots the wrong
# quantity and the wrong sign, and on a mixed static/controllable system the two
# sign conventions cancel — which is what these tests pin down. The rest of the
# suite runs on an all-static fixture where both readings coincide.

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

# Total demand per timestep the way the old PowerAnalytics pipeline reported it.
# Categories emptied out by a `filter_func` are skipped: upstream
# `PA.combine_categories` throws a `MethodError` on those.
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

# Read through the backend-agnostic harness in `plot_introspection.jl` rather
# than off `PlotlyLight.Plot.data`: a value assertion written against one
# backend's object model is exactly what lets a regression survive in the other.
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

    # Sign contract. Reading `calc_load_forecast` alone returns the static loads
    # positive and the controllable loads negative, so the aggregate came out
    # negative before the variable-first fallback existed.
    @test all(>=(0.0), plotted)

    # Magnitude contract against the old pipeline, per timestep.
    @test plotted ≈ old_api_demand(res)

    # The fixture has teeth only if the solver actually shed load, i.e. served
    # demand is strictly below the forecast for at least one period.
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

    # A whole-pool `calc_active_power` read cannot express this: the static
    # loads have no `ActivePowerVariable`, so the call throws and everything
    # falls back to the forecast. This is why resolution is per load type.
    @test_throws Exception PA.compute(
        PA.Metrics.calc_active_power,
        res,
        rebuild_selector(PA.Selectors.all_loads; groupby = :all),
    )

    # `filter_func` still restricts the pool, and still matches the old reader.
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

@testset "net-load overlay tracks served load when load is shed" begin
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
    # served load every period, so the net-load line must sit exactly on top of
    # the generation stack. Curtailment is drawn above the line, not in it.
    generation = zeros(Float64, length(netload))
    for s in plot_series(p)
        s.label in ("Load", "Curtailment") && continue
        generation .+= s.values
    end
    @test generation ≈ netload
end

@testset "plot_demand window aliases apply on the PSY.System path" begin
    sys = deepcopy(PSB.build_system(PSB.PSITestSystems, "c_sys5_uc"))
    initial_times = collect(get_forecast_initial_times(sys))
    t0 = initial_times[2]

    full = total_trace(
        plot_demand(sys; backend = PG.PlotlyLightBackend(), set_display = false),
    )
    windowed = total_trace(
        plot_demand(
            sys;
            backend = PG.PlotlyLightBackend(),
            set_display = false,
            start_time = t0,
            len = 3,
        ),
    )
    # `start_time`/`len` are documented aliases, so they must slice rather than
    # be silently dropped, and must agree with the canonical spellings.
    @test length(windowed) == 3
    @test length(full) > 3
    @test windowed ≈ total_trace(
        plot_demand(
            sys;
            backend = PG.PlotlyLightBackend(),
            set_display = false,
            initial_time = t0,
            horizon = 3,
        ),
    )
end

@testset "get_demand_data returns the numbers plot_demand draws" begin
    res = solve_interruptible_load_problem(
        build_interruptible_load_system(; n_interruptible = 2, capacity_scale = 0.55),
    )

    df = get_demand_data(res)
    @test names(df)[1] == PA.DATETIME_COL
    @test eltype(df[!, PA.DATETIME_COL]) <: Dates.DateTime

    # The reason this accessor is exported at all: it must agree with the plot,
    # not merely be plausible. Anything less and callers would be better off
    # reading a metric directly, which is the trap the sign fix exists to close.
    p = plot_demand(res; backend = PG.PlotlyLightBackend(), set_display = false)
    @test df[!, "Load"] ≈ series_values(p, "Load")

    # `aggregate` is meaningful only on the `PSY.System` path. Accepting and
    # ignoring it here would hand back a single aggregated column while implying
    # a per-bus breakdown, so the `IS.Results` method must not take it at all.
    @test_throws MethodError get_demand_data(res; aggregate = "Bus")
end

@testset "get_demand_data window key words and their aliases slice" begin
    sys = deepcopy(PSB.build_system(PSB.PSITestSystems, "c_sys5_uc"))
    t0 = collect(get_forecast_initial_times(sys))[2]

    full = get_demand_data(sys)
    windowed = get_demand_data(sys; start_time = t0, len = 3)
    @test DataFrames.nrow(windowed) == 3
    @test DataFrames.nrow(full) > 3
    @test windowed == get_demand_data(sys; initial_time = t0, horizon = 3)

    # The `System` path groups columns, so `aggregate` has to reach the reader.
    @test names(get_demand_data(sys; aggregate = "System")) !=
          names(get_demand_data(sys; aggregate = "Bus"))
end
