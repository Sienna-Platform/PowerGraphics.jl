function _empty_plot()
    return _empty_plot(CairoMakieBackend())
end

function _empty_plot_plotly()
    return _empty_plot(PlotlyLightBackend())
end

function popkwargs(kwargs, kwarg)
    return Dict{Symbol, Any}((k, v) for (k, v) in kwargs if k ≠ kwarg)
end

# A CairoMakie plot is displayed through its `Figure`; a PlotlyLight plot is
# displayed directly. Dispatching keeps the backend split out of plot bodies.
_display_plot(::CairoMakieBackend, p) = display(p.figure)
_display_plot(::PlotlyLightBackend, p) = display(p)

# Translation table for the user-facing `aggregate::String` kwarg of
# `plot_demand` to the typed `aggregation::Type` kwarg expected by
# `PowerAnalytics.get_load_data(::PSY.System; aggregation = …)`. The
# `IS.Results` branch of `get_load_data` ignores `aggregation` entirely, so
# the translation is a safe no-op there.
const _AGGREGATE_STRING_TO_TYPE =
    Dict("System" => PSY.System, "Bus" => PSY.ACBus, "PowerLoad" => PSY.PowerLoad)

function _aggregate_to_type(s::AbstractString)
    haskey(_AGGREGATE_STRING_TO_TYPE, s) || throw(
        ArgumentError(
            "Unknown `aggregate` value $(repr(s)). " *
            "Valid options: $(collect(keys(_AGGREGATE_STRING_TO_TYPE))).",
        ),
    )
    return _AGGREGATE_STRING_TO_TYPE[s]
end

# An already-typed `aggregate` (e.g. `PSY.ACBus`) is passed through unchanged.
_aggregate_to_type(t::Type) = t

# Translate `:aggregate => "System" | "Bus" | "PowerLoad"` (if present) into
# the typed `:aggregation` kwarg PowerAnalytics expects. Returns a fresh
# `Dict{Symbol,Any}` regardless so callers can keep mutating it.
function _translate_demand_aggregate(kwargs)
    out = Dict{Symbol, Any}(kwargs)
    (haskey(out, :aggregate) && !isnothing(out[:aggregate])) || return out
    out[:aggregation] = _aggregate_to_type(out[:aggregate])
    delete!(out, :aggregate)
    return out
end

"""
Pick a power unit and scaling divisor from the peak magnitude of the plotted
totals (values are assumed to be in MW): `< 1e3 → MW`, `[1e3, 1e6) → GW`,
`≥ 1e6 → TW`. Returns `(divisor, unit_string)`.
"""
function _auto_power_unit(peak::Real)
    a = abs(float(peak))
    if a >= 1.0e6
        return (1.0e6, "TW")
    elseif a >= 1.0e3
        return (1.0e3, "GW")
    else
        return (1.0, "MW")
    end
end

"""
Resolve the y-axis label and data-scaling divisor for a fuel/generation plot.
Honors an explicit `:y_label` or `:power_scale` kwarg; otherwise auto-detects
MW/GW/TW from the peak stacked total of `df`, unless `:auto_units => false` or
`:bar => true` (energy bar plots keep the existing MWh behavior).
"""
function _resolve_power_units(df::DataFrames.DataFrame, kwargs)
    bar = get(kwargs, :bar, false)
    user_scale = get(kwargs, :power_scale, nothing)
    user_ylabel = get(kwargs, :y_label, nothing)
    if bar || !get(kwargs, :auto_units, true) || !isnothing(user_scale)
        divisor = something(user_scale, 1.0)
        unit = bar ? "MWh" : "MW"
    else
        mat = Matrix(PA.no_datetime(df))
        peak = if isempty(mat)
            0.0
        else
            # stacked plots: peak is the largest per-timestep positive total;
            # also guard against a single dominant (possibly negative) series.
            max(
                maximum(sum(x -> max(x, 0.0), mat; dims = 2)),
                maximum(abs, mat),
            )
        end
        divisor, unit = _auto_power_unit(peak)
    end
    return (something(user_ylabel, unit), divisor)
end

"""
Per-series `(lower, upper)` envelopes for a sign-aware stacked-area/line plot.
`data` is `time × series`. Positive values stack **upward** from 0, negative
values (e.g. storage charging or source input via `ActivePowerInVariable`) stack **downward**
from 0, so charging renders below the zero axis instead of being folded into the
positive generation stack. Returns `(lower, upper)` matrices the same size as
`data`; band `ix` is `[lower[:,ix], upper[:,ix]]`.
"""
function _signed_stack_bounds(data::AbstractMatrix)
    nt, ns = size(data)
    lower = zeros(eltype(data), nt, ns)
    upper = zeros(eltype(data), nt, ns)
    pos = zeros(eltype(data), nt)
    neg = zeros(eltype(data), nt)
    # Classify each *series* (not each value) by its net sign, matching the
    # PlotlyLight backend's `sign_group`. A positive-type series always stacks
    # on the positive baseline — even at timesteps where it is 0 (e.g. PV at
    # night) it keeps a zero-width band *in place* rather than jumping to the
    # negative baseline (which left whitespace holes / slash lines). Negative-
    # type series (e.g. storage charging, source input) always stack downward from 0.
    for ix in 1:ns
        series_negative = sum(@view data[:, ix]) < zero(eltype(data))
        for t in 1:nt
            v = data[t, ix]
            if series_negative
                upper[t, ix] = neg[t]
                lower[t, ix] = neg[t] + v
                neg[t] = lower[t, ix]
            else
                lower[t, ix] = pos[t]
                upper[t, ix] = pos[t] + v
                pos[t] = upper[t, ix]
            end
        end
    end
    return lower, upper
end

"""
Row indices selecting the user-requested time window from a full results time
axis; the legacy `initial_time`/`horizon` kwarg spellings stay accepted
alongside `start_time`/`len`. Slicing locally instead of forwarding to
`PowerAnalytics.compute` is deliberate: `compute` rejects unknown kwargs and,
in PowerAnalytics 1.4, mishandles time windows on simulation results (`len` is
treated as an execution count), so local row slicing is the only way to
preserve the old windowing behavior.
"""
# TODO upstream: fix `compute` time-window kwargs in PowerAnalytics, then
# forward `start_time`/`len` directly.
function _time_window_indices(time::AbstractVector, kwargs)
    start_time = get(kwargs, :initial_time, get(kwargs, :start_time, nothing))
    len = get(kwargs, :horizon, get(kwargs, :len, nothing))
    i0 = if isnothing(start_time)
        1
    else
        found = findfirst(==(start_time), time)
        isnothing(found) && throw(
            ArgumentError(
                "start_time $start_time is not one of the results timestamps",
            ),
        )
        found
    end
    i1 = isnothing(len) ? length(time) : i0 + len - 1
    i1 <= length(time) || throw(
        ArgumentError(
            "the requested time window ends after the results end ($(last(time)))",
        ),
    )
    return i0:i1
