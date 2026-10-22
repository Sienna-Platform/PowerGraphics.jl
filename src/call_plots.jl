function popkwargs(kwargs, kwarg)
    return Dict{Symbol, Any}((k, v) for (k, v) in kwargs if k ≠ kwarg)
end

# Key words shared by every public plot function, interpolated into their docstrings.
const _COMMON_PLOT_KWARGS = """
- `set_display::Bool = true`: set to false to prevent the plots from displaying
- `save::String`: directory to save the plot in, as `<title>.<format>` (`dataframe.<format>` when untitled)
- `format::String`: file extension for saved plots; defaults to `"png"` for the CairoMakie backend and `"html"` for the PlotlyLight backend. CairoMakie supports `"png"`, `"pdf"`, `"svg"`; PlotlyLight only supports `"html"` (other values are written as `.html` with a warning).
- `seriescolor::Array`: Set different colors for the plots
- `stack::Bool = false`: stack plot traces; `true` by default for `plot_fuel`
- `bar::Bool` : create bar plot
- `nofill::Bool = !bar && !stack`: draw traces without an area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function applied to legend labels (typically the raw `Variable__Component` strings produced by PowerAnalytics). Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`.
- `legend_position::Symbol = :right`: legend placement, `:right` or `:bottom`
- `legend_font_size::Number`: override the legend label font size
- `palette`: color palette from [`load_palette`](@ref)"""

const _BACKEND_KWARG = """
- `backend::PlottingBackend = CairoMakieBackend()`: plotting backend, `CairoMakieBackend()` (static png/pdf/svg) or `PlotlyLightBackend()` (interactive html). The matching backend package must be loaded with `using`."""

# A CairoMakie plot is displayed through its `Figure`; a PlotlyLight plot is
# displayed directly. Dispatching keeps the backend split out of plot bodies.
_display_plot(::CairoMakieBackend, p) = display(p.figure)
_display_plot(::PlotlyLightBackend, p) = display(p)

# Maps the user-facing `aggregate::String` kwarg of `plot_demand` to the typed
# `aggregation` kwarg of `PowerAnalytics.get_load_data(::PSY.System)`.
# Only used on the `PSY.System` path.
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
            max(maximum(sum(x -> max(x, 0.0), mat; dims = 2)), maximum(abs, mat))
        end
        divisor, unit = _auto_power_unit(peak)
    end
    return (something(user_ylabel, unit), divisor)
end

"""
Per-series net-sign classification of a `time × series` matrix: `true` where the
series' values sum to a net-negative total.
"""
function _series_is_negative(data::AbstractMatrix)
    return [sum(view(data, :, ix)) < zero(eltype(data)) for ix in axes(data, 2)]
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
    return _signed_stack_bounds(data, _series_is_negative(data))
end

