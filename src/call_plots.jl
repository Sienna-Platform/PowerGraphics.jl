function popkwargs(kwargs, kwarg)
    return Dict{Symbol, Any}((k, v) for (k, v) in kwargs if k ≠ kwarg)
end

# Key-word documentation every public plot function accepts, interpolated into
# each docstring rather than copied into it: the same twelve entries appeared in
# eight docstrings and could only rot independently. Function-specific key words
# stay written out at the call site.
const _COMMON_PLOT_KWARGS = """
- `set_display::Bool = true`: set to false to prevent the plots from displaying
- `save::String = "file_path"`: set a file path to save the plots
- `format::String`: file extension for saved plots; defaults to `"png"` for the CairoMakie backend and `"html"` for the PlotlyLight backend. CairoMakie supports `"png"`, `"pdf"`, `"svg"`; PlotlyLight only supports `"html"` (other values are written as `.html` with a warning).
- `seriescolor::Array`: Set different colors for the plots
- `title::String = "Title"`: Set a title for the plots
- `stack::Bool = true`: stack plot traces
- `bar::Bool` : create bar plot
- `nofill::Bool = !bar && !stack`: draw traces without an area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function applied to legend labels (typically the raw `Variable__Component` strings produced by PowerAnalytics). Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`. Note that when `combine_categories = true` (the default for `plot_results`; `plot_fuel` always aggregates), columns are aggregated to category names *before* `label_fn` runs — those names don't contain `__`, so the default `label_short` is a no-op. Pass `combine_categories = false` to see the effect of `label_fn` on the raw labels.
- `legend_position::Symbol = :right`: legend placement, `:right` or `:bottom`
- `legend_font_size::Number`: override the legend label font size"""

# Documented last in every plot docstring, and in the deprecated shims too.
const _BACKEND_KWARG = """
- `backend::PlottingBackend = CairoMakieBackend()`: plotting backend, `CairoMakieBackend()` (static png/pdf/svg) or `PlotlyLightBackend()` (interactive html). The matching backend package must be loaded with `using`."""

# A CairoMakie plot is displayed through its `Figure`; a PlotlyLight plot is
# displayed directly. Dispatching keeps the backend split out of plot bodies.
_display_plot(::CairoMakieBackend, p) = display(p.figure)
_display_plot(::PlotlyLightBackend, p) = display(p)

# Translation table for the user-facing `aggregate::String` kwarg of
# `plot_demand` to the typed `aggregation::Type` kwarg expected by
# `PowerAnalytics.get_load_data(::PSY.System; aggregation = …)`. This
# translation applies ONLY to the `PSY.System` path; the `IS.Results` path
# always aggregates to a single "Load" column and ignores `aggregate`
# entirely.
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

# `start_time`/`len` are documented aliases of `initial_time`/`horizon`. This is
# the only place the two spellings are related; both the `IS.Results` row slicing
# in `_time_window_indices` and the `PSY.System` forwarding below read it.
const _WINDOW_ALIASES = (initial_time = :start_time, horizon = :len)

function _window_kwarg(kwargs, canonical::Symbol)
    return get(kwargs, canonical, get(kwargs, _WINDOW_ALIASES[canonical], nothing))
end

# `PowerAnalytics.get_load_data(::PSY.System)` reads only the canonical spellings,
# so an aliased window has to be normalized before forwarding or a `PSY.System`
# plot would silently ignore it. Returns a fresh `Dict{Symbol,Any}` regardless so
# callers can keep mutating it.
function _translate_demand_window(kwargs)
    out = Dict{Symbol, Any}(kwargs)
    for canonical in keys(_WINDOW_ALIASES)
        value = _window_kwarg(out, canonical)
        isnothing(value) || (out[canonical] = value)
    end
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
series' values sum to a net-negative total. Every rule that decides which side of
the zero axis a series belongs on — `_signed_stack_bounds`, `_series_draw_order`,
and the PlotlyLight `stackgroup` split — reads this one answer, so the three
cannot disagree.
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