end

################################### DEMAND #################################

"""
    plot_demand(results)
    plot_demand(system)

Plots the demand in the system.

# Arguments

- `res::Union{`[`InfrastructureSystems.Results`](@extref)`, `[`PowerSystems.System`](@extref)`}`: 
    A `Results` object (e.g., [`PowerSimulations.SimulationProblemResults`](@extref))
    or [`PowerSystems.System`](@extref) to plot the demand from

# Example

```julia
res = PowerSimulations.solve_op_problem!(OpProblem)
plot = plot_demand(res)
```

# Accepted Key Words

- `linestyle::Symbol = :dash` : set line style
- `title::String`: Set a title for the plots
- `horizon::Int64`: To plot a shorter window of time than the full results
- `initial_time::DateTime`: To start the plot at a different time other than the results initial time
- `aggregate::String = "System", "PowerLoad", or "Bus"`: aggregate the demand other than by generator
- `set_display::Bool = true`: set to false to prevent the plots from displaying
- `save::String = "file_path"`: set a file path to save the plots
- `format::String = "png"`: file extension for saved plots. CairoMakie supports `"png"`, `"pdf"`, `"svg"`. PlotlyLight only supports `"html"` (other values are written as `.html` with a warning).
- `seriescolor::Array`: Set different colors for the plots
- `title::String = "Title"`: Set a title for the plots
- `stack::Bool = true`: stack plot traces
- `bar::Bool` : create bar plot
- `nofill::Bool` : force empty area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function applied to legend labels (typically the raw `Variable__Component` strings produced by PowerAnalytics). Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`. Note that when `combine_categories = true` (the default for `plot_powerdata`, `plot_results`, and `plot_fuel`), columns are aggregated to category names *before* `label_fn` runs — those names don't contain `__`, so the default `label_short` is a no-op. Pass `combine_categories = false` to see the effect of `label_fn` on the raw labels.
- `legend_position::Symbol = :right`: legend placement, `:right` or `:bottom`
- `legend_font_size::Number`: override the legend label font size
- `filter_func::Function = `[`PowerSystems.get_available`](@extref PowerSystems InfrastructureSystems.get_available-Tuple{RenewableDispatch}): filter components included in plot
"""  # ^ temporary workaround for https://github.com/Sienna-Platform/PowerSystems.jl/issues/1598
function plot_demand(result::Union{IS.Results, PSY.System}; kwargs...)
    return plot_demand!(_empty_plot(), result; kwargs...)
end

@doc (@doc plot_demand) function plot_demand_plotly(
    result::Union{IS.Results, PSY.System};
    kwargs...,
)
    return plot_demand_plotly!(_empty_plot_plotly(), result; kwargs...)
end

# Assemble the aggregated demand DataFrame (columns = demand categories, no
# DateTime column) and its time axis. Dispatching on the input type keeps the
# metrics-API and System paths separate.

# Results path: the PowerAnalytics metrics API.
function _demand_data(result::IS.Results; kwargs...)
    # A user-supplied filter folds into the selector; the default matches the
    # built-in `all_loads` selector grouped into a single column.
    filter_func = get(kwargs, :filter_func, nothing)
    selector = if isnothing(filter_func)
        PSY.rebuild_selector(PA.Selectors.all_loads; groupby = :all)
    else
        PSY.make_selector(filter_func, PSY.ElectricLoad; groupby = :all)
    end
    ldf = PA.compute(PA.Metrics.calc_load_forecast, result, selector)
    time = PA.get_time_vec(ldf)
    load = PA.get_data_vec(ldf)

    window = _time_window_indices(time, kwargs)
    # Range indexing allocates fresh vectors, so the metric's DataFrame can
    # never be mutated downstream (e.g. via `extra_load`); the fixed "Load"
    # column name keeps palette and label behavior identical to the old API.
    return (DataFrames.DataFrame("Load" => load[window]), time[window])
end

# System path: the new API cannot read demand straight from a `PSY.System`, so
# this stays on the old PowerAnalytics interface, including the
# `aggregate::String` → `aggregation::Type` translation.
function _demand_data(system::PSY.System; kwargs...)
    kwargs = _translate_demand_aggregate(kwargs)
    load = PA.get_load_data(system; kwargs...)
    return (PA.combine_categories(load.data), load.time)
end

function _plot_demand!(p, result::Union{IS.Results, PSY.System}, backend; kwargs...)
    set_display = get(kwargs, :set_display, true)
    save_fig = get(kwargs, :save, nothing)
    bar = get(kwargs, :bar, false)

    title = get(kwargs, :title, "Demand")
    y_label = get(kwargs, :y_label, bar ? "MWh" : "MW")
    palette = get(kwargs, :palette, PALETTE)

    load_agg, load_time = _demand_data(result; kwargs...)
    if isempty(load_agg)
        throw(ErrorException("No load data found"))
    end
    # Build a mutable copy with defaults so we splat exactly once below.
    kwargs = popkwargs(kwargs, :filter_func)
    # Optional per-timestep load added to demand (e.g. storage charging or source
    # input, so the net-load line matches the top of the generation stack in `plot_fuel!`).
    extra_load = get(kwargs, :extra_load, nothing)
    kwargs = popkwargs(kwargs, :extra_load)
    linestyle = get(kwargs, :linestyle, :solid)
    kwargs[:linestyle] = Symbol(linestyle)
    kwargs[:line_dash] = string(linestyle)
    kwargs[:linewidth] = get(kwargs, :linewidth, 1)
    kwargs[:seriescolor] =
        get(kwargs, :seriescolor, get_palette_seriescolor(backend, palette))

    if !isnothing(extra_load)
        el = collect(extra_load)
        for c in DataFrames.names(load_agg)
            length(el) == DataFrames.nrow(load_agg) || throw(
                DimensionMismatch(
                    "extra_load length $(length(el)) != demand rows $(DataFrames.nrow(load_agg))",
                ),
            )
            load_agg[!, c] = load_agg[!, c] .+ el
        end
    end

    p = _plot_dataframe!(
        p,
        load_agg,
        load_time,
        backend;
        y_label = y_label,
        set_display = false,
        title = title,
        kwargs...,
    )

    set_display && _display_plot(backend, p)
    if !isnothing(save_fig)
        title = replace(title, " " => "_")
        format = get(kwargs, :format, "png")
        save_plot(p, joinpath(save_fig, "$title.$format"), backend; kwargs...)
    end
    return p
end