# Classification is per series, not per value: a positive series keeps its band
# on the positive stack even at timesteps where it is 0.
function _signed_stack_bounds(data::AbstractMatrix, negative::AbstractVector{Bool})
    nt, ns = size(data)
    lower = zeros(eltype(data), nt, ns)
    upper = zeros(eltype(data), nt, ns)
    pos = zeros(eltype(data), nt)
    neg = zeros(eltype(data), nt)
    for ix in 1:ns
        for t in 1:nt
            v = data[t, ix]
            if negative[ix]
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
Series draw order for non-bar plots: net-negative series first, then the rest,
each group in column order, so positive bands are drawn on top.
"""
function _series_draw_order(negative::AbstractVector{Bool})
    return vcat(findall(negative), findall(.!negative))
end

function _series_draw_order(data::AbstractMatrix)
    return _series_draw_order(_series_is_negative(data))
end

# Legacy "no title" value; normalized to `nothing`.
const _NO_TITLE_SENTINEL = " "

# Base name a plot is saved under when it carries no title.
const _UNTITLED_SAVE_NAME = "dataframe"

"""
Plot settings resolved once by `_plot_dataframe!` and consumed by the backend
recipes in `ext/`. `data` is scaled by `power_scale`, `seriescolor` has one color
per drawn series, `title`/`save_file` are `nothing` when unset.
"""
struct _PlotOptions{C}
    bar::Bool
    stack::Bool
    stair::Bool
    nofill::Bool
    linestyle::Symbol
    linewidth::Float64
    power_scale::Float64
    y_label::String
    x_label::String
    title::Union{String, Nothing}
    save_file::Union{String, Nothing}
    set_display::Bool
    legend_position::Symbol
    legend_font_size::Union{Float64, Nothing}
    data::Matrix{Float64}
    column_labels::Vector{String}
    seriescolor::Vector{C}
    series_negative::Vector{Bool}
    interval::Float64
end

# `line_dash` is accepted as a legacy alias of `linestyle`.
function _resolve_linestyle(kwargs)
    haskey(kwargs, :linestyle) && return Symbol(kwargs[:linestyle])
    haskey(kwargs, :line_dash) && return Symbol(kwargs[:line_dash])
    return :solid
end

function _resolve_title(kwargs, default = nothing)
    title = get(kwargs, :title, default)
    if isnothing(title) || title == _NO_TITLE_SENTINEL
        return nothing
    end
    return String(title)
end

# Save path for a plot; spaces in the title become underscores.
function _resolve_save_file(backend::PlottingBackend, title, kwargs)
    save_dir = get(kwargs, :save, nothing)
    isnothing(save_dir) && return nothing
    format = get(kwargs, :format, _default_save_format(backend))
    name = replace(something(title, _UNTITLED_SAVE_NAME), " " => "_")
    return joinpath(save_dir, "$(name).$(format)")
end

function _PlotOptions(
    p,
    variable::DataFrames.DataFrame,
    time_range::Vector,
    backend::PlottingBackend,
    kwargs,
)
    bar = get(kwargs, :bar, false)
    stack = get(kwargs, :stack, false)
    title = _resolve_title(kwargs)
    font_size = get(kwargs, :legend_font_size, nothing)
    power_scale = Float64(get(kwargs, :power_scale, 1.0))

    ndf = PA.no_datetime(variable)
    data = Matrix{Float64}(ndf)
    power_scale == 1.0 || (data ./= power_scale)
    label_fn = get(kwargs, :label_fn, label_short)
    column_labels = [string(label_fn(name)) for name in DataFrames.names(ndf)]

    seriescolor = _series_colors(
        get(kwargs, :seriescolor, nothing),
        column_labels,
        p,
        backend,
        get(kwargs, :palette, PALETTE),
    )

    step = _time_step(time_range, get(kwargs, :resolution, nothing))
    return _PlotOptions(
        bar,
        stack,
        get(kwargs, :stair, false),
        get(kwargs, :nofill, !bar && !stack),
        _resolve_linestyle(kwargs),
        Float64(get(kwargs, :linewidth, 1)),
        power_scale,
        String(get(kwargs, :y_label, "")),
        string(IS.convert_compound_period(length(time_range) * step)),
        title,
        _resolve_save_file(backend, title, kwargs),
        get(kwargs, :set_display, true),
        Symbol(get(kwargs, :legend_position, :right)),
        isnothing(font_size) ? nothing : Float64(font_size),
        data,
        column_labels,
        seriescolor,
        _series_is_negative(data),
        # Steps per hour; bar plots divide summed totals by this.
        Dates.Millisecond(Dates.Hour(1)) / Dates.Millisecond(step),
    )
end

# Caller-supplied colors map to the series in order.
_series_colors(colors::Array, column_labels, p, ::PlottingBackend, palette) =
    set_seriescolor(colors, column_labels)

# The default palette continues the color cycle past series already on `p`.
function _series_colors(::Nothing, column_labels, p, backend::PlottingBackend, palette)
    drawn = _drawn_series_count(p, backend)
    colors = get_palette_seriescolor(backend, palette)
    return set_seriescolor(colors, vcat(ones(drawn), column_labels))[(drawn + 1):end]
end

# Spacing of `time_range`; a single time step takes it from `resolution`.
function _time_step(time_range::Vector, resolution)
    length(time_range) > 1 && return Dates.Millisecond(time_range[2] - time_range[1])
    isnothing(resolution) && throw(
        ArgumentError("plotting a single time step requires the `resolution` key word"),
    )
    return Dates.Millisecond(resolution)
end

const _REMOVED_WINDOW_KWARGS = (start_time = :initial_time, len = :horizon)

# Throw for the removed `start_time`/`len` time window key words.
function _check_removed_window_kwargs(kwargs)
    for (old, new) in pairs(_REMOVED_WINDOW_KWARGS)
        haskey(kwargs, old) && throw(
            ArgumentError("The `$old` key word was removed; use `$new` instead."),
        )
    end
    return
end

# `initial_time`/`horizon` key words to forward to `PA.compute`, unset ones dropped.
function _time_window_kwargs(kwargs)
    _check_removed_window_kwargs(kwargs)
    return NamedTuple(
        k => kwargs[k] for
        k in (:initial_time, :horizon) if !isnothing(get(kwargs, k, nothing))
    )
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

- `linestyle::Symbol = :solid` : set line style
- `horizon::Union{Int64, Dates.Period}`: number of time periods to plot, counted from `initial_time`; a `Dates.Period` (e.g. `Dates.Hour(12)`) is converted using the resolution of the time axis
- `resolution::Dates.Period`: time step of the data, used when a single time step is plotted; defaults to the resolution of the results, or of the system `Deterministic` time series
- `initial_time::DateTime`: To start the plot at a different time other than the results initial time
- `aggregate::String = "System", "PowerLoad", or "Bus"`: aggregate the demand other than by generator. Applies ONLY to the `PSY.System` input; the `IS.Results` path always aggregates to a single "Load" trace and ignores `aggregate` entirely.
$(_COMMON_PLOT_KWARGS)
- `title::String = "Demand"`: plot title
- `filter_func::Function = `[`PowerSystems.get_available`](@extref PowerSystems InfrastructureSystems.get_available-Tuple{RenewableDispatch}): filter components included in plot
$(_BACKEND_KWARG)
"""  # ^ temporary workaround for https://github.com/Sienna-Platform/PowerSystems.jl/issues/1598
function plot_demand(
    result::Union{IS.Results, PSY.System};
    backend::PlottingBackend = CairoMakieBackend(),
    kwargs...,
)
    return plot_demand!(_empty_plot(backend), result; backend = backend, kwargs...)
