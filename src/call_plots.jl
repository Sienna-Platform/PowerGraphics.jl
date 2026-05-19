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
values (e.g. storage charging via `ActivePowerInVariable`) stack **downward**
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
    # type series (e.g. storage charging) always stack downward from 0.
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

function plot_demand_plotly(result::Union{IS.Results, PSY.System}; kwargs...)
    return plot_demand_plotly!(_empty_plot_plotly(), result; kwargs...)
end

"""
    plot_demand!(plot, result)
    plot_demand!(plot, system)

Plots the demand in the system.

# Arguments

- `plot`: existing plot handle, such as the result of [`plot()`](@extref RecipesBase.plot)
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
function _plot_demand!(p, result::Union{IS.Results, PSY.System}, backend; kwargs...)
    set_display = get(kwargs, :set_display, true)
    save_fig = get(kwargs, :save, nothing)
    bar = get(kwargs, :bar, false)

    title = get(kwargs, :title, "Demand")
    y_label = get(kwargs, :y_label, bar ? "MWh" : "MW")
    palette = get(kwargs, :palette, PALETTE)

    # Translate the user-facing `aggregate::String` kwarg into PA's typed
    # `aggregation` kwarg before calling `get_load_data`.
    kwargs = _translate_demand_aggregate(kwargs)
    load = PA.get_load_data(result; kwargs...)
    # Build a mutable copy with defaults so we splat exactly once below.
    kwargs = popkwargs(kwargs, :filter_func)
    # Optional per-timestep load added to demand (e.g. storage charging, so the
    # net-load line matches the top of the generation stack in `plot_fuel!`).
    extra_load = get(kwargs, :extra_load, nothing)
    kwargs = popkwargs(kwargs, :extra_load)
    linestyle = get(kwargs, :linestyle, :solid)
    kwargs[:linestyle] = Symbol(linestyle)
    kwargs[:line_dash] = string(linestyle)
    kwargs[:linewidth] = get(kwargs, :linewidth, 1)
    kwargs[:seriescolor] =
        get(kwargs, :seriescolor, get_palette_seriescolor(backend, palette))

    load_agg = PA.combine_categories(load.data)

    if isnothing(load_agg)
        throw(ErrorException("No load data found"))
    end

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
        load.time,
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

function plot_demand!(p, result::Union{IS.Results, PSY.System}; kwargs...)
    return _plot_demand!(p, result, CairoMakieBackend(); kwargs...)
end

function plot_demand_plotly!(p, result::Union{IS.Results, PSY.System}; kwargs...)
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

function plot_dataframe_plotly(df::DataFrames.DataFrame; kwargs...)
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

"""
    plot_dataframe!(plot, df)
    plot_dataframe!(plot, df, time_range)

Plots data from a [`DataFrames.DataFrame`](@extref) where each row represents a time period
and each column represents a trace

# Arguments

- `plot`: existing plot handle, such as the result of [`plot()`](@extref RecipesBase.plot)
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

function plot_dataframe_plotly!(p, df::DataFrames.DataFrame; kwargs...)
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

################################# Plotting PowerData ##########################

"""
    plot_powerdata(powerdata)

Makes a plot from a `PowerAnalytics.PowerData` object, such as the result of
`PowerAnalytics.get_generation_data`

# Arguments

- `powerdata::PowerAnalytics.PowerData`: The `PowerData` object to be plotted

# Accepted Key Words
- `combine_categories::Bool = false` : plot category values or each value in a category
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
function plot_powerdata(powerdata::PA.PowerData; kwargs...)
    return plot_powerdata!(_empty_plot(), powerdata; kwargs...)
end

function plot_powerdata_plotly(powerdata::PA.PowerData; kwargs...)
    return plot_powerdata_plotly!(_empty_plot_plotly(), powerdata; kwargs...)
end

"""
    plot_powerdata!(plot, powerdata)

Makes a plot from a `PowerAnalytics.PowerData` object, such as the result of
`PowerAnalytics.get_generation_data`

# Arguments

- `plot`: existing plot handle, such as the result of [`plot()`](@extref RecipesBase.plot) (optional)
- `powerdata::PowerAnalytics.PowerData`: The `PowerData` object to be plotted

# Accepted Key Words
- `combine_categories::Bool = false` : plot category values or each value in a category
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
function _plot_powerdata!(p, powerdata::PA.PowerData, backend; kwargs...)
    title = get(kwargs, :title, "")
    set_display = get(kwargs, :set_display, true)
    save_fig = get(kwargs, :save, nothing)

    if get(kwargs, :combine_categories, true)
        aggregate = get(kwargs, :aggregate, nothing)
        names = get(kwargs, :names, nothing)
        data = PA.combine_categories(powerdata.data; names = names, aggregate = aggregate)
    else
        data = powerdata.data
    end
    kwargs =
        Dict{Symbol, Any}((k, v) for (k, v) in kwargs if k ∉ [:title, :save, :set_display])

    p = _plot_dataframe!(p, data, powerdata.time, backend; set_display = false, kwargs...)

    set_display && _display_plot(backend, p)
    if !isnothing(save_fig)
        title = replace(title, " " => "_")
        format = get(kwargs, :format, "png")
        save_plot(p, joinpath(save_fig, "$title.$format"), backend; kwargs...)
    end
    return p