"""
    plot_demand!(plot, result)
    plot_demand!(plot, system)
    plot_demand_plotly!(plot, result)
    plot_demand_plotly!(plot, system)

Plots the demand in the system onto an existing plot handle. The `!`-form mutates
or extends `plot`; the `_plotly` variants render with the PlotlyLight backend
instead of CairoMakie.

# Arguments

- `plot`: existing plot handle returned by a previous PowerGraphics plot call such as [`plot_demand`](@ref PowerGraphics.plot_demand)
- `res::Union{`[`InfrastructureSystems.Results`](@extref)`, `[`PowerSystems.System`](@extref)`}`:
    A `Results` object (e.g., [`PowerSimulations.SimulationProblemResults`](@extref))
    or [`PowerSystems.System`](@extref) to plot the demand from

# Accepted Key Words

- `linestyle::Symbol = :dash` : set line style
- `title::String`: Set a title for the plots
- `horizon::Int64`: To plot a shorter window of time than the full results
- `initial_time::DateTime`: To start the plot at a different time other than the results initial time
- `aggregate::String = "System", "PowerLoad", or "Bus"`: aggregate the demand by
    [`PowerSystems.System`](@extref), [`PowerSystems.PowerLoad`](@extref), or [`PowerSystems.Bus`](@extref),
    rather than by generator
- `set_display::Bool = true`: set to false to prevent the plots from displaying
- `save::String = "file_path"`: set a file path to save the plots
- `format::String = "png"`: file extension for saved plots. CairoMakie supports `"png"`, `"pdf"`, `"svg"`. PlotlyLight only supports `"html"` (other values are written as `.html` with a warning).
- `seriescolor::Array`: Set different colors for the plots
- `title::String = "Title"`: Set a title for the plots
- `stack::Bool = true`: stack plot traces
- `bar::Bool` : create bar plot
- `nofill::Bool` : force empty area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function applied to legend labels (typically the raw `Variable__Component` strings produced by PowerAnalytics). Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`. Note that when `combine_categories = true` (the default for `plot_powerdata`, `plot_results`, and `plot_fuel`), columns are aggregated to category names *before* `label_fn` runs — those names don't contain `__`, so the default `label_short` is a no-op. Pass `combine_categories = false` to see the effect of `label_fn` on the raw labels.
- `legend_position::Symbol = :right`: legend placement, `:right` or `:bottom`
- `legend_font_size::Number`: override the legend label font size
- `filter_func::Function = `[`PowerSystems.get_available`](@extref PowerSystems InfrastructureSystems.get_available-Tuple{RenewableDispatch}): filter components included in plot
- `palette` : color palette from [`load_palette`](@ref)
"""
function plot_demand!(p, result::Union{IS.Results, PSY.System}; kwargs...)
    return _plot_demand!(p, result, CairoMakieBackend(); kwargs...)
end

@doc (@doc plot_demand!) function plot_demand_plotly!(
    p,
    result::Union{IS.Results, PSY.System};
    kwargs...,
)
    return _plot_demand!(p, result, PlotlyLightBackend(); kwargs...)
end

################################# Plotting a Single DataFrame ##########################

"""
    plot_dataframe(df)
    plot_dataframe(df, time_range)

Plots data from a [`DataFrames.DataFrame`](@extref) where each row represents a time period
and each column represents a trace

# Arguments

- `df::DataFrames.DataFrame`: `DataFrame` where each row represents a time period and each column represents a trace.
If only the `DataFrame` is provided, it must have a column of `DateTime` values.
- `time_range::Union{DataFrames.DataFrame, Array, StepRange}`: The time periods of the data

# Example

```julia
var_name = :P__ThermalStandard
df = PowerSimulations.read_variables_with_keys(results, names = [var_name])[var_name]
time_range = PowerSimulations.get_realized_timestamps(results)
plot = plot_dataframe(df, time_range)
```

# Accepted Key Words
- `curtailment::Bool`: plot the curtailment with the variable
- `set_display::Bool = true`: set to false to prevent the plots from displaying
- `save::String = "file_path"`: set a file path to save the plots
- `format::String = "png"`: file extension for saved plots. CairoMakie supports `"png"`, `"pdf"`, `"svg"`. PlotlyLight only supports `"html"` (other values are written as `.html` with a warning).
- `seriescolor::Array`: Set different colors for the plots
- `title::String = "Title"`: Set a title for the plots
- `stack::Bool = true`: stack plot traces
- `bar::Bool` : create bar plot
- `nofill::Bool` : force empty area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function applied to legend labels (typically the raw `Variable__Component` strings produced by PowerAnalytics). Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`. Note that when `combine_categories = true` (the default for `plot_powerdata`, `plot_results`, and `plot_fuel`), columns are aggregated to category names *before* `label_fn` runs — those names don't contain `__`, so the default `label_short` is a no-op. Pass `combine_categories = false` to see the effect of `label_fn` on the raw labels.
- `legend_position::Symbol = :right`: legend placement, `:right` or `:bottom`
- `legend_font_size::Number`: override the legend label font size
"""
function plot_dataframe(df::DataFrames.DataFrame; kwargs...)
    return plot_dataframe!(_empty_plot(), PA.no_datetime(df), df.DateTime; kwargs...)
end
function plot_dataframe(
    df::DataFrames.DataFrame,
    time_range::Union{DataFrames.DataFrame, Array, StepRange};
    kwargs...,
)
    return plot_dataframe!(_empty_plot(), df, time_range; kwargs...)
end

@doc (@doc plot_dataframe) function plot_dataframe_plotly(
    df::DataFrames.DataFrame;
    kwargs...,
)
    return plot_dataframe_plotly!(
        _empty_plot_plotly(),
        PA.no_datetime(df),
        df.DateTime;
        kwargs...,
    )
end
function plot_dataframe_plotly(
    df::DataFrames.DataFrame,
    time_range::Union{DataFrames.DataFrame, Array, StepRange};
    kwargs...,
)
    return plot_dataframe_plotly!(_empty_plot_plotly(), df, time_range; kwargs...)
end

function _plot_dataframe!(
    p,
    variable::DataFrames.DataFrame,
    time_range::Union{DataFrames.DataFrame, Array, StepRange},
    backend;
    kwargs...,
)
    tr =
        typeof(time_range) == DataFrames.DataFrame ? time_range[:, 1] : collect(time_range)
    return _dataframe_plots_internal(p, variable, tr, backend; kwargs...)
end