end

# Column name of the aggregated demand on the `IS.Results` path.
const _DEMAND_COLUMN = "Load"

# Demand is read variable-first, falling back to the forecast parameter. Under
# controllable load formulations the variable is the served load and the
# parameter is stored with the opposite sign, so the order matters.
const _DEMAND_METRICS = (PA.Metrics.calc_active_power, PA.Metrics.calc_load_forecast)

# Per-load-type selector: `PA.compute` throws if any component in a selector
# lacks the result, so the metric fallback is resolved per type.
_demand_type_selector(::Nothing, load_type::Type{<:PSY.ElectricLoad}) =
    PSY.make_selector(load_type; groupby = :all)
_demand_type_selector(filter_func::Function, load_type::Type{<:PSY.ElectricLoad}) =
    PSY.make_selector(filter_func, load_type; groupby = :all)

# `(time, values)` for one metric over a selector, or `nothing` if not stored.
function _try_selector_metric(metric, result::IS.Results, selector; kwargs...)
    df = try
        PA.compute(metric, result, selector; _time_window_kwargs(kwargs)...)
    catch e
        e isa PA.NoResultError && return nothing
        rethrow()
    end
    return (
        Vector{Dates.DateTime}(PA.get_time_vec(df)),
        Vector{Float64}(PA.get_data_vec(df)),
    )
end

# Results path: the PowerAnalytics metrics API.
function _demand_data(result::IS.Results; kwargs...)
    filter_func = get(kwargs, :filter_func, nothing)
    time = Dates.DateTime[]
    total = Float64[]
    # Sorted so the summation order is deterministic.
    pool = PSY.get_components(_demand_type_selector(filter_func, PSY.ElectricLoad), result)
    for load_type in sort!(unique(typeof(c) for c in pool); by = nameof)
        selector = _demand_type_selector(filter_func, load_type)
        for metric in _DEMAND_METRICS
            r = _try_selector_metric(metric, result, selector; kwargs...)
            isnothing(r) && continue
            metric_time, vals = r
            if isempty(time)
                time = metric_time
                total = zeros(Float64, length(metric_time))
            elseif time != metric_time
                throw(
                    ArgumentError(
                        "Mismatched time axes across load results for \"$load_type\"",
                    ),
                )
            end
            total .+= vals
            break
        end
    end
    isempty(time) && return (DataFrames.DataFrame(), Dates.DateTime[])
    return (DataFrames.DataFrame(_DEMAND_COLUMN => total), time)
end

# Time step of the plotted results.
_plot_resolution(result::IS.Results) = IS.Optimization.get_resolution(result)

# Resolution of the system's `Deterministic` time series, or `nothing` unless unique.
function _plot_resolution(system::PSY.System)
    resolutions =
        PSY.get_time_series_resolutions(system; time_series_type = PSY.Deterministic)
    length(resolutions) == 1 || return nothing
    return only(resolutions)
end

# System path: reads load time series via `PA.get_load_data`.
function _demand_data(system::PSY.System; kwargs...)
    kwargs = _translate_demand_aggregate(kwargs)
    load = PA.get_load_data(system; kwargs...)
    return (PA.combine_categories(load.data), load.time)
end

function _plot_demand!(p, result::Union{IS.Results, PSY.System}, backend; kwargs...)
    set_display = get(kwargs, :set_display, true)
    bar = get(kwargs, :bar, false)

    title = _resolve_title(kwargs, "Demand")
    y_label = get(kwargs, :y_label, bar ? "MWh" : "MW")
    save_file = _resolve_save_file(backend, title, kwargs)

    load_agg, load_time = _demand_data(result; kwargs...)
    if isempty(load_agg)
        throw(ArgumentError("No load data found"))
    end
    # Drop key words this wrapper handles itself.
    kwargs = Dict{Symbol, Any}(
        (k, v) for (k, v) in kwargs if k ∉ [:filter_func, :save, :title, :set_display]
    )
    kwargs[:linestyle] = _resolve_linestyle(kwargs)
    kwargs[:linewidth] = get(kwargs, :linewidth, 1)
    kwargs[:resolution] = get(() -> _plot_resolution(result), kwargs, :resolution)

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
    if !isnothing(save_file)
        save_plot(p, save_file, backend; kwargs...)
    end
    return p
end

