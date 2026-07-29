# BEGIN 0.23.0 deprecations

# Shared by every deprecated `_plotly`-suffixed shim. The backend is a value —
# `src/backends.jl` already models it as one — so encoding it in the function
# name doubled the public API without buying any dispatch; the `_plotly` names
# now forward to the un-suffixed function with `backend = PlotlyLightBackend()`.
# A caller-supplied `backend` is rejected instead of silently overridden,
# because the name and the key word would then disagree about which backend to
# use, and a shim that ignored the key word would be the worse surprise.
function _plotly_suffix_backend(old::String, new::String, kwargs)
    haskey(kwargs, :backend) && throw(
        ArgumentError(
            "`$old` always renders with `PlotlyLightBackend()` and does not accept a " *
            "`backend` key word; call `$new(...; backend = ...)` instead.",
        ),
    )
    @warn "`$old` is deprecated; call `$new(...; backend = PlotlyLightBackend())` " *
          "instead. The `_plotly`-suffixed names will be removed in a future " *
          "breaking release."
    return PlotlyLightBackend()
end

function _warn_plot_powerdata_deprecated(name::String, replacement::String)
    @warn "$name(::PowerAnalytics.PowerData) is deprecated because PowerAnalytics' " *
          "PowerData predates its 1.0 metrics API; use $replacement with a " *
          "`Dict{String, DataFrame}` (or `plot_dataframe` for a single DataFrame) " *
          "instead. This method will be removed in a future breaking release."
    return
end

# Forward a `PA.PowerData` to the dict-of-DataFrames shape the `plot_results`
# pipeline consumes: keys become strings and any `DateTime` columns are
# stripped, while the time axis comes from `powerdata.time`.
function _powerdata_to_results(powerdata::PA.PowerData)
    return Dict{String, DataFrames.DataFrame}(
        string(k) => PA.no_datetime(v) for (k, v) in powerdata.data
    )
end

"""
    plot_powerdata(powerdata)

!!! warning "Deprecated"
    This method is deprecated because `PowerAnalytics.PowerData` predates the
    PowerAnalytics 1.0 metrics API. Use [`plot_results`](@ref) with a
    `Dict{String, DataFrame}` (or [`plot_dataframe`](@ref) for a single
    `DataFrame`) instead. It will be removed in a future breaking release.

Makes a plot from a `PowerAnalytics.PowerData` object by forwarding its `data`
and `time` fields to the [`plot_results`](@ref) pipeline; accepts the same key
words as [`plot_results`](@ref).

# Accepted Key Words
- `backend::PlottingBackend = CairoMakieBackend()`: plotting backend, `CairoMakieBackend()` (static png/pdf/svg) or `PlotlyLightBackend()` (interactive html). The matching backend package must be loaded with `using`.
"""
function plot_powerdata(
    powerdata::PA.PowerData;
    backend::PlottingBackend = CairoMakieBackend(),
    kwargs...,
)
    _warn_plot_powerdata_deprecated("plot_powerdata", "plot_results")
    return _plot_results!(
        _empty_plot(backend),
        _powerdata_to_results(powerdata),
        powerdata.time,
        backend;
        kwargs...,
    )
end

"""
    plot_powerdata!(plot, powerdata)

!!! warning "Deprecated"
    This method is deprecated because `PowerAnalytics.PowerData` predates the
    PowerAnalytics 1.0 metrics API. Use [`plot_results!`](@ref) with a
    `Dict{String, DataFrame}` (or [`plot_dataframe!`](@ref) for a single
    `DataFrame`) instead. It will be removed in a future breaking release.

Makes a plot from a `PowerAnalytics.PowerData` object onto an existing plot
handle by forwarding its `data` and `time` fields to the [`plot_results!`](@ref)
pipeline; accepts the same key words as [`plot_results!`](@ref).

# Accepted Key Words
- `backend::PlottingBackend = CairoMakieBackend()`: plotting backend, `CairoMakieBackend()` (static png/pdf/svg) or `PlotlyLightBackend()` (interactive html). The matching backend package must be loaded with `using`.
"""
function plot_powerdata!(
    p,
    powerdata::PA.PowerData;
    backend::PlottingBackend = CairoMakieBackend(),
    kwargs...,
)
    _warn_plot_powerdata_deprecated("plot_powerdata!", "plot_results!")
    return _plot_results!(
        p,
        _powerdata_to_results(powerdata),
        powerdata.time,
        backend;
        kwargs...,
    )
end

"""
    plot_demand_plotly(result)
    plot_demand_plotly!(plot, result)

!!! warning "Deprecated"
    Use [`plot_demand`](@ref) / [`plot_demand!`](@ref) with
    `backend = PlotlyLightBackend()` instead. The `_plotly`-suffixed names will
    be removed in a future breaking release.
"""
function plot_demand_plotly(result::Union{IS.Results, PSY.System}; kwargs...)
    backend = _plotly_suffix_backend("plot_demand_plotly", "plot_demand", kwargs)
    return plot_demand(result; backend = backend, kwargs...)
end