"""
    plot_dataframe!(plot, df)
    plot_dataframe!(plot, df, time_range)
    plot_dataframe_plotly!(plot, df)
    plot_dataframe_plotly!(plot, df, time_range)

Plots data from a [`DataFrames.DataFrame`](@extref) where each row represents a time
period and each column represents a trace, onto an existing plot handle. The
`_plotly` variants render with the PlotlyLight backend instead of CairoMakie.

# Arguments

- `plot`: existing plot handle returned by a previous PowerGraphics plot call (e.g. [`plot_dataframe`](@ref))
- `df::DataFrames.DataFrame`: `DataFrame` where each row represents a time period and each column represents a trace.
If only the `DataFrame` is provided, it must have a column of `DateTime` values.
- `time_range::Union{DataFrames.DataFrame, Array, StepRange}`: The time periods of the data

# Accepted Key Words
- `curtailment::Bool`: plot the curtailment with the variable
- `set_display::Bool = true`: set to false to prevent the plots from displaying
- `save::String = "file_path"`: set a file path to save the plots
- `format::String = "png"`: file extension for saved plots. CairoMakie supports `"png"`, `"pdf"`, `"svg"`. PlotlyLight only supports `"html"` (other values are written as `.html` with a warning).
- `seriescolor::Array`: Set different colors for the plots
- `title::String = "Title"`: Set a title for the plots
- `stack::Bool = true`: stack plot traces
- `bar::Bool` : create bar plot
- `nofill::Bool` : force empty area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function applied to legend labels (typically the raw `Variable__Component` strings produced by PowerAnalytics). Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`. Note that when `combine_categories = true` (the default for `plot_powerdata`, `plot_results`, and `plot_fuel`), columns are aggregated to category names *before* `label_fn` runs — those names don't contain `__`, so the default `label_short` is a no-op. Pass `combine_categories = false` to see the effect of `label_fn` on the raw labels.
- `legend_position::Symbol = :right`: legend placement, `:right` or `:bottom`
- `legend_font_size::Number`: override the legend label font size
"""
function plot_dataframe!(p, df::DataFrames.DataFrame; kwargs...)
    return _plot_dataframe!(
        p,
        PA.no_datetime(df),
        df.DateTime,
        CairoMakieBackend();
        kwargs...,
    )
end

function plot_dataframe!(
    p,
    variable::DataFrames.DataFrame,
    time_range::Union{DataFrames.DataFrame, Array, StepRange};
    kwargs...,
)
    return _plot_dataframe!(p, variable, time_range, CairoMakieBackend(); kwargs...)
end

@doc (@doc plot_dataframe!) function plot_dataframe_plotly!(
    p,
    df::DataFrames.DataFrame;
    kwargs...,
)
    return _plot_dataframe!(
        p,
        PA.no_datetime(df),
        df.DateTime,
        PlotlyLightBackend();
        kwargs...,
    )
end

function plot_dataframe_plotly!(
    p,
    variable::DataFrames.DataFrame,
    time_range::Union{DataFrames.DataFrame, Array, StepRange};
    kwargs...,
)
    return _plot_dataframe!(p, variable, time_range, PlotlyLightBackend(); kwargs...)
end

################################# Plotting a Results Dictionary ##########################

# Split a dict of result DataFrames from its shared time axis: `DateTime`
# columns are stripped (copying) from every value and the time axis is taken
# from the first value's `DateTime` column, replicating the shape the old
# `PowerAnalytics.PowerData` constructor produced.
function _split_results_time(results::Dict{String, DataFrames.DataFrame})
    data =
        Dict{String, DataFrames.DataFrame}(k => PA.no_datetime(v) for (k, v) in results)
    return (data, first(values(results)).DateTime)
end

# Sum each entry's frame into a single column, preserving the old
# `PowerAnalytics.combine_categories` behavior: `names` restricts and orders
# the entries, `aggregate` maps each entry's `time × column` matrix to one
# column. Empty entries are dropped silently; when every entry is empty the
# result is an empty `DataFrame`.
function _combine_result_categories(
    data::Dict{String, DataFrames.DataFrame};
    names::Union{Vector{String}, Nothing} = nothing,
    aggregate::Union{Function, Nothing} = nothing,
)
    aggregate = something(aggregate, x -> sum(x; dims = 2))
    names = something(names, collect(keys(data)))
    cols = Pair{String, Any}[]
    for k in names
        isempty(data[k]) && continue
        push!(cols, k => vec(aggregate(Matrix(data[k]))))
    end
    return DataFrames.DataFrame(cols)
end

# Flatten without aggregation: one trace per stored column, labeled
# "<entry>__<column>" so the default `label_short` legend labels reduce to the
# column (usually component) names and collisions across entries are impossible.
function _flatten_result_categories(data::Dict{String, DataFrames.DataFrame})
    cols = Pair{String, Any}[]
    for k in sort!(collect(keys(data)))
        df = data[k]
        for c in DataFrames.names(df)
            push!(cols, "$(k)__$(c)" => df[!, c])
        end
    end
    return DataFrames.DataFrame(cols)
end

function _plot_results!(
    p,
    data::Dict{String, DataFrames.DataFrame},
    time,
    backend;
    kwargs...,
)
    title = get(kwargs, :title, "")
    set_display = get(kwargs, :set_display, true)
    save_fig = get(kwargs, :save, nothing)

    df = if get(kwargs, :combine_categories, true)
        _combine_result_categories(
            data;
            names = get(kwargs, :names, nothing),
            aggregate = get(kwargs, :aggregate, nothing),
        )
    else
        _flatten_result_categories(data)
    end
    kwargs = Dict{Symbol, Any}(
        (k, v) for (k, v) in kwargs if
        k ∉ [:title, :save, :set_display, :combine_categories, :names, :aggregate]
    )

    p = _plot_dataframe!(p, df, time, backend; set_display = false, kwargs...)

    set_display && _display_plot(backend, p)
    if !isnothing(save_fig)
        title = replace(title, " " => "_")
        format = get(kwargs, :format, "png")
        save_plot(p, joinpath(save_fig, "$title.$format"), backend; kwargs...)
    end
    return p
end

"""
    plot_results(results)

Makes a plot from a results dictionary object. Each entry's `DateTime` column is
stripped and the time axis is taken from the first entry.

# Arguments

- `results::Dict{String, DataFrame}`: The results to be plotted

# Accepted Key Words
- `combine_categories::Bool = true` : plot one aggregated trace per entry (the default), or one trace per column of each entry when `false`
- `names::Vector{String}`: subset and order of the entries to plot when `combine_categories = true`
- `aggregate::Function`: reduction applied to each entry's `time × column` matrix when `combine_categories = true` (default `x -> sum(x; dims = 2)`)
- `set_display::Bool = true`: set to false to prevent the plots from displaying
- `save::String = "file_path"`: set a file path to save the plots
- `format::String = "png"`: file extension for saved plots. CairoMakie supports `"png"`, `"pdf"`, `"svg"`. PlotlyLight only supports `"html"` (other values are written as `.html` with a warning).
- `seriescolor::Array`: Set different colors for the plots
- `title::String = "Title"`: Set a title for the plots
- `stack::Bool = true`: stack plot traces
- `bar::Bool` : create bar plot
- `nofill::Bool` : force empty area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function applied to legend labels (typically the raw `Variable__Component` strings produced by PowerAnalytics). Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`. Note that when `combine_categories = true` (the default for `plot_powerdata`, `plot_results`, and `plot_fuel`), columns are aggregated to category names *before* `label_fn` runs — those names don't contain `__`, so the default `label_short` is a no-op. Pass `combine_categories = false` to see the effect of `label_fn` on the raw labels.
- `legend_position::Symbol = :right`: legend placement, `:right` or `:bottom`
- `legend_font_size::Number`: override the legend label font size
"""
function plot_results(results::Dict{String, DataFrames.DataFrame}; kwargs...)
    return plot_results!(_empty_plot(), results; kwargs...)