"""
    plot_demand!(plot, result)
    plot_demand!(plot, system)

Plots the demand in the system onto an existing plot handle. The `!`-form mutates
or extends `plot`; pass the `backend` key word to pick the renderer.

# Arguments

- `plot`: existing plot handle returned by a previous PowerGraphics plot call such as [`plot_demand`](@ref PowerGraphics.plot_demand)
- `res::Union{`[`InfrastructureSystems.Results`](@extref)`, `[`PowerSystems.System`](@extref)`}`:
    A `Results` object (e.g., [`PowerSimulations.SimulationProblemResults`](@extref))
    or [`PowerSystems.System`](@extref) to plot the demand from

# Accepted Key Words

- `linestyle::Symbol = :solid` : set line style
- `horizon::Union{Int64, Dates.Period}`: number of time periods to plot, counted from `initial_time`; a `Dates.Period` (e.g. `Dates.Hour(12)`) is converted using the resolution of the time axis
- `resolution::Dates.Period`: time step of the data, used when a single time step is plotted; defaults to the resolution of the results, or of the system `Deterministic` time series
- `initial_time::DateTime`: To start the plot at a different time other than the results initial time
- `aggregate::String = "System", "PowerLoad", or "Bus"`: aggregate the demand other than by generator. Applies ONLY to the `PSY.System` input; the `IS.Results` path always aggregates to a single "Load" trace and ignores `aggregate` entirely.
$(_COMMON_PLOT_KWARGS)
- `title::String = "Demand"`: plot title
- `filter_func::Function = `[`PowerSystems.get_available`](@extref PowerSystems InfrastructureSystems.get_available-Tuple{RenewableDispatch}): filter components included in plot
$(_BACKEND_KWARG)
"""
function plot_demand!(
    p,
    result::Union{IS.Results, PSY.System};
    backend::PlottingBackend = CairoMakieBackend(),
    kwargs...,
)
    return _plot_demand!(p, result, backend; kwargs...)
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
- `resolution::Dates.Period`: time step of the data; required to plot a single time step
$(_COMMON_PLOT_KWARGS)
- `title::String`: plot title; none by default
$(_BACKEND_KWARG)
"""
function plot_dataframe(
    df::DataFrames.DataFrame;
    backend::PlottingBackend = CairoMakieBackend(),
    kwargs...,
)
    return plot_dataframe!(
        _empty_plot(backend),
        PA.no_datetime(df),
        df.DateTime;
        backend = backend,
        kwargs...,
    )
end

function plot_dataframe(
    df::DataFrames.DataFrame,
    time_range::Union{DataFrames.DataFrame, Array, StepRange};
    backend::PlottingBackend = CairoMakieBackend(),
    kwargs...,
)
    return plot_dataframe!(
        _empty_plot(backend),
        df,
        time_range;
        backend = backend,
        kwargs...,
    )
end

# A `time_range` handed in as a `DataFrame` carries the axis in its first column.
function _plot_dataframe!(
    p,
    variable::DataFrames.DataFrame,
    time_range::DataFrames.DataFrame,
    backend;
    kwargs...,
)
    return _plot_dataframe!(p, variable, time_range[:, 1], backend; kwargs...)
end

function _plot_dataframe!(
    p,
    variable::DataFrames.DataFrame,
    time_range::Union{Array, StepRange},
    backend;
    kwargs...,
)
    _check_removed_window_kwargs(kwargs)
    isnothing(p) && (p = _empty_plot(backend))
    if isempty(variable)
        @warn "Plot dataframe empty: skipping plot creation"
        return p
    end
    tr = collect(time_range)
    return _dataframe_plots_internal(
        p,
        tr,
        backend,
        _PlotOptions(p, variable, tr, backend, kwargs);
        kwargs...,
    )
end

"""
    plot_dataframe!(plot, df)
    plot_dataframe!(plot, df, time_range)

Plots data from a [`DataFrames.DataFrame`](@extref) where each row represents a time
period and each column represents a trace, onto an existing plot handle. Pass the
`backend` key word to pick the renderer.

# Arguments

- `plot`: existing plot handle returned by a previous PowerGraphics plot call (e.g. [`plot_dataframe`](@ref))
- `df::DataFrames.DataFrame`: `DataFrame` where each row represents a time period and each column represents a trace.
If only the `DataFrame` is provided, it must have a column of `DateTime` values.
- `time_range::Union{DataFrames.DataFrame, Array, StepRange}`: The time periods of the data