# Classification is by *series* (not by value): a positive-type series always
# stacks on the positive baseline — even at timesteps where it is 0 (e.g. PV at
# night) it keeps a zero-width band *in place* rather than jumping to the
# negative baseline, which left whitespace holes and slash lines.
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
Series indices in the order a non-bar plot must draw them: series whose values
sum to a net-negative total first, then all the others, each group keeping its
original column order. Net-negative series (storage charging, source input)
stack *below* the zero axis, so drawing them first leaves the positive
generation bands and lines on top of them instead of hidden behind their fill.
"""
function _series_draw_order(negative::AbstractVector{Bool})
    return vcat(findall(negative), findall(.!negative))
end

function _series_draw_order(data::AbstractMatrix)
    return _series_draw_order(_series_is_negative(data))
end

# Old spelling of "this plot has no title". User code still passes it, so it is
# normalized to `nothing` here — the one place that knows about the sentinel.
const _NO_TITLE_SENTINEL = " "

# Base name a plot is saved under when it carries no title.
const _UNTITLED_SAVE_NAME = "dataframe"

"""
Everything a backend recipe needs to draw one call, resolved once by
`_plot_dataframe!` so that the recipes in `ext/` consume already-decided values
instead of each deriving its own defaults. Every field is canonical: `data` is
the plotted `time × series` matrix with `power_scale` already applied,
`column_labels` are the finished legend labels, `seriescolor` holds one color per
drawn series (continuing the cycle past any series already on the plot),
`series_negative` is the net-sign classification the stacking and draw-order
rules share, `nofill`/`linestyle`/`linewidth` are always filled in, `title` is
`nothing` when the plot has no title, and `save_file` is the complete path to
write or `nothing` when the plot is not being saved.
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

# `linestyle::Symbol` is the canonical spelling. `line_dash::String` was the
# PlotlyLight-only name for the same thing and is still accepted from old user
# code; folding it in here means neither recipe has to know two names exist.
function _resolve_linestyle(kwargs)
    haskey(kwargs, :linestyle) && return Symbol(kwargs[:linestyle])
    haskey(kwargs, :line_dash) && return Symbol(kwargs[:line_dash])
    return :solid
end

function _resolve_title(kwargs)
    title = get(kwargs, :title, nothing)
    if isnothing(title) || title == _NO_TITLE_SENTINEL
        return nothing
    end
    return String(title)
end

# The single place a save path is decided. Spaces in the title become
# underscores, which is what the `plot_demand`/`plot_results`/`plot_fuel`
# wrappers have always done; routing those wrappers through this helper rather
# than letting each rebuild the path is what keeps one filename convention
# across every entry point.
function _resolve_save_file(backend::PlottingBackend, title, kwargs)
    save_dir = get(kwargs, :save, nothing)
    isnothing(save_dir) && return nothing
    format = get(kwargs, :format, _default_save_format(backend))
    name = replace(something(title, _UNTITLED_SAVE_NAME), " " => "_")
    return joinpath(save_dir, "$(name).$(format)")
end