end

@doc (@doc plot_results) function plot_results_plotly(
    results::Dict{String, DataFrames.DataFrame};
    kwargs...,
)
    return plot_results_plotly!(_empty_plot_plotly(), results; kwargs...)
end

"""
    plot_results!(plot, results)

Makes a plot from a results dictionary onto an existing plot handle. Each entry's
`DateTime` column is stripped and the time axis is taken from the first entry.

# Arguments

- `plot`: existing plot handle returned by a previous PowerGraphics plot call (optional; e.g. [`plot_results`](@ref))
- `results::Dict{String, DataFrame}`: The results to be plotted

# Accepted Key Words
- `combine_categories::Bool = true` : plot one aggregated trace per entry (the default), or one trace per column of each entry when `false`
- `names::Vector{String}`: subset and order of the entries to plot when `combine_categories = true`
- `aggregate::Function`: reduction applied to each entry's `time × column` matrix when `combine_categories = true` (default `x -> sum(x; dims = 2)`)
- `set_display::Bool = true`: set to false to prevent the plots from displaying
- `save::String = "file_path"`: set a file path to save the plots
- `format::String = "png"`: file extension for saved plots. CairoMakie supports `"png"`, `"pdf"`, `"svg"`. PlotlyLight only supports `"html"` (other values are written as `.html` with a warning).
- `seriescolor::Array`: Set different colors for the plots
- `title::String = "Title"`: Set a title for the plots
- `stack::Bool = true`: stack plot traces
- `bar::Bool` : create bar plot
- `nofill::Bool` : force empty area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function applied to legend labels (typically the raw `Variable__Component` strings produced by PowerAnalytics). Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`. Note that when `combine_categories = true` (the default for `plot_powerdata`, `plot_results`, and `plot_fuel`), columns are aggregated to category names *before* `label_fn` runs — those names don't contain `__`, so the default `label_short` is a no-op. Pass `combine_categories = false` to see the effect of `label_fn` on the raw labels.
- `legend_position::Symbol = :right`: legend placement, `:right` or `:bottom`
- `legend_font_size::Number`: override the legend label font size
"""
function plot_results!(p, results::Dict{String, DataFrames.DataFrame}; kwargs...)
    data, time = _split_results_time(results)
    return _plot_results!(p, data, time, CairoMakieBackend(); kwargs...)
end

@doc (@doc plot_results!) function plot_results_plotly!(
    p,
    results::Dict{String, DataFrames.DataFrame};
    kwargs...,
)
    data, time = _split_results_time(results)
    return _plot_results!(p, data, time, PlotlyLightBackend(); kwargs...)
end

################################# Plotting Fuel Plot of Results ##########################
"""
    plot_fuel(results)

Plots a stack plot of the results by fuel type
and assigns each fuel type a specific color.

# Arguments

- `res::`[`InfrastructureSystems.Results`](@extref): 
    A `Results` object (e.g., [`PowerSimulations.SimulationProblemResults`](@extref))
    to be plotted

    # Example

```julia
res = solve_op_problem!(OpProblem)
plot = plot_fuel(res)
```

# Accepted Key Words
- `generator_mapping_file` = "file_path" : file path to yaml defining generator category by fuel and primemover
- `variables::Union{Nothing, Vector{Symbol}}` = nothing : specific variables to plot
- `slacks::Bool = true` : display slack variables
- `load::Bool = true` : display load line
- `curtailment::Bool = true`: To plot the curtailment in the stack plot
- `set_display::Bool = true`: set to false to prevent the plots from displaying
- `save::String = "file_path"`: set a file path to save the plots
- `format::String = "png"`: file extension for saved plots. CairoMakie supports `"png"`, `"pdf"`, `"svg"`. PlotlyLight only supports `"html"` (other values are written as `.html` with a warning).
- `seriescolor::Array`: Set different colors for the plots
- `title::String = "Title"`: Set a title for the plots
- `stack::Bool = true`: stack plot traces
- `bar::Bool` : create bar plot
- `nofill::Bool` : force empty area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function applied to legend labels (typically the raw `Variable__Component` strings produced by PowerAnalytics). Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`. Note that when `combine_categories = true` (the default for `plot_powerdata`, `plot_results`, and `plot_fuel`), columns are aggregated to category names *before* `label_fn` runs — those names don't contain `__`, so the default `label_short` is a no-op. Pass `combine_categories = false` to see the effect of `label_fn` on the raw labels.
- `legend_position::Symbol = :right`: legend placement, `:right` or `:bottom`
- `legend_font_size::Number`: override the legend label font size
- `filter_func::Function = `[`PowerSystems.get_available`](@extref PowerSystems InfrastructureSystems.get_available-Tuple{RenewableDispatch}): filter components included in plot
"""
function plot_fuel(result::IS.Results; kwargs...)
    return plot_fuel!(_empty_plot(), result; kwargs...)
end

@doc (@doc plot_fuel) function plot_fuel_plotly(result::IS.Results; kwargs...)
    return plot_fuel_plotly!(_empty_plot_plotly(), result; kwargs...)
end

# Backend-dispatched entry point for the Weave report template so the template
# stays backend-agnostic instead of branching on the backend type.
_report_plot_fuel(::CairoMakieBackend, result; kwargs...) =
    plot_fuel(result; kwargs...)
_report_plot_fuel(::PlotlyLightBackend, result; kwargs...) =
    plot_fuel_plotly(result; kwargs...)

# The fuel stack is assembled on the PowerAnalytics metrics/selectors API, one
# metric evaluation per component, because the old pipeline's semantics cannot
# be reproduced with whole-selector `compute` calls: components whose results
# are absent must be skipped silently, each generator needs a
# variable → parameter → aux-variable fallback chain, and categories with no
# contributing component must vanish instead of producing all-zero columns.

# TODO upstream: PowerAnalytics has no built-in metrics for these entry types
# (it should export `calc_system_slack_down` and forecast metrics for the
# storage/source time-series parameters); build them locally until then.
const _CALC_POWER_OUTPUT =
    PA.make_component_metric_from_entry("PowerOutput", PA.PSI.PowerOutput)
const _CALC_ACTIVE_POWER_IN_FORECAST = PA.make_component_metric_from_entry(
    "ActivePowerInForecast",
    PA.PSI.ActivePowerInTimeSeriesParameter,
)
const _CALC_ACTIVE_POWER_OUT_FORECAST = PA.make_component_metric_from_entry(
    "ActivePowerOutForecast",
    PA.PSI.ActivePowerOutTimeSeriesParameter,
)
const _CALC_SYSTEM_SLACK_DOWN =
    PA.make_system_metric_from_entry("SystemSlackDown", PA.PSI.SystemBalanceSlackDown)