# Accepted Key Words
- `resolution::Dates.Period`: time step of the data; required to plot a single time step
$(_COMMON_PLOT_KWARGS)
- `title::String`: plot title; none by default
$(_BACKEND_KWARG)
"""
function plot_dataframe!(
    p,
    df::DataFrames.DataFrame;
    backend::PlottingBackend = CairoMakieBackend(),
    kwargs...,
)
    return _plot_dataframe!(p, PA.no_datetime(df), df.DateTime, backend; kwargs...)
end

function plot_dataframe!(
    p,
    variable::DataFrames.DataFrame,
    time_range::Union{DataFrames.DataFrame, Array, StepRange};
    backend::PlottingBackend = CairoMakieBackend(),
    kwargs...,
)
    return _plot_dataframe!(p, variable, time_range, backend; kwargs...)
end

################################# Plotting a Results Dictionary ##########################

# Strip `DateTime` columns from each entry and take the time axis from the first.
function _split_results_time(results::Dict{String, DataFrames.DataFrame})
    data = Dict{String, DataFrames.DataFrame}(k => PA.no_datetime(v) for (k, v) in results)
    return (data, first(values(results)).DateTime)
end

# Wraps `PA.combine_categories` with a clearer error for an unknown `names` entry.
function _combine_result_categories(
    data::Dict{String, DataFrames.DataFrame};
    names::Union{Vector{String}, Vector{Symbol}, Nothing} = nothing,
    aggregate::Union{Function, Nothing} = nothing,
)
    # `Vector{Symbol}` is accepted for the deprecated `plot_powerdata` path.
    entries = String.(something(names, collect(keys(data))))
    for k in entries
        haskey(data, k) || throw(
            ArgumentError(
                "`names` entry $(repr(k)) is not one of the results entries: " *
                "$(sort!(collect(keys(data))))",
            ),
        )
    end
    return PA.combine_categories(data; names = entries, aggregate = aggregate)
end

# Flatten without aggregation: one trace per stored column, labeled
# "<entry>__<column>" so labels are unique across entries.
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
    title = _resolve_title(kwargs)
    set_display = get(kwargs, :set_display, true)
    save_file = _resolve_save_file(backend, title, kwargs)

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

    p = _plot_dataframe!(
        p,
        df,
        time,
        backend;
        title = title,
        set_display = false,
        kwargs...,
    )

    set_display && _display_plot(backend, p)
    if !isnothing(save_file)
        save_plot(p, save_file, backend; kwargs...)
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
- `aggregate::Function`: reduction applied to each entry's `time × column` matrix when `combine_categories = true` (default `x -> sum(x; dims = 2)`). The function must return an array with one value per time period (length `nrow`); scalar returns are unsupported.
- `resolution::Dates.Period`: time step of the data; required to plot a single time step
$(_COMMON_PLOT_KWARGS)
- `title::String`: plot title; none by default
$(_BACKEND_KWARG)
"""
function plot_results(
    results::Dict{String, DataFrames.DataFrame};
    backend::PlottingBackend = CairoMakieBackend(),
    kwargs...,
)
    return plot_results!(_empty_plot(backend), results; backend = backend, kwargs...)
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
- `aggregate::Function`: reduction applied to each entry's `time × column` matrix when `combine_categories = true` (default `x -> sum(x; dims = 2)`). The function must return an array with one value per time period (length `nrow`); scalar returns are unsupported.
- `resolution::Dates.Period`: time step of the data; required to plot a single time step
$(_COMMON_PLOT_KWARGS)
- `title::String`: plot title; none by default
$(_BACKEND_KWARG)
"""
function plot_results!(
    p,
    results::Dict{String, DataFrames.DataFrame};
    backend::PlottingBackend = CairoMakieBackend(),
    kwargs...,
)
    data, time = _split_results_time(results)
    return _plot_results!(p, data, time, backend; kwargs...)
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
- `slacks::Bool = true` : display slack variables
- `load::Bool = true` : display load line
- `curtailment::Bool = true`: To plot the curtailment in the stack plot
- `storage::Bool = true`: include storage components (as "<category> In"/"<category> Out" traces)
- `sources::Bool = true`: include source components (as "<category> In"/"<category> Out" traces)
- `service::Union{PowerSystems.Service, String}`: a reserve product, or its name, from `PowerAnalytics.get_reserve_services(results)`. Stacks that product's reserve provision by fuel category instead of energy, titled with the service name by default; `load`, `curtailment` and `slacks` do not apply.
- `initial_time::DateTime`: To start the plot at a different time other than the results initial time
- `horizon::Union{Int64, Dates.Period}`: number of time periods to plot, counted from `initial_time`; a `Dates.Period` (e.g. `Dates.Hour(12)`) is converted using the resolution of the time axis
- `resolution::Dates.Period`: time step of the data, used when a single time step is plotted; defaults to the resolution of the results
$(_COMMON_PLOT_KWARGS)
- `title::String = "Fuel"`: plot title; defaults to the service name when `service` is set
- `filter_func::Function = `[`PowerSystems.get_available`](@extref PowerSystems InfrastructureSystems.get_available-Tuple{RenewableDispatch}): filter components included in plot
$(_BACKEND_KWARG)
"""
function plot_fuel(
    result::IS.Results;
    backend::PlottingBackend = CairoMakieBackend(),
    kwargs...,
)
    return plot_fuel!(_empty_plot(backend), result; backend = backend, kwargs...)
end

# Positional form kept for report templates from earlier releases.
_report_plot_fuel(backend::PlottingBackend, result; kwargs...) =
    plot_fuel(result; backend = backend, kwargs...)

# The fuel stack is computed per component so missing results can be skipped
# and each generator can use a metric fallback chain.