@doc (@doc plot_demand_plotly) function plot_demand_plotly!(
    p,
    result::Union{IS.Results, PSY.System};
    kwargs...,
)
    backend = _plotly_suffix_backend("plot_demand_plotly!", "plot_demand!", kwargs)
    return plot_demand!(p, result; backend = backend, kwargs...)
end

"""
    plot_dataframe_plotly(df)
    plot_dataframe_plotly(df, time_range)
    plot_dataframe_plotly!(plot, df)
    plot_dataframe_plotly!(plot, df, time_range)

!!! warning "Deprecated"
    Use [`plot_dataframe`](@ref) / [`plot_dataframe!`](@ref) with
    `backend = PlotlyLightBackend()` instead. The `_plotly`-suffixed names will
    be removed in a future breaking release.
"""
function plot_dataframe_plotly(df::DataFrames.DataFrame; kwargs...)
    backend = _plotly_suffix_backend("plot_dataframe_plotly", "plot_dataframe", kwargs)
    return plot_dataframe(df; backend = backend, kwargs...)
end

function plot_dataframe_plotly(
    df::DataFrames.DataFrame,
    time_range::Union{DataFrames.DataFrame, Array, StepRange};
    kwargs...,
)
    backend = _plotly_suffix_backend("plot_dataframe_plotly", "plot_dataframe", kwargs)
    return plot_dataframe(df, time_range; backend = backend, kwargs...)
end

@doc (@doc plot_dataframe_plotly) function plot_dataframe_plotly!(
    p,
    df::DataFrames.DataFrame;
    kwargs...,
)
    backend = _plotly_suffix_backend("plot_dataframe_plotly!", "plot_dataframe!", kwargs)
    return plot_dataframe!(p, df; backend = backend, kwargs...)
end

function plot_dataframe_plotly!(
    p,
    variable::DataFrames.DataFrame,
    time_range::Union{DataFrames.DataFrame, Array, StepRange};
    kwargs...,
)
    backend = _plotly_suffix_backend("plot_dataframe_plotly!", "plot_dataframe!", kwargs)
    return plot_dataframe!(p, variable, time_range; backend = backend, kwargs...)
end

"""
    plot_results_plotly(results)
    plot_results_plotly!(plot, results)

!!! warning "Deprecated"
    Use [`plot_results`](@ref) / [`plot_results!`](@ref) with
    `backend = PlotlyLightBackend()` instead. The `_plotly`-suffixed names will
    be removed in a future breaking release.
"""
function plot_results_plotly(results::Dict{String, DataFrames.DataFrame}; kwargs...)
    backend = _plotly_suffix_backend("plot_results_plotly", "plot_results", kwargs)
    return plot_results(results; backend = backend, kwargs...)
end

@doc (@doc plot_results_plotly) function plot_results_plotly!(
    p,
    results::Dict{String, DataFrames.DataFrame};
    kwargs...,
)
    backend = _plotly_suffix_backend("plot_results_plotly!", "plot_results!", kwargs)
    return plot_results!(p, results; backend = backend, kwargs...)
end

"""
    plot_fuel_plotly(result)
    plot_fuel_plotly!(plot, result)

!!! warning "Deprecated"
    Use [`plot_fuel`](@ref) / [`plot_fuel!`](@ref) with
    `backend = PlotlyLightBackend()` instead. The `_plotly`-suffixed names will
    be removed in a future breaking release.
"""
function plot_fuel_plotly(result::IS.Results; kwargs...)
    backend = _plotly_suffix_backend("plot_fuel_plotly", "plot_fuel", kwargs)
    return plot_fuel(result; backend = backend, kwargs...)
end

@doc (@doc plot_fuel_plotly) function plot_fuel_plotly!(p, result::IS.Results; kwargs...)
    backend = _plotly_suffix_backend("plot_fuel_plotly!", "plot_fuel!", kwargs)
    return plot_fuel!(p, result; backend = backend, kwargs...)
end

"""
    plot_powerdata_plotly(powerdata)
    plot_powerdata_plotly!(plot, powerdata)

!!! warning "Deprecated"
    Deprecated twice over: `PowerAnalytics.PowerData` predates the
    PowerAnalytics 1.0 metrics API, and the `_plotly` suffix has been replaced
    by the `backend` key word. Use [`plot_results`](@ref) /
    [`plot_results!`](@ref) with a `Dict{String, DataFrame}` and
    `backend = PlotlyLightBackend()` instead. These names will be removed in a
    future breaking release.
"""
function plot_powerdata_plotly(powerdata::PA.PowerData; kwargs...)
    backend = _plotly_suffix_backend("plot_powerdata_plotly", "plot_powerdata", kwargs)
    return plot_powerdata(powerdata; backend = backend, kwargs...)
end

@doc (@doc plot_powerdata_plotly) function plot_powerdata_plotly!(
    p,
    powerdata::PA.PowerData;
    kwargs...,
)
    backend = _plotly_suffix_backend("plot_powerdata_plotly!", "plot_powerdata!", kwargs)
    return plot_powerdata!(p, powerdata; backend = backend, kwargs...)
end