# Fallback chain for generators: dispatch power if the component was modeled
# with a variable, otherwise its forecast parameter (e.g. `FixedOutput`
# formulations), otherwise the `PowerOutput` aux variable. Only the first
# available metric contributes, mirroring the old `add_fixed_parameters!` /
# `add_aux_variables!` promotion rules.
const _GENERATION_METRICS = (
    (PA.Metrics.calc_active_power, 1.0),
    (PA.Metrics.calc_active_power_forecast, 1.0),
    (_CALC_POWER_OUTPUT, 1.0),
)
# Storage and source components split into "<category> In"/"<category> Out"
# columns instead of a plain one. Charging drawn through `ActivePowerInVariable`
# is flipped to negative so it stacks below zero; the source input time-series
# parameter is already negative (its multiplier is `active_power_limits.min`),
# so it keeps its sign. Every available metric contributes.
const _STORAGE_IN_METRICS = ((PA.Metrics.calc_active_power_in, -1.0),)
const _STORAGE_OUT_METRICS = ((PA.Metrics.calc_active_power_out, 1.0),)
const _SOURCE_IN_METRICS =
    ((PA.Metrics.calc_active_power_in, -1.0), (_CALC_ACTIVE_POWER_IN_FORECAST, 1.0))
const _SOURCE_OUT_METRICS =
    ((PA.Metrics.calc_active_power_out, 1.0), (_CALC_ACTIVE_POWER_OUT_FORECAST, 1.0))
# System balance slacks and their fixed display names, taken from
# `PA.BALANCE_SLACKVARS` so the naming has a single source of truth.
const _SLACK_METRICS = (
    (PA.BALANCE_SLACKVARS[PA.PSI.SystemBalanceSlackUp], PA.Metrics.calc_system_slack_up),
    (PA.BALANCE_SLACKVARS[PA.PSI.SystemBalanceSlackDown], _CALC_SYSTEM_SLACK_DOWN),
)

# Catch-all category for components matched by no rule in the generator
# mapping; matches the `Other` key in the default mapping and the color
# palette, like the old `PA.UNMAPPED_GENERATOR_CATEGORY`.
const _UNMAPPED_CATEGORY = "Other"

# Exceptions that mean "this result simply is not present": a component absent
# from a stored result table raises `NoResultError`, a result key that was
# never stored raises `InvalidValue`. Anything else is a real error.
_is_missing_result_error(::PA.NoResultError) = true
_is_missing_result_error(::IS.InvalidValue) = true
_is_missing_result_error(::Any) = false

# Accumulates fuel-category columns on a single shared time axis.
mutable struct _FuelAccumulator
    time::Vector{Dates.DateTime}
    cols::Dict{String, Vector{Float64}}
end

function _FuelAccumulator()
    return _FuelAccumulator(Dates.DateTime[], Dict{String, Vector{Float64}}())
end

function _add_fuel_values!(
    acc::_FuelAccumulator,
    name::String,
    time::Vector{Dates.DateTime},
    vals::Vector{Float64},
)
    if isempty(acc.time)
        acc.time = time
    elseif acc.time != time
        throw(ArgumentError("Mismatched time axes across fuel results for \"$name\""))
    end
    col = get!(acc.cols, name) do
        zeros(Float64, length(time))
    end
    col .+= vals
    return acc
end

# Compute one metric for one component, returning `(time, values)` as fresh
# vectors so the metric's DataFrame is never mutated downstream, or `nothing`
# when the component has no such result (the old pipeline skipped it silently).
function _try_component_metric(metric, result::IS.Results, comp::PSY.Component)
    df = try
        PA.compute(metric, result, comp)
    catch e
        _is_missing_result_error(e) && return nothing
        rethrow()
    end
    return (
        Vector{Dates.DateTime}(PA.get_time_vec(df)),
        Vector{Float64}(PA.get_data_vec(df)),
    )
end

function _accumulate_metrics!(
    acc::_FuelAccumulator,
    name::String,
    metrics_and_signs,
    result::IS.Results,
    comp::PSY.Component,
)
    for (metric, sign) in metrics_and_signs
        r = _try_component_metric(metric, result, comp)
        isnothing(r) && continue
        time, vals = r
        isone(sign) || (vals .*= sign)
        _add_fuel_values!(acc, name, time, vals)
    end
    return acc
end

# One component's contribution to its category, dispatched on the component
# role: generators contribute a plain "<category>" column through the fallback
# chain; storage and sources contribute "<category> In"/"<category> Out".
function _accumulate_component!(
    acc::_FuelAccumulator,
    category::String,
    result::IS.Results,
    comp::PSY.Generator,
)
    for (metric, sign) in _GENERATION_METRICS
        r = _try_component_metric(metric, result, comp)
        isnothing(r) && continue
        time, vals = r
        isone(sign) || (vals .*= sign)
        _add_fuel_values!(acc, category, time, vals)
        return acc
    end
    return acc
end

function _accumulate_component!(
    acc::_FuelAccumulator,
    category::String,
    result::IS.Results,
    comp::PSY.Storage,
)
    _accumulate_metrics!(acc, category * " In", _STORAGE_IN_METRICS, result, comp)
    _accumulate_metrics!(acc, category * " Out", _STORAGE_OUT_METRICS, result, comp)
    return acc
end

function _accumulate_component!(
    acc::_FuelAccumulator,
    category::String,
    result::IS.Results,
    comp::PSY.Source,
)
    _accumulate_metrics!(acc, category * " In", _SOURCE_IN_METRICS, result, comp)
    _accumulate_metrics!(acc, category * " Out", _SOURCE_OUT_METRICS, result, comp)
    return acc
end

# Curtailment (forecast minus dispatch) applies only to generators that have
# both results; everything else contributes nothing.
_accumulate_curtailment!(acc::_FuelAccumulator, ::IS.Results, ::PSY.Component) = acc

function _accumulate_curtailment!(
    acc::_FuelAccumulator,
    result::IS.Results,
    comp::PSY.Generator,
)
    r = _try_component_metric(PA.Metrics.calc_curtailment, result, comp)
    isnothing(r) && return acc
    time, vals = r
    _add_fuel_values!(acc, "Curtailment", time, vals)
    return acc
end

function _accumulate_slacks!(acc::_FuelAccumulator, result::IS.Results)
    for (name, metric) in _SLACK_METRICS
        df = try
            PA.compute(metric, result)
        catch e
            # Results without slack variables simply skip the category.
            _is_missing_result_error(e) || rethrow()
            continue
        end
        _add_fuel_values!(
            acc,
            name,
            Vector{Dates.DateTime}(PA.get_time_vec(df)),
            Vector{Float64}(PA.get_data_vec(df)),
        )
    end
    return acc