# Generator fallback chain: active power variable, then forecast parameter, then
# `PowerOutput` aux variable. Only the first available metric contributes.
const _GENERATION_METRICS = (
    PA.Metrics.calc_active_power,
    PA.Metrics.calc_active_power_forecast,
    PA.Metrics.calc_power_output,
)
# Storage and sources split into "<category> In"/"<category> Out" columns.
# `ActivePowerInVariable` is negated so charging stacks below zero; the source
# input parameter is already negative.
const _STORAGE_IN_METRICS = ((PA.Metrics.calc_active_power_in, -1.0),)
const _STORAGE_OUT_METRICS = ((PA.Metrics.calc_active_power_out, 1.0),)
const _SOURCE_IN_METRICS = (
    (PA.Metrics.calc_active_power_in, -1.0),
    (PA.Metrics.calc_active_power_in_forecast, 1.0),
)
const _SOURCE_OUT_METRICS = (
    (PA.Metrics.calc_active_power_out, 1.0),
    (PA.Metrics.calc_active_power_out_forecast, 1.0),
)
# System balance slacks, named via `PA.BALANCE_SLACKVARS`.
const _SLACK_METRICS = (
    (PA.BALANCE_SLACKVARS[PA.PSI.SystemBalanceSlackUp], PA.Metrics.calc_system_slack_up),
    (
        PA.BALANCE_SLACKVARS[PA.PSI.SystemBalanceSlackDown],
        PA.Metrics.calc_system_slack_down,
    ),
)

# Category for components matched by no rule in the generator mapping.
const _UNMAPPED_CATEGORY = "Other"

# Fuel-category columns on a shared time axis; `window` is passed to every `PA.compute`.
mutable struct _FuelAccumulator{W <: NamedTuple}
    time::Vector{Dates.DateTime}
    cols::Dict{String, Vector{Float64}}
    window::W
end

function _FuelAccumulator(window::NamedTuple)
    return _FuelAccumulator(Dates.DateTime[], Dict{String, Vector{Float64}}(), window)
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

# `(time, values)` for one metric on one component, or `nothing` if not stored.
function _try_component_metric(
    metric,
    result::IS.Results,
    comp::PSY.Component,
    window::NamedTuple,
)
    df = try
        PA.compute(metric, result, comp; window...)
    catch e
        e isa PA.NoResultError && return nothing
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
        r = _try_component_metric(metric, result, comp, acc.window)
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
    for metric in _GENERATION_METRICS
        r = _try_component_metric(metric, result, comp, acc.window)
        isnothing(r) && continue
        time, vals = r
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
    r = _try_component_metric(PA.Metrics.calc_curtailment, result, comp, acc.window)
    isnothing(r) && return acc
    time, vals = r
    _add_fuel_values!(acc, "Curtailment", time, vals)
    return acc
end

function _accumulate_slacks!(acc::_FuelAccumulator, result::IS.Results)
    for (name, metric) in _SLACK_METRICS
        df = try
            PA.compute(metric, result; acc.window...)
        catch e
            # Results without slack variables simply skip the category.
            e isa PA.NoResultError || rethrow()
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

# Category selectors: the PowerAnalytics defaults, or parsed from a mapping file.
_fuel_categories(::Nothing) = PA.Selectors.injector_categories

# `ext_category` is not supported by the selector parser; warn if present.
_has_ext_category(::Any) = false
_has_ext_category(v::AbstractVector) = any(_has_ext_category, v)
function _has_ext_category(d::AbstractDict)
    return haskey(d, "ext_category") || any(_has_ext_category, values(d))
end

function _fuel_categories(file::AbstractString)
    if _has_ext_category(YAML.load_file(file))
        @warn "The generator mapping file $file contains `ext_category` keys, which " *
              "are not supported; those rules will match without the ext discrimination."
    end
    return PA.parse_injector_categories(file)
end

# The component type every fuel category selector is rooted at.
const _MAPPING_ROOT_TYPE = PSY.StaticInjection

_pool_components(::Type{T}, result::IS.Results, filter_func::Function) where {T} =
    PSY.get_components(filter_func, T, result)
_pool_components(::Type{T}, result::IS.Results, ::Nothing) where {T} =
    PSY.get_components(T, result)

# Generators, storage and sources eligible for the fuel plot (never loads).
function _injector_pool(result::IS.Results, filter_func, storage::Bool, sources::Bool)
    pool = Vector{_MAPPING_ROOT_TYPE}()
    append!(pool, _pool_components(PSY.Generator, result, filter_func))
    storage && append!(pool, _pool_components(PSY.Storage, result, filter_func))
    sources && append!(pool, _pool_components(PSY.Source, result, filter_func))
    return pool
end

"""
Assign each pooled component to its PowerAnalytics fuel category. Components
matching no category are returned separately for the "$(_UNMAPPED_CATEGORY)" bucket.
"""
function _assign_fuel_categories(result::IS.Results, categories, pool)
    in_pool = Set{_MAPPING_ROOT_TYPE}(pool)
    assigned = Set{_MAPPING_ROOT_TYPE}()
    assignments = Dict{String, Vector{_MAPPING_ROOT_TYPE}}()
    for category in sort!(collect(keys(categories)))
        for comp in PSY.get_components(categories[category], result)
            (comp in in_pool && !(comp in assigned)) || continue
            push!(assigned, comp)
            comps = get!(assignments, category) do
                Vector{_MAPPING_ROOT_TYPE}()
            end
            push!(comps, comp)
        end
    end
    unmatched = filter(comp -> !(comp in assigned), pool)
    return assignments, unmatched
end

# The system attached to `result`, which the fuel categories are read from.
function _results_system(result::IS.Results)
    sys = PA.get_system(result)
    if isnothing(sys)
        throw(
            ArgumentError(
                "No System data present: please run `set_system!(results, sys)` or " *
                "load the results with `populate_system = true`",
            ),
        )
    end
    return sys
