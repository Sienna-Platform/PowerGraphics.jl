# BEGIN 0.23.0 deprecations

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
    plot_powerdata_plotly(powerdata)

!!! warning "Deprecated"
    These methods are deprecated because `PowerAnalytics.PowerData` predates the
    PowerAnalytics 1.0 metrics API. Use [`plot_results`](@ref) with a
    `Dict{String, DataFrame}` (or [`plot_dataframe`](@ref) for a single
    `DataFrame`) instead. They will be removed in a future breaking release.

Makes a plot from a `PowerAnalytics.PowerData` object by forwarding its `data`
and `time` fields to the [`plot_results`](@ref) pipeline; accepts the same key
words as [`plot_results`](@ref).
"""
function plot_powerdata(powerdata::PA.PowerData; kwargs...)
    _warn_plot_powerdata_deprecated("plot_powerdata", "plot_results")
    return _plot_results!(
        _empty_plot(),
        _powerdata_to_results(powerdata),
        powerdata.time,
        CairoMakieBackend();
        kwargs...,
    )
end

@doc (@doc plot_powerdata) function plot_powerdata_plotly(
    powerdata::PA.PowerData;
    kwargs...,
)
    _warn_plot_powerdata_deprecated("plot_powerdata_plotly", "plot_results_plotly")
    return _plot_results!(
        _empty_plot_plotly(),
        _powerdata_to_results(powerdata),
        powerdata.time,
        PlotlyLightBackend();
        kwargs...,
    )
end

"""
    plot_powerdata!(plot, powerdata)
    plot_powerdata_plotly!(plot, powerdata)

!!! warning "Deprecated"
    These methods are deprecated because `PowerAnalytics.PowerData` predates the
    PowerAnalytics 1.0 metrics API. Use [`plot_results!`](@ref) with a
    `Dict{String, DataFrame}` (or [`plot_dataframe!`](@ref) for a single
    `DataFrame`) instead. They will be removed in a future breaking release.

Makes a plot from a `PowerAnalytics.PowerData` object onto an existing plot
handle by forwarding its `data` and `time` fields to the [`plot_results!`](@ref)
pipeline; accepts the same key words as [`plot_results!`](@ref).
"""
function plot_powerdata!(p, powerdata::PA.PowerData; kwargs...)
    _warn_plot_powerdata_deprecated("plot_powerdata!", "plot_results!")
    return _plot_results!(
        p,
        _powerdata_to_results(powerdata),
        powerdata.time,
        CairoMakieBackend();
        kwargs...,
    )
end

@doc (@doc plot_powerdata!) function plot_powerdata_plotly!(
    p,
    powerdata::PA.PowerData;
    kwargs...,
)
    _warn_plot_powerdata_deprecated("plot_powerdata_plotly!", "plot_results_plotly!")
    return _plot_results!(
        p,
        _powerdata_to_results(powerdata),
        powerdata.time,
        PlotlyLightBackend();
        kwargs...,
    )
end