end

# Category selectors: the precompiled defaults, or a custom mapping file parsed
# per call. Which categories act as generator vs. storage/source is decided by
# the component roles in the pool, not by the mapping's metadata, so
# `parse_injector_categories` (which works with or without a `__META` section)
# is the right parser here.
_fuel_categories(::Nothing) = PA.Selectors.injector_categories
_fuel_categories(file::AbstractString) = PA.parse_injector_categories(file)

_pool_components(::Type{T}, result::IS.Results, filter_func::Function) where {T} =
    PSY.get_components(filter_func, T, result)
_pool_components(::Type{T}, result::IS.Results, ::Nothing) where {T} =
    PSY.get_components(T, result)

# The components eligible for fuel plotting: available generators, storage, and
# sources (never loads), optionally restricted by a user filter, matching the
# old `make_fuel_dictionary` iteration. The `storage`/`sources` kwargs of
# `plot_fuel` drop those roles entirely, like the old key filters did.
function _injector_pool(result::IS.Results, filter_func, storage::Bool, sources::Bool)
    pool = Vector{PSY.Component}()
    append!(pool, _pool_components(PSY.Generator, result, filter_func))
    storage && append!(pool, _pool_components(PSY.Storage, result, filter_func))
    sources && append!(pool, _pool_components(PSY.Source, result, filter_func))
    return pool
end

# Number of `supertype` steps from `T` to the type named `name`;
# `typemax(Int)` when the name never appears in the chain. Matching by name
# reproduces the old mapping lookup, which compared `string(nameof(t))`
# against the mapping's `gentype` strings.
function _type_distance(::Type{T}, name::AbstractString) where {T}
    t = T
    dist = 0
    while true
        string(nameof(t)) == name && return dist
        t === Any && return typemax(Int)
        t = supertype(t)
        dist += 1
    end
end

# One rule of the generator mapping: a category, the rule's specificity
# (parsed from the selector name PowerAnalytics assigns, either "Type" or
# "Type__PrimeMover__Fuel" with "Any" wildcards), and its member components.
struct _FuelRule
    category::String
    type_name::String
    pm_wild::Bool
    fuel_wild::Bool
    members::Set{PSY.Component}
end

function _FuelRule(category::String, rule_selector, members::Set{PSY.Component})
    parts = split(PA.get_name(rule_selector), PSY.COMPONENT_NAME_DELIMITER)
    pm_wild = length(parts) < 2 || parts[2] == "Any"
    fuel_wild = length(parts) < 3 || parts[3] == "Any"
    return _FuelRule(category, String(first(parts)), pm_wild, fuel_wild, members)
end

# Rank a rule for `comp` the way the old first-match-wins ladder did: most
# specific component type first, then prime-mover-specific over wildcard, then
# fuel-specific over wildcard. Smaller ranks win.
function _rule_rank(comp::PSY.Component, rule::_FuelRule)
    return (_type_distance(typeof(comp), rule.type_name), rule.pm_wild, rule.fuel_wild)
end

"""
Assign each pooled component to exactly one fuel category. The new
PowerAnalytics category selectors are independent, so a component can match
several (e.g. every gas generator matches both `NG-CC` and `NG-Steam` through
the fuel-only fallback rules); replaying the old priority ladder over the
per-rule subselectors keeps each component in a single category and prevents
its energy from being double-counted. Components matching no rule are returned
separately for the "$(_UNMAPPED_CATEGORY)" bucket.
"""
function _assign_fuel_categories(result::IS.Results, categories, pool, filter_func)
    rules = _FuelRule[]
    for (category, selector) in categories
        for rule_selector in PSY.get_groups(selector, result)
            members =
                Set{PSY.Component}(PSY.get_components(filter_func, rule_selector, result))
            isempty(members) && continue
            push!(rules, _FuelRule(category, rule_selector, members))
        end
    end
    assignments = Dict{String, Vector{PSY.Component}}()
    unmatched = PSY.Component[]
    for comp in pool
        best_category = nothing
        best_rank = (typemax(Int), true, true)
        for rule in rules
            comp in rule.members || continue
            rank = _rule_rank(comp, rule)
            if isnothing(best_category) || rank < best_rank
                best_category = rule.category
                best_rank = rank
            end
        end
        if isnothing(best_category)
            push!(unmatched, comp)
        else
            comps = get!(assignments, best_category) do
                Vector{PSY.Component}()
            end
            push!(comps, comp)
        end
    end
    return assignments, unmatched
end

"""
Assemble the fuel-stack DataFrame (columns = category names in
palette-first-then-sorted order, no `DateTime` column) and its time axis from
the PowerAnalytics metrics/selectors API. Categories with no contributing
component are dropped rather than emitted as all-zero columns.
"""
function _fuel_data(result::IS.Results, palette_categories::Vector{String}; kwargs...)
    # `get_system` is brought into PowerAnalytics from PowerSimulations, so it
    # can be reached without going through the unexported `PA.PSI` alias.
    if isnothing(PA.get_system(result))
        throw(
            ArgumentError(
                "No System data present: please run `set_system!(results, sys)` or " *
                "load the results with `populate_system = true`",
            ),
        )
    end
    filter_func = get(kwargs, :filter_func, nothing)
    curtailment = get(kwargs, :curtailment, true)
    slacks = get(kwargs, :slacks, true)
    storage = get(kwargs, :storage, true)
    sources = get(kwargs, :sources, true)
    categories = _fuel_categories(get(kwargs, :generator_mapping_file, nothing))

    pool = _injector_pool(result, filter_func, storage, sources)
    assignments, unmatched = _assign_fuel_categories(result, categories, pool, filter_func)

    acc = _FuelAccumulator()
    for (category, comps) in assignments, comp in comps
        _accumulate_component!(acc, category, result, comp)
    end
    if !isempty(unmatched)
        unmatched_names = sort([PSY.get_name(c) for c in unmatched])
        @error "No category in the generator mapping for components: " *
               "$(join(unmatched_names, ", ")); plotting them as \"$(_UNMAPPED_CATEGORY)\""
        for comp in unmatched
            _accumulate_component!(acc, _UNMAPPED_CATEGORY, result, comp)
        end
    end
    if curtailment
        for comp in pool
            _accumulate_curtailment!(acc, result, comp)
        end
    end
    slacks && _accumulate_slacks!(acc, result)

    isempty(acc.cols) && throw(ErrorException("No generation data found in the results"))

    # Palette categories first (in palette order), then the sorted remainder;
    # this column order is the trace order backends draw, so it must not change.
    matched = intersect(palette_categories, collect(keys(acc.cols)))
    remainder = sort(setdiff(collect(keys(acc.cols)), palette_categories))
    window = _time_window_indices(acc.time, kwargs)
    fuel_agg = DataFrames.DataFrame(
        [name => acc.cols[name][window] for name in vcat(matched, remainder)],
    )
    return (fuel_agg, acc.time[window])