end

# Injectors selected by the `filter_func`, `storage` and `sources` key words.
_kwargs_pool(result::IS.Results, kwargs) = _injector_pool(
    result,
    get(kwargs, :filter_func, nothing),
    get(kwargs, :storage, true),
    get(kwargs, :sources, true),
)

# Pooled components by fuel category (from the `generator_mapping_file` key
# word); components matching no rule are logged and grouped under
# `_UNMAPPED_CATEGORY`.
function _components_by_category(result::IS.Results, pool, kwargs)
    categories = _fuel_categories(get(kwargs, :generator_mapping_file, nothing))
    assignments, unmatched = _assign_fuel_categories(result, categories, pool)
    if !isempty(unmatched)
        unmatched_names = sort([PSY.get_name(c) for c in unmatched])
        @error "No category in the generator mapping for components: " *
               "$(join(unmatched_names, ", ")); plotting them as \"$(_UNMAPPED_CATEGORY)\""
        comps = get!(assignments, _UNMAPPED_CATEGORY) do
            Vector{_MAPPING_ROOT_TYPE}()
        end
        append!(comps, unmatched)
    end
    return assignments
end

# Accumulated columns as a DataFrame (palette categories first, in palette
# order, then the sorted remainder) and their time axis.
function _stack_frame(acc::_FuelAccumulator, palette_categories::Vector{String})
    matched = intersect(palette_categories, collect(keys(acc.cols)))
    remainder = sort(setdiff(collect(keys(acc.cols)), palette_categories))
    df = DataFrames.DataFrame([name => acc.cols[name] for name in vcat(matched, remainder)])
    return (df, acc.time)
end

"""
Fuel-stack DataFrame (palette categories first, then sorted; no `DateTime`
column) and its time axis. Categories with no contributing component are dropped.
"""
function _fuel_data(result::IS.Results, palette_categories::Vector{String}; kwargs...)
    _results_system(result)
    haskey(kwargs, :variables) &&
        @warn "The `variables` kwarg is no longer supported and is ignored; " *
              "use filter_func/generator_mapping_file instead."
    curtailment = get(kwargs, :curtailment, true)
    slacks = get(kwargs, :slacks, true)

    pool = _kwargs_pool(result, kwargs)
    acc = _FuelAccumulator(_time_window_kwargs(kwargs))
    for (category, comps) in _components_by_category(result, pool, kwargs),
        comp in comps

        _accumulate_component!(acc, category, result, comp)
    end
    if curtailment
        for comp in pool
            _accumulate_curtailment!(acc, result, comp)
        end
    end
    slacks && _accumulate_slacks!(acc, result)

    isempty(acc.cols) && throw(ErrorException("No generation data found in the results"))
    return _stack_frame(acc, palette_categories)
end

"""
Reserve provision of `service` by fuel category, in the layout of `_fuel_data`.
Only devices contributing to `service` are included; storage and sources
contribute a single "<category>" column.
"""
function _service_fuel_data(
    result::IS.Results,
    service::PSY.Service,
    palette_categories::Vector{String};
    kwargs...,
)
    sys = _results_system(result)
    contributing = Set(PSY.get_contributing_devices(sys, service))
    pool = filter!(in(contributing), _kwargs_pool(result, kwargs))
    provision = ((PA.Metrics.make_calc_reserve_provision(service), 1.0),)
    acc = _FuelAccumulator(_time_window_kwargs(kwargs))
    for (category, comps) in _components_by_category(result, pool, kwargs),
        comp in comps

        _accumulate_metrics!(acc, category, provision, result, comp)
    end

    isempty(acc.cols) && throw(
        ErrorException(
            "No reserve provision found for \"$(PSY.get_name(service))\" in the results",
        ),
    )
    return _stack_frame(acc, palette_categories)
end

# A service is matched by type and name, so a `Service` from another copy of
# the system resolves to the results system's own object.
_service_matches(name::AbstractString) = s -> PSY.get_name(s) == name
_service_matches(service::PSY.Service) =
    s -> IS.component_to_qualified_string(s) ==
         IS.component_to_qualified_string(service)

_service_label(name::AbstractString) = name
_service_label(service::PSY.Service) = PSY.get_name(service)

"""
The reserve product in `available` matching `service` (a `PSY.Service` or a
name). Throws an `ArgumentError` if none or, for a name, several match.
"""
function _select_service(available::AbstractVector, service)
    matches = filter(_service_matches(service), available)
    if isempty(matches)
        throw(
            ArgumentError(
                "No reserve results for service \"$(_service_label(service))\"; " *
                "reserve products in the results: " *
                "$(isempty(available) ? "none" : join(PSY.get_name.(available), ", "))",
            ),
        )
    end
    length(matches) > 1 && throw(
        ArgumentError(
            "Several reserve products are named \"$(_service_label(service))\"; " *
            "pass the service itself",
        ),
    )
    return only(matches)
end

