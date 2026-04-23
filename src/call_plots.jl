function _empty_plot()
    return _empty_plot(CairoMakieBackend())
end

function _empty_plot_plotly()
    return _empty_plot(PlotlyLightBackend())
end

function popkwargs(kwargs, kwarg)
    return Dict{Symbol, Any}((k, v) for (k, v) in kwargs if k ≠ kwarg)
end

function _make_ylabel(
    base_power::Float64;
    variable::String = "Generation",
    time::String = "",
)
    if isapprox(base_power, 1.0)
        ylabel = "$variable (MW$time)"
    elseif isapprox(base_power, 1000.0)
        ylabel = "$variable (GW$time)"
    else
        ylabel = "$variable (MW$time x$base_power)"
    end
    return ylabel
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
- `format::String = "png"`: set a different format for saving a [PlotlyJS](@extref Plots [Plotly-/-PlotlyJS](https://github.com/spencerlyon2/PlotlyJS.jl)) plot. Options include "png", "pdf" and "eps"
- `seriescolor::Array`: Set different colors for the plots
- `title::String = "Title"`: Set a title for the plots
- `stack::Bool = true`: stack plot traces
- `bar::Bool` : create bar plot
- `nofill::Bool` : force empty area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function to transform legend labels. Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`
- `legend_position::Symbol = :right`: legend placement, `:right` or `:bottom`
- `legend_font_size::Number`: override the legend label font size
- `filter_func::Function = `[`PowerSystems.get_available`](@extref PowerSystems InfrastructureSystems.get_available-Tuple{RenewableDispatch}): filter components included in plot
"""  # ^ temporary workaround for https://github.com/NREL-Sienna/PowerSystems.jl/issues/1598

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
- `format::String = "png"`: set a different format for saving a [PlotlyJS](@extref Plots [Plotly-/-PlotlyJS](https://github.com/spencerlyon2/PlotlyJS.jl)) plot. Options include "png", "pdf" and "eps"
- `seriescolor::Array`: Set different colors for the plots
- `title::String = "Title"`: Set a title for the plots
- `stack::Bool = true`: stack plot traces
- `bar::Bool` : create bar plot
- `nofill::Bool` : force empty area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function to transform legend labels. Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`
- `legend_position::Symbol = :right`: legend placement, `:right` or `:bottom`
- `legend_font_size::Number`: override the legend label font size
- `filter_func::Function = `[`PowerSystems.get_available`](@extref PowerSystems InfrastructureSystems.get_available-Tuple{RenewableDispatch}): filter components included in plot
- `palette` : color palette from [`load_palette`](@ref)
"""
function plot_demand!(p, result::Union{IS.Results, PSY.System}; kwargs...)
    set_display = get(kwargs, :set_display, true)
    save_fig = get(kwargs, :save, nothing)
    bar = get(kwargs, :bar, false)
    linestyle = get(kwargs, :linestyle, :solid)

    title = get(kwargs, :title, "Demand")
    y_label = get(kwargs, :y_label, bar ? "MWh" : "MW")
    palette = get(kwargs, :palette, PALETTE)

    load = PA.get_load_data(result; kwargs...)
    kwargs = popkwargs(kwargs, :filter_func)
    load_agg = PA.combine_categories(load.data)

    if isnothing(load_agg)
        Throw(error("No load data found"))
    end

    p = plot_dataframe!(
        p,
        load_agg,
        load.time;
        seriescolor = get(
            kwargs,
            :seriescolor,
            get_palette_seriescolor(CairoMakieBackend(), palette),
        ),
        linestyle = Symbol(linestyle),
        line_dash = string(linestyle),
        linewidth = get(kwargs, :linewidth, 1),
        y_label = y_label,
        set_display = false,
        title = title,
        kwargs...,
    )

    if set_display
        display(p.figure)
    end
    if !isnothing(save_fig)
        title = replace(title, " " => "_")
        save_plot(p, joinpath(save_fig, "$(title).png"), CairoMakieBackend(); kwargs...)
    end
    return p
end

function plot_demand_plotly!(p, result::Union{IS.Results, PSY.System}; kwargs...)
    set_display = get(kwargs, :set_display, true)
    save_fig = get(kwargs, :save, nothing)
    bar = get(kwargs, :bar, false)
    linestyle = get(kwargs, :linestyle, :solid)

    title = get(kwargs, :title, "Demand")
    y_label = get(kwargs, :y_label, bar ? "MWh" : "MW")
    palette = get(kwargs, :palette, PALETTE)

    load = PA.get_load_data(result; kwargs...)
    kwargs = popkwargs(kwargs, :filter_func)
    load_agg = PA.combine_categories(load.data)

    if isnothing(load_agg)
        Throw(error("No load data found"))
    end

    p = plot_dataframe_plotly!(
        p,
        load_agg,
        load.time;
        seriescolor = get(
            kwargs,
            :seriescolor,
            get_palette_seriescolor(PlotlyLightBackend(), palette),
        ),
        linestyle = Symbol(linestyle),
        line_dash = string(linestyle),
        linewidth = get(kwargs, :linewidth, 1),
        y_label = y_label,
        set_display = false,
        title = title,
        kwargs...,
    )

    if set_display
        display(p)
    end
    if !isnothing(save_fig)
        title = replace(title, " " => "_")
        save_plot(p, joinpath(save_fig, "$(title).png"), PlotlyLightBackend(); kwargs...)
    end
    return p
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
- `format::String = "png"`: set a different format for saving a [PlotlyJS](@extref Plots [Plotly-/-PlotlyJS](https://github.com/spencerlyon2/PlotlyJS.jl)) plot. Options include "png", "pdf" and "eps"
- `seriescolor::Array`: Set different colors for the plots
- `title::String = "Title"`: Set a title for the plots
- `stack::Bool = true`: stack plot traces
- `bar::Bool` : create bar plot
- `nofill::Bool` : force empty area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function to transform legend labels. Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`
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
- `format::String = "png"`: set a different format for saving a [PlotlyJS](@extref Plots [Plotly-/-PlotlyJS](https://github.com/spencerlyon2/PlotlyJS.jl)) plot. Options include "png", "pdf" and "eps"
- `seriescolor::Array`: Set different colors for the plots
- `title::String = "Title"`: Set a title for the plots
- `stack::Bool = true`: stack plot traces
- `bar::Bool` : create bar plot
- `nofill::Bool` : force empty area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function to transform legend labels. Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`
- `legend_position::Symbol = :right`: legend placement, `:right` or `:bottom`
- `legend_font_size::Number`: override the legend label font size
"""
function plot_dataframe!(p, df::DataFrames.DataFrame; kwargs...)
    return plot_dataframe!(p, PA.no_datetime(df), df.DateTime; kwargs...)
end

function plot_dataframe!(
    p,
    variable::DataFrames.DataFrame,
    time_range::Union{DataFrames.DataFrame, Array, StepRange};
    kwargs...,
)
    time_range =
        typeof(time_range) == DataFrames.DataFrame ? time_range[:, 1] : collect(time_range)
    p = _dataframe_plots_internal(p, variable, time_range, CairoMakieBackend(); kwargs...)
    return p
end

function plot_dataframe_plotly!(p, df::DataFrames.DataFrame; kwargs...)
    return plot_dataframe_plotly!(p, PA.no_datetime(df), df.DateTime; kwargs...)
end

function plot_dataframe_plotly!(
    p,
    variable::DataFrames.DataFrame,
    time_range::Union{DataFrames.DataFrame, Array, StepRange};
    kwargs...,
)
    time_range =
        typeof(time_range) == DataFrames.DataFrame ? time_range[:, 1] : collect(time_range)
    p = _dataframe_plots_internal(p, variable, time_range, PlotlyLightBackend(); kwargs...)
    return p
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
- `format::String = "png"`: set a different format for saving a [PlotlyJS](@extref Plots [Plotly-/-PlotlyJS](https://github.com/spencerlyon2/PlotlyJS.jl)) plot. Options include "png", "pdf" and "eps"
- `seriescolor::Array`: Set different colors for the plots
- `title::String = "Title"`: Set a title for the plots
- `stack::Bool = true`: stack plot traces
- `bar::Bool` : create bar plot
- `nofill::Bool` : force empty area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function to transform legend labels. Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`
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
- `format::String = "png"`: set a different format for saving a [PlotlyJS](@extref Plots [Plotly-/-PlotlyJS](https://github.com/spencerlyon2/PlotlyJS.jl)) plot. Options include "png", "pdf" and "eps"
- `seriescolor::Array`: Set different colors for the plots
- `title::String = "Title"`: Set a title for the plots
- `stack::Bool = true`: stack plot traces
- `bar::Bool` : create bar plot
- `nofill::Bool` : force empty area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function to transform legend labels. Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`
- `legend_position::Symbol = :right`: legend placement, `:right` or `:bottom`
- `legend_font_size::Number`: override the legend label font size
"""
function plot_powerdata!(p, powerdata::PA.PowerData; kwargs...)
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

    p = plot_dataframe!(p, data, powerdata.time; set_display = false, kwargs...)

    if set_display
        display(p.figure)
    end
    if !isnothing(save_fig)
        title = replace(title, " " => "_")
        format = get(kwargs, :format, "png")
        save_plot(p, joinpath(save_fig, "$title.$format"), CairoMakieBackend(); kwargs...)
    end
    return p
end

function plot_powerdata_plotly!(p, powerdata::PA.PowerData; kwargs...)
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

    p = plot_dataframe_plotly!(p, data, powerdata.time; set_display = false, kwargs...)

    if set_display
        display(p)
    end
    if !isnothing(save_fig)
        title = replace(title, " " => "_")
        format = get(kwargs, :format, "png")
        save_plot(p, joinpath(save_fig, "$title.$format"), PlotlyLightBackend(); kwargs...)
    end
    return p
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
- `format::String = "png"`: set a different format for saving a [PlotlyJS](@extref Plots [Plotly-/-PlotlyJS](https://github.com/spencerlyon2/PlotlyJS.jl)) plot. Options include "png", "pdf" and "eps"
- `seriescolor::Array`: Set different colors for the plots
- `title::String = "Title"`: Set a title for the plots
- `stack::Bool = true`: stack plot traces
- `bar::Bool` : create bar plot
- `nofill::Bool` : force empty area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function to transform legend labels. Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`
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
- `format::String = "png"`: set a different format for saving a [PlotlyJS](@extref Plots [Plotly-/-PlotlyJS](https://github.com/spencerlyon2/PlotlyJS.jl)) plot. Options include "png", "pdf" and "eps"
- `seriescolor::Array`: Set different colors for the plots
- `title::String = "Title"`: Set a title for the plots
- `stack::Bool = true`: stack plot traces
- `bar::Bool` : create bar plot
- `nofill::Bool` : force empty area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function to transform legend labels. Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`
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
- `format::String = "png"`: set a different format for saving a [PlotlyJS](@extref Plots [Plotly-/-PlotlyJS](https://github.com/spencerlyon2/PlotlyJS.jl)) plot. Options include "png", "pdf" and "eps"
- `seriescolor::Array`: Set different colors for the plots
- `title::String = "Title"`: Set a title for the plots
- `stack::Bool = true`: stack plot traces
- `bar::Bool` : create bar plot
- `nofill::Bool` : force empty area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function to transform legend labels. Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`
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
- `format::String = "png"`: set a different format for saving a [PlotlyJS](@extref Plots [Plotly-/-PlotlyJS](https://github.com/spencerlyon2/PlotlyJS.jl)) plot. Options include "png", "pdf" and "eps"
- `seriescolor::Array`: Set different colors for the plots
- `title::String = "Title"`: Set a title for the plots
- `stack::Bool = true`: stack plot traces
- `bar::Bool` : create bar plot
- `nofill::Bool` : force empty area fill
- `stair::Bool`: Make a stair plot instead of a stack plot
- `label_fn::Function = label_short`: function to transform legend labels. Built-in options: `label_short`, `label_component`, `label_variable`, `label_acronym`, `label_first_word`, `label_truncate(n)`
- `legend_position::Symbol = :right`: legend placement, `:right` or `:bottom`
- `legend_font_size::Number`: override the legend label font size
- `filter_func::Function = `[`PowerSystems.get_available`](@extref PowerSystems InfrastructureSystems.get_available-Tuple{RenewableDispatch}): filter components included in plot
- `palette` : Color palette as from [`load_palette`](@ref).
"""
function plot_fuel!(p, result::IS.Results; kwargs...)
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
        throw(error("No System data present: please run `set_system!(results, sys)`"))
    end
    cat = PA.make_fuel_dictionary(sys; kwargs...)
    fuel = PA.categorize_data(gen.data, cat; curtailment = curtailment, slacks = slacks)

    filter_func = get(kwargs, :filter_func, PSY.get_available)
    kwargs = popkwargs(kwargs, :filter_func)

    # passing names here enforces order; append any fuel categories not in the palette
    palette_categories = get_palette_category(palette)
    matched = intersect(palette_categories, keys(fuel))
    unmatched = setdiff(keys(fuel), palette_categories)
    fuel_agg = PA.combine_categories(
        fuel;
        names = vcat(matched, sort(collect(unmatched))),
    )
    y_label = get(kwargs, :y_label, bar ? "MWh" : "MW")

    seriescolor =
        get(
            kwargs,
            :seriescolor,
            match_fuel_colors(fuel_agg, CairoMakieBackend(); palette = palette),
        )
    p = plot_dataframe!(
        p,
        fuel_agg,
        gen.time;
        stack = stack,
        seriescolor = seriescolor,
        y_label = y_label,
        title = title,
        set_display = false,
        kwargs...,
    )

    kwargs = popkwargs(popkwargs(kwargs, :nofill), :seriescolor)

    kwargs[:linestyle] = get(kwargs, :linestyle, :dash)
    kwargs[:linewidth] = get(kwargs, :linewidth, 3)
    kwargs[:filter_func] = filter_func

    if load
        # load line
        p = plot_demand!(
            p,
            result;
            nofill = true,
            title = title,
            y_label = y_label,
            set_display = false,
            stack = stack,
            seriescolor = ["black"],
            kwargs...,
        )
    end

    # service stack
    # TODO: how to display this?

    if set_display
        display(p.figure)
    end
    if !isnothing(save_fig)
        title = replace(title, " " => "_")
        format = get(kwargs, :format, "png")
        save_plot(p, joinpath(save_fig, "$title.$format"), CairoMakieBackend(); kwargs...)
    end
    return p
end

function plot_fuel_plotly!(p, result::IS.Results; kwargs...)
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
        throw(error("No System data present: please run `set_system!(results, sys)`"))
    end
    cat = PA.make_fuel_dictionary(sys; kwargs...)
    fuel = PA.categorize_data(gen.data, cat; curtailment = curtailment, slacks = slacks)

    filter_func = get(kwargs, :filter_func, PSY.get_available)
    kwargs = popkwargs(kwargs, :filter_func)

    # passing names here enforces order; append any fuel categories not in the palette
    palette_categories = get_palette_category(palette)
    matched = intersect(palette_categories, keys(fuel))
    unmatched = setdiff(keys(fuel), palette_categories)
    fuel_agg = PA.combine_categories(
        fuel;
        names = vcat(matched, sort(collect(unmatched))),
    )
    y_label = get(kwargs, :y_label, bar ? "MWh" : "MW")

    seriescolor =
        get(
            kwargs,
            :seriescolor,
            match_fuel_colors(fuel_agg, PlotlyLightBackend(); palette = palette),
        )
    p = plot_dataframe_plotly!(
        p,
        fuel_agg,
        gen.time;
        stack = stack,
        seriescolor = seriescolor,
        y_label = y_label,
        title = title,
        set_display = false,
        kwargs...,
    )

    kwargs = popkwargs(popkwargs(kwargs, :nofill), :seriescolor)

    kwargs[:linestyle] = get(kwargs, :linestyle, :dash)
    kwargs[:linewidth] = get(kwargs, :linewidth, 3)
    kwargs[:filter_func] = filter_func

    if load
        # load line
        p = plot_demand_plotly!(
            p,
            result;
            nofill = true,
            title = title,
            y_label = y_label,
            set_display = false,
            stack = stack,
            seriescolor = ["black"],
            kwargs...,
        )
    end

    # service stack
    # TODO: how to display this?

    if set_display
        display(p)
    end
    if !isnothing(save_fig)
        title = replace(title, " " => "_")
        format = get(kwargs, :format, "png")
        save_plot(p, joinpath(save_fig, "$title.$format"), PlotlyLightBackend(); kwargs...)
    end
    return p
end

"""
    save_plot(plot, filename)

Saves plot to specified filename

# Arguments

- `plot`: plot object
- `filename::String` : save to filename

# Example

```julia
res = solve_op_problem!(OpProblem)
plot = plot_fuel(res)
save_plot(plot, "my_plot.png")
```

# Accepted Key Words (currently only implemented for [PlotlyJS](@extref Plots [Plotly-/-PlotlyJS](https://github.com/spencerlyon2/PlotlyJS.jl)) backend)
- `width::Union{Nothing,Int}=nothing`
- `height::Union{Nothing,Int}=nothing`
- `scale::Union{Nothing,Real}=nothing`
"""
function save_plot(plot, filename::String; kwargs...)
    return save_plot(plot, filename, CairoMakieBackend(); kwargs...)
end

# For PlotlyJS plots (no specific type, handled generically)
function save_plot_plotly(plot, filename::String; kwargs...)
    return save_plot(plot, filename, PlotlyLightBackend(); kwargs...)
end