# Key word values arrive with whatever type the caller wrote (`linewidth = 3`,
# `power_scale = 1000`), so each one is converted to the field type here: the
# parametric struct's default constructor matches on the exact type and would
# otherwise reject them.
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

    # The `DateTime` column is stripped, the labels are applied and the scaling
    # is done once here; a recipe that repeated any of the three would be free to
    # repeat it differently.
    ndf = PA.no_datetime(variable)
    data = Matrix{Float64}(ndf)
    power_scale == 1.0 || (data ./= power_scale)
    label_fn = get(kwargs, :label_fn, label_short)
    column_labels = [string(label_fn(name)) for name in DataFrames.names(ndf)]

    # The color cycle continues past whatever is already drawn on `p`, so a `!`
    # call layering a second set of traces does not restart at palette entry one.
    drawn = _drawn_series_count(p, backend)
    colors = get(
        kwargs,
        :seriescolor,
        get_palette_seriescolor(backend, get(kwargs, :palette, PALETTE)),
    )
    seriescolor = set_seriescolor(colors, vcat(ones(drawn), column_labels))[(drawn + 1):end]

    step = time_range[2] - time_range[1]
    return _PlotOptions(
        bar,
        stack,
        get(kwargs, :stair, false),
        # An area fill is only meaningful under a stacked or bar plot, so a plain
        # line plot draws no fill; `_plot_fuel!` forces `true` for its net-load
        # overlay.
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
        # One hour expressed in the data's own time step: a bar plot divides its
        # summed totals by it to report energy per hour.
        Dates.Millisecond(Dates.Hour(1)) / Dates.Millisecond(step),
    )
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
# TODO upstream: fix `compute` time-window key words in PowerAnalytics
# (https://github.com/PabloBotin/PowerAnalytics.jl/issues/1), then forward
# `start_time`/`len` directly.
function _time_window_indices(time::AbstractVector, kwargs)
    start_time = _window_kwarg(kwargs, :initial_time)
    len = _window_kwarg(kwargs, :horizon)
    i0 = if isnothing(start_time)
        1
    else
        found = findfirst(==(start_time), time)
        isnothing(found) && throw(
            ArgumentError("start_time $start_time is not one of the results timestamps"),
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
- `horizon::Int64`: number of time periods to plot, counted from `initial_time` (`len` is accepted as an alias)
- `initial_time::DateTime`: To start the plot at a different time other than the results initial time (`start_time` is accepted as an alias)
- `aggregate::String = "System", "PowerLoad", or "Bus"`: aggregate the demand other than by generator. Applies ONLY to the `PSY.System` input; the `IS.Results` path always aggregates to a single "Load" trace and ignores `aggregate` entirely.
$(_COMMON_PLOT_KWARGS)
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

# Assemble the aggregated demand DataFrame (columns = demand categories, no
# DateTime column) and its time axis. Dispatching on the input type keeps the
# metrics-API and System paths separate.

# The single demand column the `IS.Results` path always produces; the fixed name
# keeps palette and label behavior identical to the old API.
const _DEMAND_COLUMN = "Load"

# Demand is read variable-first, exactly as the old `PA.get_load_data` did (it
# scanned `SUPPORTED_LOAD_VARIABLES = [ActivePowerVariable]` and only called
# `add_fixed_parameters!` for load types with no variable stored). The order is
# not cosmetic: under a controllable formulation (`PowerLoadInterruption`,
# `PowerLoadDispatch`) the variable is the *served* load, while the forecast
# parameter is the demand that was requested, and PowerSimulations stores that
# parameter with the opposite sign there — `get_multiplier_value` is
# `+max_active_power` for `AbstractControllablePowerLoadFormulation` against
# `-max_active_power` for `StaticPowerLoad`. Reading only `calc_load_forecast`
# therefore plots the wrong quantity *and* the wrong sign for dispatchable load,
# and in a mixed system the two sign conventions cancel against each other.
const _DEMAND_METRICS = (PA.Metrics.calc_active_power, PA.Metrics.calc_load_forecast)

# The pool of loads to plot: a user-supplied filter folds into the selector, and
# the default matches the built-in `all_loads` selector.
_demand_selector(::Nothing) = PSY.rebuild_selector(PA.Selectors.all_loads; groupby = :all)
_demand_selector(filter_func::Function) =
    PSY.make_selector(filter_func, PSY.ElectricLoad; groupby = :all)

# The same pool narrowed to one concrete load type, which is what the old
# pipeline keyed on too. Resolving the `_DEMAND_METRICS` fallback per type is
# required because `PowerAnalytics.compute` throws as soon as *any* component in
# a selector is missing the result, so a whole-pool call on a mixed system would
# fall every load back to the forecast and cancel the signs described above.
_demand_type_selector(::Nothing, load_type::Type{<:PSY.ElectricLoad}) =
    PSY.make_selector(load_type; groupby = :all)
_demand_type_selector(filter_func::Function, load_type::Type{<:PSY.ElectricLoad}) =
    PSY.make_selector(filter_func, load_type; groupby = :all)

# Compute one metric over one selector, returning `(time, values)` as fresh
# vectors, or `nothing` when that result is not stored for the selected
# components (the old pipeline skipped those keys silently).
function _try_selector_metric(metric, result::IS.Results, selector)
    df = try
        PA.compute(metric, result, selector)
    catch e
        _is_missing_result_error(e) && return nothing
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
    # Concrete load types present in the pool, ordered deterministically so that
    # the summation order (and the floating-point rounding it implies) is
    # reproducible.
    pool = PSY.get_components(_demand_selector(filter_func), result)
    for load_type in sort!(unique(typeof(c) for c in pool); by = nameof)
        selector = _demand_type_selector(filter_func, load_type)
        for metric in _DEMAND_METRICS
            r = _try_selector_metric(metric, result, selector)
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
    # A load type attached to the system but absent from the problem template
    # must not crash the plot: skip missing results like everywhere else and
    # fall through to the empty-data ("No load data found") path.
    isempty(time) && return (DataFrames.DataFrame(), Dates.DateTime[])

    window = _time_window_indices(time, kwargs)
    # Range indexing allocates fresh vectors, so nothing the metrics returned can
    # be mutated downstream (e.g. via `extra_load`).
    return (DataFrames.DataFrame(_DEMAND_COLUMN => total[window]), time[window])
end

# System path: the new API cannot read demand straight from a `PSY.System`, so
# this stays on the old PowerAnalytics interface, including the
# `aggregate::String` → `aggregation::Type` translation and the
# `start_time`/`len` alias normalization.
function _demand_data(system::PSY.System; kwargs...)
    kwargs = _translate_demand_aggregate(_translate_demand_window(kwargs))
    load = PA.get_load_data(system; kwargs...)
    return (PA.combine_categories(load.data), load.time)
end

# Unset key words are dropped rather than forwarded as `nothing`, because the
# window readers distinguish "absent" from "nothing": forwarding an explicit
# `initial_time = nothing` would satisfy the lookup and stop `start_time` from
# ever being consulted.
function _demand_frame(result; kwargs...)
    passed = Dict{Symbol, Any}((k, v) for (k, v) in kwargs if !isnothing(v))
    data, time = _demand_data(result; passed...)
    return DataFrames.insertcols(data, 1, PA.DATETIME_COL => time)
end

"""
    get_demand_data(results)

The demand data [`plot_demand`](@ref) draws from simulation results, as a
`DataFrame` whose first column is the `DateTime` axis and whose second is the
aggregated `"Load"` column. Use it to tabulate or post-process the same numbers
the plot shows.

Reading a single load metric instead does **not** give the same answer: under a
controllable load formulation (`PowerLoadInterruption`, `PowerLoadDispatch`) the
load forecast parameter is the *requested* demand and PowerSimulations stores it
with the opposite sign, so a forecast-only total is understated on a controllable
system and cancels itself on a mixed one. Resolving that per concrete load type
is what this function exists to encapsulate.

Results are always aggregated into a single column; use
[`get_demand_data(::PowerSystems.System)`](@ref) for the per-component breakdown
that accepts `aggregate`.

When the results hold no load data this returns a 0-row frame, where
[`plot_demand`](@ref) instead throws an `ArgumentError`. An accessor's caller can
test `nrow` and carry on; a plot with nothing to draw is a mistake worth
reporting, so the two deliberately differ.

!!! note

    The time windowing below is applied locally because `PowerAnalytics.compute`
    mishandles window key words on simulation results. That workaround is
    temporary, but this function is exported and so outlives it: if
    PowerAnalytics grows a correct load metric the internals change and the
    signature stays.

# Arguments

- `results::`[`InfrastructureSystems.Results`](@extref): results to read the demand from
    (e.g., [`PowerSimulations.SimulationProblemResults`](@extref))

# Accepted Key Words

- `horizon::Int64`: number of time periods to return, counted from `initial_time` (`len` is accepted as an alias)
- `initial_time::DateTime`: start at a time other than the results initial time (`start_time` is accepted as an alias)
- `filter_func::Function`: filter components included in the total
"""
function get_demand_data(
    results::IS.Results;
    filter_func = nothing,
    initial_time = nothing,
    start_time = nothing,
    horizon = nothing,
    len = nothing,
)
    return _demand_frame(
        results;
        filter_func = filter_func,
        initial_time = initial_time,
        start_time = start_time,
        horizon = horizon,
        len = len,
    )
end

"""
    get_demand_data(system)

The demand data [`plot_demand`](@ref) draws from a `System`, as a `DataFrame`
whose first column is the `DateTime` axis. Unlike the
[`get_demand_data(::InfrastructureSystems.Results)`](@ref) method, this one reads
the load time series rather than solved variables, so `aggregate` selects how the
columns are grouped.

# Arguments

- `system::`[`PowerSystems.System`](@extref): system to read the demand from

# Accepted Key Words

- `horizon::Int64`: number of time periods to return, counted from `initial_time` (`len` is accepted as an alias)
- `initial_time::DateTime`: start at a time other than the system initial time (`start_time` is accepted as an alias)
- `aggregate::String = "System", "PowerLoad", or "Bus"`: group the demand columns by something other than generator
- `filter_func::Function`: filter components included in the total
"""
function get_demand_data(
    system::PSY.System;
    aggregate = nothing,
    filter_func = nothing,
    initial_time = nothing,
    start_time = nothing,
    horizon = nothing,
    len = nothing,
)
    return _demand_frame(
        system;
        aggregate = aggregate,
        filter_func = filter_func,
        initial_time = initial_time,
        start_time = start_time,
        horizon = horizon,
        len = len,
    )
end

function _plot_demand!(p, result::Union{IS.Results, PSY.System}, backend; kwargs...)
    set_display = get(kwargs, :set_display, true)
    bar = get(kwargs, :bar, false)

    title_raw = get(kwargs, :title, "Demand")
    title = (isnothing(title_raw) || title_raw == _NO_TITLE_SENTINEL) ? nothing :
            String(title_raw)
    y_label = get(kwargs, :y_label, bar ? "MWh" : "MW")
    palette = get(kwargs, :palette, PALETTE)
    save_file = _resolve_save_file(backend, title, kwargs)

    load_agg, load_time = _demand_data(result; kwargs...)
    if isempty(load_agg)
        throw(ArgumentError("No load data found"))
    end
    # A splatted key word wins over an explicit one, so the key words this
    # wrapper passes itself — and acts on itself — are dropped from the splat.
    kwargs = Dict{Symbol, Any}(
        (k, v) for (k, v) in kwargs if k ∉ [:filter_func, :save, :title, :set_display]
    )
    # Optional per-timestep load added to demand (e.g. storage charging or source
    # input, so the net-load line matches the top of the generation stack in `plot_fuel!`).
    extra_load = get(kwargs, :extra_load, nothing)
    kwargs = popkwargs(kwargs, :extra_load)
    # `linestyle` is the canonical spelling for both backends (`_PlotOptions`
    # also folds in a caller-supplied `line_dash`), so it is set once here.
    kwargs[:linestyle] = _resolve_linestyle(kwargs)
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

- `linestyle::Symbol = :dash` : set line style
- `horizon::Int64`: number of time periods to plot, counted from `initial_time` (`len` is accepted as an alias)
- `initial_time::DateTime`: To start the plot at a different time other than the results initial time (`start_time` is accepted as an alias)
- `aggregate::String = "System", "PowerLoad", or "Bus"`: aggregate the demand by
    [`PowerSystems.System`](@extref), [`PowerSystems.PowerLoad`](@extref), or [`PowerSystems.Bus`](@extref),
    rather than by generator. Applies ONLY to the `PSY.System` input; the `IS.Results` path
    always aggregates to a single "Load" trace and ignores `aggregate` entirely.
$(_COMMON_PLOT_KWARGS)
- `filter_func::Function = `[`PowerSystems.get_available`](@extref PowerSystems InfrastructureSystems.get_available-Tuple{RenewableDispatch}): filter components included in plot
- `palette` : color palette from [`load_palette`](@ref)
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
- `curtailment::Bool`: plot the curtailment with the variable
$(_COMMON_PLOT_KWARGS)
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
    # A caller may hand in `nothing` to ask for a fresh plot; resolving it here
    # means the recipes can take a concrete plot type.
    isnothing(p) && (p = _empty_plot(backend))
    # Nothing downstream — labels, legend, saving — is meaningful without data,
    # so the empty case ends here rather than in each recipe.
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
- `curtailment::Bool`: plot the curtailment with the variable
$(_COMMON_PLOT_KWARGS)
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

# Split a dict of result DataFrames from its shared time axis: `DateTime`
# columns are stripped (copying) from every value and the time axis is taken
# from the first value's `DateTime` column, replicating the shape the old
# `PowerAnalytics.PowerData` constructor produced. The strip is not redundant
# with the one inside `PowerAnalytics.combine_categories`, because
# `_flatten_result_categories` emits one trace per stored column and would
# otherwise plot the `DateTime` column as a series.
function _split_results_time(results::Dict{String, DataFrames.DataFrame})
    data = Dict{String, DataFrames.DataFrame}(k => PA.no_datetime(v) for (k, v) in results)
    return (data, first(values(results)).DateTime)
end

# `PowerAnalytics.combine_categories` owns the aggregation itself: `names`
# restricts and orders the entries, `aggregate` maps each entry's `time × column`
# matrix to one column, empty entries are dropped silently, and an all-empty
# input yields an empty `DataFrame`. The only thing added here is the error for
# an unknown entry, which upstream reports as a bare `KeyError` that names
# neither the key word nor the entries that would have been valid.
function _combine_result_categories(
    data::Dict{String, DataFrames.DataFrame};
    names::Union{Vector{String}, Vector{Symbol}, Nothing} = nothing,
    aggregate::Union{Function, Nothing} = nothing,
)
    # `Vector{Symbol}` is accepted for the deprecated `plot_powerdata` path,
    # whose `PowerData` dicts were keyed by `Symbol` under the old API.
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

    p = _plot_dataframe!(p, df, time, backend; set_display = false, kwargs...)

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
$(_COMMON_PLOT_KWARGS)
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
$(_COMMON_PLOT_KWARGS)
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
- `initial_time::DateTime`: To start the plot at a different time other than the results initial time (`start_time` is accepted as an alias)
- `horizon::Int64`: number of time periods to plot, counted from `initial_time` (`len` is accepted as an alias)
$(_COMMON_PLOT_KWARGS)
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

# The `(backend, result)` positional order is part of the report template's
# contract: `report` renders a user-supplied `.jmd`, and the shipped
# `generic_report_template.jmd` has called this since before `backend` became a
# key word. Templates copied from an earlier release still call it, so removing
# it would throw `UndefVarError` on their next `report` rather than degrade.
_report_plot_fuel(backend::PlottingBackend, result; kwargs...) =
    plot_fuel(result; backend = backend, kwargs...)

# The fuel stack is assembled on the PowerAnalytics metrics/selectors API, one
# metric evaluation per component, because the old pipeline's semantics cannot
# be reproduced with whole-selector `compute` calls: components whose results
# are absent must be skipped silently, each generator needs a
# variable → parameter → aux-variable fallback chain, and categories with no
# contributing component must vanish instead of producing all-zero columns.

# TODO upstream: PowerAnalytics has no built-in metrics for these entry types
# (it should export `calc_system_slack_down` and forecast metrics for the
# storage/source time-series parameters); build them locally until then. See
# https://github.com/PabloBotin/PowerAnalytics.jl/issues/4.
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
# so it keeps its sign. Every available metric contributes: if a component ever
# had both the In/Out variable AND the time-series parameter stored, the two
# entries would double-count, but a single PSI problem assigns each component
# type exactly one formulation, so only one of the pair can produce results.
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

# `ext_category` discrimination existed only in the old mapping lookup; the
# PowerAnalytics 1.0 selector parser has no equivalent, so rules carrying it
# still match — just without the ext discrimination. Scan the raw YAML and warn
# so users of such mappings are not silently surprised.
_has_ext_category(::Any) = false
_has_ext_category(v::AbstractVector) = any(_has_ext_category, v)
function _has_ext_category(d::AbstractDict)
    return haskey(d, "ext_category") || any(_has_ext_category, values(d))
end

function _fuel_categories(file::AbstractString)
    if _has_ext_category(YAML.load_file(file))
        @warn "The generator mapping file $file contains `ext_category` keys, which " *
              "the PowerAnalytics 1.0 selector parser does not support; those rules " *
              "will match without the ext discrimination."
    end
    return PA.parse_injector_categories(file)
end

# The generator mapping file behind the category selectors. When the caller
# supplies none, `_fuel_categories` hands back `PA.Selectors.injector_categories`,
# which PowerAnalytics builds as
# `parse_injector_categories(PA.FUEL_TYPES_DATA_FILE)`
# (PowerAnalytics/src/builtin_component_selectors.jl), so that same file
# reproduces the default categories rule for rule.
_fuel_mapping_file(::Nothing) = PA.FUEL_TYPES_DATA_FILE
_fuel_mapping_file(file::AbstractString) = file

# `parse_injector_categories` and `PA.Selectors.injector_categories` both take
# PowerAnalytics' default root type, so re-deriving rule specificity has to use
# the same one or `parse_fuel_category`'s `typeintersect` lands elsewhere than it
# did when the sub-selectors were built.
const _MAPPING_ROOT_TYPE = PSY.StaticInjection

_pool_components(::Type{T}, result::IS.Results, filter_func::Function) where {T} =
    PSY.get_components(filter_func, T, result)
_pool_components(::Type{T}, result::IS.Results, ::Nothing) where {T} =
    PSY.get_components(T, result)

# The components eligible for fuel plotting: available generators, storage, and
# sources (never loads), optionally restricted by a user filter, matching the
# old `make_fuel_dictionary` iteration. The `storage`/`sources` kwargs of
# `plot_fuel` drop those roles entirely, like the old key filters did. The pool
# is deliberately heterogeneous, so its element type cannot be concrete; it is
# narrowed to the mapping's own root type rather than left at `PSY.Component`.
function _injector_pool(result::IS.Results, filter_func, storage::Bool, sources::Bool)
    pool = Vector{_MAPPING_ROOT_TYPE}()
    append!(pool, _pool_components(PSY.Generator, result, filter_func))
    storage && append!(pool, _pool_components(PSY.Storage, result, filter_func))
    sources && append!(pool, _pool_components(PSY.Source, result, filter_func))
    return pool
end

# Number of `supertype` steps from `t` up to `target`, `typemax(Int)` when `t`
# is not a subtype of it at all. The old mapping lookup compared the mapping's
# `gentype` strings against type names; matching the resolved type objects
# instead keeps bare names working (PowerAnalytics' `lookup_gentype` resolves
# them against `PowerSystems`) while telling `Foo.Thermal` apart from
# `Bar.Thermal`, which name matching cannot. `@nospecialize` keeps this to a
# single compiled method instead of one per (component type, rule type) pair.
function _type_distance(@nospecialize(t::Type), @nospecialize(target::Type))
    t <: target || return typemax(Int)
    dist = 0
    while true
        t === target && return dist
        # `target` is a subtype of `t` without appearing in its nominal chain
        # (e.g. a `Union` produced by `typeintersect`): still a match, but rank
        # it behind every rule whose type the chain does reach.
        t === Any && return typemax(Int) - 1
        t = supertype(t)
        dist += 1
    end
end

# One rule of the generator mapping: a category, the rule's specificity taken
# from the `(gentype, primemover, fuel)` triple PowerAnalytics itself parsed out
# of the mapping YAML, and its member components.
struct _FuelRule
    category::String
    gen_type::Type
    pm_wild::Bool
    fuel_wild::Bool
    members::Set{_MAPPING_ROOT_TYPE}
end

# The component type a category sub-selector filters on. PowerAnalytics builds
# every one of them via `make_selector(filter_closure, gen_type)`, i.e. as a
# `FilterComponentSelector` (PowerAnalytics/src/builtin_component_selectors.jl,
# `make_fuel_component_selector`). Anything else means the parser changed shape,
# and `Union{}` — which no surviving mapping rule can yield — makes the caller's
# correspondence check fail loudly.
_selector_component_type(selector::IS.FilterComponentSelector) = selector.component_type
_selector_component_type(::IS.ComponentSelector) = Union{}

# The `(gentype, primemover, fuel)` specificity of every rule listed under
# `category`, in the order PowerAnalytics turns them into sub-selectors.
# `parse_fuel_category` is PowerAnalytics' own parser, so the type and enum items
# here are exactly the ones baked into the corresponding sub-selector's filter,
# and rules that `make_fuel_component_selector` drops (their `gentype`
# intersected away to `Union{}` under the root type) are dropped here too.
function _mapping_rule_specs(raw_mapping::AbstractDict, category::AbstractString)
    specs = Vector{Tuple{Type, Bool, Bool}}()
    for rule in get(raw_mapping, category, ())
        gen_type, prime_mover, fuel =
            PA.parse_fuel_category(rule; root_type = _MAPPING_ROOT_TYPE)
        gen_type === Union{} && continue
        push!(specs, (gen_type, isnothing(prime_mover), isnothing(fuel)))
    end
    return specs
end

# TODO upstream: PowerAnalytics should either expose each mapping rule's
# specificity or document the one-sub-selector-per-rule ordering this replay
# depends on, so the ladder below can be deleted. Not yet filed.
#
# `parse_generator_mapping_file` broadcasts `make_fuel_component_selector` over a
# category's rule list, drops the `nothing`s, and wraps the survivors in a
# `ListComponentSelector`, whose `get_groups` returns its contents verbatim — so
# group `i` comes from surviving rule `i`. PowerAnalytics never promised that
# ordering, so cross-check it against the one thing each group independently
# carries: the component type its filter is built on. A mismatch means the
# specificity above cannot be trusted, and quietly ranking on it would sort
# components into the wrong fuel category with no other symptom.
function _validate_rule_correspondence(
    category::AbstractString,
    mapping_file::AbstractString,
    groups,
    specs::Vector{Tuple{Type, Bool, Bool}},
)
    if length(groups) == length(specs) &&
       all(_selector_component_type(g) === first(s) for (g, s) in zip(groups, specs))
        return nothing
    end
    throw(
        ErrorException(
            "Cannot recover generator-mapping rule specificity for category " *
            "\"$category\" of $mapping_file: PowerAnalytics $(pkgversion(PA)) " *
            "produced sub-selectors $([PA.get_name(g) for g in groups]) on types " *
            "$([_selector_component_type(g) for g in groups]), which do not " *
            "correspond one-to-one and in order with the parsed rule types " *
            "$([first(s) for s in specs]). PowerGraphics relies on " *
            "`parse_generator_mapping_file` emitting one sub-selector per " *
            "mapping rule, in order, to rank rules by specificity; please " *
            "report this as a PowerGraphics issue.",
        ),
    )
end

# Every mapping rule that has at least one member in `result`, paired with the
# specificity of the YAML rule that produced it.
function _fuel_rules(
    result::IS.Results,
    categories,
    mapping_file::AbstractString,
    filter_func,
)
    raw_mapping = YAML.load_file(mapping_file)
    rules = _FuelRule[]
    for (category, selector) in categories
        groups = collect(PSY.get_groups(selector, result))
        specs = _mapping_rule_specs(raw_mapping, category)
        _validate_rule_correspondence(category, mapping_file, groups, specs)
        for (group, (gen_type, pm_wild, fuel_wild)) in zip(groups, specs)
            members =
                Set{_MAPPING_ROOT_TYPE}(PSY.get_components(filter_func, group, result))
            isempty(members) && continue
            push!(rules, _FuelRule(category, gen_type, pm_wild, fuel_wild, members))
        end
    end
    return rules
end

# Rank a rule for `comp` the way the old first-match-wins ladder did: most
# specific component type first, then prime-mover-specific over wildcard, then
# fuel-specific over wildcard. Smaller ranks win.
function _rule_rank(comp::PSY.Component, rule::_FuelRule)
    return (_type_distance(typeof(comp), rule.gen_type), rule.pm_wild, rule.fuel_wild)
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
function _assign_fuel_categories(
    result::IS.Results,
    categories,
    mapping_file::AbstractString,
    pool,
    filter_func,
)
    rules = _fuel_rules(result, categories, mapping_file, filter_func)
    assignments = Dict{String, Vector{_MAPPING_ROOT_TYPE}}()
    unmatched = _MAPPING_ROOT_TYPE[]
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
                Vector{_MAPPING_ROOT_TYPE}()
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
    haskey(kwargs, :variables) &&
        @warn "The `variables` kwarg is no longer supported and is ignored; " *
              "use filter_func/generator_mapping_file instead."
    filter_func = get(kwargs, :filter_func, nothing)
    curtailment = get(kwargs, :curtailment, true)
    slacks = get(kwargs, :slacks, true)
    storage = get(kwargs, :storage, true)
    sources = get(kwargs, :sources, true)
    mapping_arg = get(kwargs, :generator_mapping_file, nothing)
    categories = _fuel_categories(mapping_arg)
    mapping_file = _fuel_mapping_file(mapping_arg)

    pool = _injector_pool(result, filter_func, storage, sources)
    assignments, unmatched =
        _assign_fuel_categories(result, categories, mapping_file, pool, filter_func)

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
    fuel_agg = DataFrames.DataFrame([
        name => acc.cols[name][window] for name in vcat(matched, remainder)
    ],)
    return (fuel_agg, acc.time[window])
end

function _plot_fuel!(p, result::IS.Results, backend; kwargs...)
    set_display = get(kwargs, :set_display, true)
    load = get(kwargs, :load, true)
    title = get(kwargs, :title, "Fuel")
    stack = get(kwargs, :stack, true)
    palette = get(kwargs, :palette, PALETTE)
    save_file = _resolve_save_file(backend, title, kwargs)
    kwargs =
        Dict{Symbol, Any}((k, v) for (k, v) in kwargs if k ∉ [:title, :save, :set_display])

    # Generation stack, assembled on the PowerAnalytics metrics/selectors API.
    fuel_agg, fuel_time = _fuel_data(result, get_palette_category(palette); kwargs...)

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
- `initial_time::DateTime`: To start the plot at a different time other than the results initial time (`start_time` is accepted as an alias)
- `horizon::Int64`: number of time periods to plot, counted from `initial_time` (`len` is accepted as an alias)
$(_COMMON_PLOT_KWARGS)
- `filter_func::Function = `[`PowerSystems.get_available`](@extref PowerSystems InfrastructureSystems.get_available-Tuple{RenewableDispatch}): filter components included in plot
- `palette` : Color palette as from [`load_palette`](@ref).
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
- `width::Union{Nothing,Int}=nothing`
- `height::Union{Nothing,Int}=nothing`
- `scale::Union{Nothing,Real}=nothing`
"""
# The 2-arg `save_plot(plot, filename)` form is defined per-backend via type
# dispatch — see `ext/plot_recipes.jl` (CairoMakie) and `ext/plotly_recipes.jl`
# (PlotlyLight).
function save_plot end