end

function _plot_fuel!(p, result::IS.Results, backend; kwargs...)
    set_display = get(kwargs, :set_display, true)
    save_fig = get(kwargs, :save, nothing)
    load = get(kwargs, :load, true)
    title = get(kwargs, :title, "Fuel")
    stack = get(kwargs, :stack, true)
    palette = get(kwargs, :palette, PALETTE)
    kwargs =
        Dict{Symbol, Any}((k, v) for (k, v) in kwargs if k ∉ [:title, :save, :set_display])

    # Generation stack, assembled on the PowerAnalytics metrics/selectors API.
    fuel_agg, fuel_time = _fuel_data(result, get_palette_category(palette); kwargs...)

    filter_func = get(kwargs, :filter_func, PSY.get_available)
    kwargs = popkwargs(kwargs, :filter_func)

    y_label, power_scale = _resolve_power_units(fuel_agg, kwargs)
    kwargs = popkwargs(popkwargs(popkwargs(kwargs, :y_label), :power_scale), :auto_units)

    seriescolor = get(
        kwargs,
        :seriescolor,
        match_fuel_colors(fuel_agg, backend; palette = palette),
    )
    p = _plot_dataframe!(
        p,
        fuel_agg,
        fuel_time,
        backend;
        stack = stack,
        seriescolor = seriescolor,
        y_label = y_label,
        power_scale = power_scale,
        title = title,
        set_display = false,
        kwargs...,
    )

    kwargs = popkwargs(popkwargs(kwargs, :nofill), :seriescolor)

    kwargs[:linestyle] = get(kwargs, :linestyle, :dash)
    kwargs[:linewidth] = get(kwargs, :linewidth, 3)
    kwargs[:filter_func] = filter_func

    if load
        # Net-load line = demand + storage charging + source input, so it coincides
        # with the top of the generation stack (both are drawn as negative bands by
        # the sign-aware stacker; only curtailment sits above the line). The
        # "<category> In" columns are negative, so their flipped sum is the extra
        # load the overlay must include.
        in_cols = [c for c in DataFrames.names(fuel_agg) if endswith(c, " In")]
        if !isempty(in_cols)
            kwargs[:extra_load] = -vec(sum(Matrix(fuel_agg[!, in_cols]); dims = 2))
        end
        p = _plot_demand!(
            p,
            result,
            backend;
            nofill = true,
            title = title,
            y_label = y_label,
            power_scale = power_scale,
            set_display = false,
            stack = stack,
            seriescolor = ["black"],
            kwargs...,
        )
    end

    # service stack
    # TODO: how to display this?

    set_display && _display_plot(backend, p)
    if !isnothing(save_fig)
        title = replace(title, " " => "_")
        format = get(kwargs, :format, "png")
        save_plot(p, joinpath(save_fig, "$title.$format"), backend; kwargs...)
    end
    return p
end

"""
    plot_fuel!(plot, results)
    plot_fuel_plotly!(plot, results)

Plots a stack plot of the results by fuel type onto an existing plot handle and
assigns each fuel type a specific color. The `_plotly` variant renders with the
PlotlyLight backend instead of CairoMakie.

# Arguments

- `plot`: existing plot handle returned by a previous PowerGraphics plot call (optional; e.g. [`plot_fuel`](@ref))
- `res::`[`InfrastructureSystems.Results`](@extref):
    A `Results` object (e.g., [`PowerSimulations.SimulationProblemResults`](@extref))
    to be plotted

# Accepted Key Words
- `generator_mapping_file` = "file_path" : file path to yaml defining generator category by fuel and primemover
- `variables::Union{Nothing, Vector{Symbol}}` = nothing : specific variables to plot
- `slacks::Bool = true` : display slack variables
- `load::Bool = true` : display load line
- `curtailment::Bool = true`: To plot the curtailment in the stack plot
- `set_display::Bool = true`: set to false to prevent the plots from displaying
- `save::String = "file_path"`: set a file path to save the plots
- `format::String = "png"`: file extension for saved plots. CairoMakie supports `"png"`, `"pdf"`, `"svg"`. PlotlyLight only supports `"html"` (other values are written as `.html` with a warning).
- `seriescolor::Array`: Set different colors for the plots
- `title::String = "Title"`: Set a title for the plots
- `stack::Bool = true`: stack plot traces
- `bar::Bool` : create bar plot
- `nofill::Bool` : force empty area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function applied to legend labels (typically the raw `Variable__Component` strings produced by PowerAnalytics). Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`. Note that when `combine_categories = true` (the default for `plot_powerdata`, `plot_results`, and `plot_fuel`), columns are aggregated to category names *before* `label_fn` runs — those names don't contain `__`, so the default `label_short` is a no-op. Pass `combine_categories = false` to see the effect of `label_fn` on the raw labels.
- `legend_position::Symbol = :right`: legend placement, `:right` or `:bottom`
- `legend_font_size::Number`: override the legend label font size
- `filter_func::Function = `[`PowerSystems.get_available`](@extref PowerSystems InfrastructureSystems.get_available-Tuple{RenewableDispatch}): filter components included in plot
- `palette` : Color palette as from [`load_palette`](@ref).
"""
function plot_fuel!(p, result::IS.Results; kwargs...)
    return _plot_fuel!(p, result, CairoMakieBackend(); kwargs...)
end

@doc (@doc plot_fuel!) function plot_fuel_plotly!(p, result::IS.Results; kwargs...)
    return _plot_fuel!(p, result, PlotlyLightBackend(); kwargs...)
end

"""
    save_plot(plot, filename)

Saves a plot to the specified filename. The backend is chosen from the plot
object's type: CairoMakie plots dispatch to the CairoMakie writer (png/pdf/svg),
PlotlyLight plots dispatch to the PlotlyLight writer (html).

# Arguments

- `plot`: plot object returned by a `plot_*` function
- `filename::String` : path to save to

# Example

```julia
res = solve_op_problem!(OpProblem)
plot = plot_fuel(res)
save_plot(plot, "my_plot.png")               # CairoMakie
plot = plot_fuel_plotly(res)
save_plot(plot, "my_plot.html")               # PlotlyLight
```

# Accepted Key Words (PlotlyLight backend only; CairoMakie ignores them)
- `width::Union{Nothing,Int}=nothing`
- `height::Union{Nothing,Int}=nothing`
- `scale::Union{Nothing,Real}=nothing`
"""
# The 2-arg `save_plot(plot, filename)` form is defined per-backend via type
# dispatch — see `ext/plot_recipes.jl` (CairoMakie) and `ext/plotly_recipes.jl`
# (PlotlyLight).
function save_plot end