# The `service` key word of `plot_fuel`, resolved to the results system's
# reserve product.
_resolve_service(::IS.Results, ::Nothing) = nothing
_resolve_service(result::IS.Results, service::Union{PSY.Service, AbstractString}) =
    _select_service(PA.get_reserve_services(result), service)

# The energy fuel stack, or one reserve product's provision stacked by fuel.
_fuel_stack(result::IS.Results, ::Nothing, palette_categories; kwargs...) =
    _fuel_data(result, palette_categories; kwargs...)
_fuel_stack(result::IS.Results, service::PSY.Service, palette_categories; kwargs...) =
    _service_fuel_data(result, service, palette_categories; kwargs...)

_fuel_title(::Nothing) = "Fuel"
_fuel_title(service::PSY.Service) = PSY.get_name(service)

# Reserve provision has no demand to compare against.
_draws_load(::Nothing, load::Bool) = load
_draws_load(::PSY.Service, ::Bool) = false

function _plot_fuel!(p, result::IS.Results, backend; kwargs...)
    set_display = get(kwargs, :set_display, true)
    service = _resolve_service(result, get(kwargs, :service, nothing))
    load = _draws_load(service, get(kwargs, :load, true))
    title = _resolve_title(kwargs, _fuel_title(service))
    stack = get(kwargs, :stack, true)
    palette = get(kwargs, :palette, PALETTE)
    save_file = _resolve_save_file(backend, title, kwargs)
    kwargs = Dict{Symbol, Any}(
        (k, v) for (k, v) in kwargs if k ∉ [:title, :save, :set_display, :service]
    )
    kwargs[:resolution] = get(() -> _plot_resolution(result), kwargs, :resolution)

    fuel_agg, fuel_time =
        _fuel_stack(result, service, get_palette_category(palette); kwargs...)

    filter_func = get(kwargs, :filter_func, PSY.get_available)
    kwargs = popkwargs(kwargs, :filter_func)

    y_label, power_scale = _resolve_power_units(fuel_agg, kwargs)
    kwargs = popkwargs(popkwargs(popkwargs(kwargs, :y_label), :power_scale), :auto_units)

    seriescolor =
        get(kwargs, :seriescolor, match_fuel_colors(fuel_agg, backend; palette = palette))
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
        # The load line is end-use demand only; storage charging is its own band.
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

    set_display && _display_plot(backend, p)
    if !isnothing(save_file)
        save_plot(p, save_file, backend; kwargs...)
    end
    return p
end

"""
    plot_fuel!(plot, results)

Plots a stack plot of the results by fuel type onto an existing plot handle and
assigns each fuel type a specific color. Pass the `backend` key word to pick the
renderer.

# Arguments

- `plot`: existing plot handle returned by a previous PowerGraphics plot call (optional; e.g. [`plot_fuel`](@ref))
- `res::`[`InfrastructureSystems.Results`](@extref):
    A `Results` object (e.g., [`PowerSimulations.SimulationProblemResults`](@extref))
    to be plotted

# Accepted Key Words
- `generator_mapping_file` = "file_path" : file path to yaml defining generator category by fuel and primemover
- `slacks::Bool = true` : display slack variables
- `load::Bool = true` : display load line
- `curtailment::Bool = true`: To plot the curtailment in the stack plot
- `storage::Bool = true`: include storage components (as "<category> In"/"<category> Out" traces)
- `sources::Bool = true`: include source components (as "<category> In"/"<category> Out" traces)
- `service::Union{PowerSystems.Service, String}`: a reserve product, or its name, from `PowerAnalytics.get_reserve_services(results)`. Stacks that product's reserve provision by fuel category instead of energy, titled with the service name by default; `load`, `curtailment` and `slacks` do not apply.
- `initial_time::DateTime`: To start the plot at a different time other than the results initial time
- `horizon::Union{Int64, Dates.Period}`: number of time periods to plot, counted from `initial_time`; a `Dates.Period` (e.g. `Dates.Hour(12)`) is converted using the resolution of the time axis
- `resolution::Dates.Period`: time step of the data, used when a single time step is plotted; defaults to the resolution of the results
$(_COMMON_PLOT_KWARGS)
- `title::String = "Fuel"`: plot title; defaults to the service name when `service` is set
- `filter_func::Function = `[`PowerSystems.get_available`](@extref PowerSystems InfrastructureSystems.get_available-Tuple{RenewableDispatch}): filter components included in plot
$(_BACKEND_KWARG)
"""
function plot_fuel!(
    p,
    result::IS.Results;
    backend::PlottingBackend = CairoMakieBackend(),
    kwargs...,
)
    return _plot_fuel!(p, result, backend; kwargs...)
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
plot = plot_fuel(res; backend = PlotlyLightBackend())
save_plot(plot, "my_plot.html")               # PlotlyLight
```

# Accepted Key Words (PlotlyLight backend only; CairoMakie ignores them)
- `autoplay`, `post_script`, `full_html`, `animation_opts`, `default_width`, `default_height`: passed to the HTML writer
"""
# The 2-arg `save_plot(plot, filename)` form is defined per-backend via type
# dispatch — see `ext/plot_recipes.jl` (CairoMakie) and `ext/plotly_recipes.jl`
# (PlotlyLight).
function save_plot end