end

function plot_powerdata!(p, powerdata::PA.PowerData; kwargs...)
    return _plot_powerdata!(p, powerdata, CairoMakieBackend(); kwargs...)
end

function plot_powerdata_plotly!(p, powerdata::PA.PowerData; kwargs...)
    return _plot_powerdata!(p, powerdata, PlotlyLightBackend(); kwargs...)
end

"""
    plot_results(results)

Makes a plot from a results dictionary object

# Arguments

- `results::Dict{String, DataFrame`: The results to be plotted

# Accepted Key Words
- `combine_categories::Bool = false` : plot category values or each value in a category
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
function plot_results(results::Dict{String, DataFrames.DataFrame}; kwargs...)
    return plot_powerdata!(_empty_plot(), PA.PowerData(results); kwargs...)
end

function plot_results_plotly(results::Dict{String, DataFrames.DataFrame}; kwargs...)
    return plot_powerdata_plotly!(_empty_plot_plotly(), PA.PowerData(results); kwargs...)
end

"""
    plot_results!(plot, results)

Makes a plot from a results dictionary

# Arguments

- `plot`: existing plot handle, such as the result of [`plot()`](@extref RecipesBase.plot) (optional)
- `results::Dict{String, DataFrame}`: The results to be plotted

# Accepted Key Words
- `combine_categories::Bool = false` : plot category values or each value in a category
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
function plot_results!(p, results::Dict{String, DataFrames.DataFrame}; kwargs...)
    return plot_powerdata!(p, PA.PowerData(results); kwargs...)
end

function plot_results_plotly!(p, results::Dict{String, DataFrames.DataFrame}; kwargs...)
    return plot_powerdata_plotly!(p, PA.PowerData(results); kwargs...)
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

function plot_fuel_plotly(result::IS.Results; kwargs...)
    return plot_fuel_plotly!(_empty_plot_plotly(), result; kwargs...)
end

# Backend-dispatched entry point for the Weave report template so the template
# stays backend-agnostic instead of branching on the backend type.
_report_plot_fuel(::CairoMakieBackend, result; kwargs...) =
    plot_fuel(result; kwargs...)
_report_plot_fuel(::PlotlyLightBackend, result; kwargs...) =
    plot_fuel_plotly(result; kwargs...)

"""
    plot_fuel!(plot, results)

Plots a stack plot of the results by fuel type
and assigns each fuel type a specific color.

# Arguments

- `plot`: existing plot handle, such as the result of [`plot()`](@extref RecipesBase.plot) (optional)
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
function _plot_fuel!(p, result::IS.Results, backend; kwargs...)
    set_display = get(kwargs, :set_display, true)
    save_fig = get(kwargs, :save, nothing)
    curtailment = get(kwargs, :curtailment, true)
    slacks = get(kwargs, :slacks, true)
    load = get(kwargs, :load, true)
    title = get(kwargs, :title, "Fuel")
    stack = get(kwargs, :stack, true)
    bar = get(kwargs, :bar, false)
    palette = get(kwargs, :palette, PALETTE)
    kwargs =
        Dict{Symbol, Any}((k, v) for (k, v) in kwargs if k ∉ [:title, :save, :set_display])

    # Generation stack
    gen = PA.get_generation_data(result; kwargs...)
    sys = PA.PSI.get_system(result)
    if sys === nothing
        throw(
            ArgumentError("No System data present: please run `set_system!(results, sys)`"),
        )
    end
    cat = PA.make_fuel_dictionary(sys; kwargs...)
    fuel = PA.categorize_data(gen.data, cat; curtailment = curtailment, slacks = slacks)

    filter_func = get(kwargs, :filter_func, PSY.get_available)
    kwargs = popkwargs(kwargs, :filter_func)

    # passing names here enforces order; append any fuel categories not in the palette
    palette_categories = get_palette_category(palette)
    matched = intersect(palette_categories, keys(fuel))
    unmatched = setdiff(keys(fuel), palette_categories)
    fuel_agg = PA.combine_categories(fuel; names = vcat(matched, sort(collect(unmatched))))
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
        gen.time,
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
        # Net-load line = demand + storage charging, so it coincides with the
        # top of the generation stack (charging is drawn as a negative band by
        # the sign-aware stacker; only curtailment sits above the line).
        charge = nothing
        charge_cols = [k for k in keys(fuel) if endswith(k, " In")]
        if !isempty(charge_cols)
            nrows = length(gen.time)
            charge = zeros(nrows)
            for k in charge_cols
                m = Matrix(PA.no_datetime(fuel[k]))   # negative (charging)
                charge .+= -vec(sum(m; dims = 2))     # -> positive load
            end
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
            extra_load = charge,
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

function plot_fuel!(p, result::IS.Results; kwargs...)
    return _plot_fuel!(p, result, CairoMakieBackend(); kwargs...)
end

function plot_fuel_plotly!(p, result::IS.Results; kwargs...)
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
