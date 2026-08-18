##################### Data assembly helpers for call_plots.jl ######################
# These helpers bridge PowerGraphics' plot-orchestration layer onto PowerAnalytics'
# metrics API (`PA.compute` over `ComponentSelector`s). Anything here is a PowerGraphics
# concern that the metrics framework does not itself provide.

################################# Source system lookup ##############################

_source_system(sys::PSY.System) = sys

function _source_system(result::IS.Outputs)
    sys = IS.get_source_data(result)
    isnothing(sys) && throw(
        ArgumentError(
            "No System data present: please run `set_source_data!(results, sys)`",
        ),
    )
    return sys
end

_has_loads(sys::PSY.System) =
    !isempty(PSY.get_components(PSY.get_available, PSY.ElectricLoad, sys))

############################### Demand (plot_demand) #################################

# `IS.Outputs` have solved results, so the demand is the load forecast that was fed into
# the model, read through PowerAnalytics' metrics API.
function _demand_dataframe(result::IS.Outputs, kwargs)
    filter_func = get(kwargs, :filter_func, PSY.get_available)
    selector = PA.make_selector(filter_func, PSY.ElectricLoad; groupby = :all)
    return PA.compute(
        PA.Metrics.calc_load_forecast,
        result,
        selector;
        start_time = get(kwargs, :initial_time, nothing),
        len = get(kwargs, :horizon, nothing),
    )
end

# A bare `PSY.System` has no solved outputs for PowerAnalytics to read, so there is no
# `PA.compute` path for it (every `IS.Outputs` subtype in the stack wraps an actually
# built/solved optimization problem). The demand there comes straight from the loads'
# own forecast time series.
_demand_dataframe(sys::PSY.System, kwargs) = _system_demand_dataframe(sys, kwargs)

# Groups of loads to sum per output column, keyed by the user-facing `aggregate` kwarg
# (translated to a type by `_aggregate_to_type`).
function _demand_aggregation_groups(sys::PSY.System, ::Type{PSY.System}, filter_func)
    return [("System", collect(PSY.get_components(filter_func, PSY.StaticLoad, sys)))]
end

function _demand_aggregation_groups(sys::PSY.System, ::Type{PSY.ACBus}, filter_func)
    return [
        (
            PSY.get_name(bus),
            [
                load for load in PSY.get_components(filter_func, PSY.StaticLoad, sys) if
                PSY.get_bus(load) == bus
            ],
        ) for bus in PSY.get_components(PSY.get_available, PSY.ACBus, sys)
    ]
end

function _demand_aggregation_groups(sys::PSY.System, ::Type{PSY.PowerLoad}, filter_func)
    return [
        (PSY.get_name(load), [load]) for
        load in PSY.get_components(filter_func, PSY.PowerLoad, sys)
    ]
end

# The resolution of the loads' `max_active_power` forecast, erroring on a mismatch rather
# than silently picking one.
function _load_forecast_resolution(loads)
    resolution = nothing
    for load in loads
        for key in PSY.get_time_series_keys(load)
            (
                IS.get_time_series_type(key) <: PSY.AbstractDeterministic &&
                IS.get_name(key) == "max_active_power"
            ) || continue
            if isnothing(resolution)
                resolution = IS.get_resolution(key)
            elseif resolution != IS.get_resolution(key)
                throw(ErrorException("Load time series have mismatched resolutions"))
            end
            break
        end
    end
    isnothing(resolution) && throw(ErrorException("No load data found"))
    return resolution
end

# `horizon` is either a `Dates.Period` (the default, from `PSY.get_forecast_horizon`) or a
# caller-supplied step count; convert the former to a step count, pass the latter through.
_resolve_len(horizon::Dates.Period, resolution) = Int64(horizon / resolution)
_resolve_len(horizon::Integer, resolution) = horizon

function _system_demand_dataframe(sys::PSY.System, kwargs)
    filter_func = get(kwargs, :filter_func, PSY.get_available)
    aggregation = get(kwargs, :aggregation, PSY.System)
    groups = _demand_aggregation_groups(sys, aggregation, filter_func)
    groups = [(name, loads) for (name, loads) in groups if !isempty(loads)]
    isempty(groups) &&
        throw(ArgumentError("System does not have loads of type $aggregation."))

    horizon = get(kwargs, :horizon, PSY.get_forecast_horizon(sys))
    initial_time = get(kwargs, :initial_time, PSY.get_forecast_initial_timestamp(sys))
    resolution = _load_forecast_resolution(reduce(vcat, last.(groups)))
    len = _resolve_len(horizon, resolution)

    time_vec = collect(range(initial_time; step = resolution, length = len))
    df = DataFrames.DataFrame(PA.DATETIME_COL => time_vec)
    for (name, loads) in groups
        total = zeros(len)
        for load in loads
            total .+= PSY.get_time_series_values(
                PSY.Deterministic,
                load,
                "max_active_power";
                start_time = initial_time,
                len = len,
            )
        end
        df[!, name] = total
    end
    return df
end

########################### plot_results combine helper ##############################

"""
Merge a `Dict{String, DataFrame}` into one wide `DataFrame`: one output column per
dictionary key, formed by summing that key's data columns row-wise. `names`, if given,
fixes the column order (and restricts the output to just those keys); otherwise every key
of `data` is included, in dictionary order. The time axis is read from the `DATETIME_COL`
of the first frame in `data`.

The private counterpart of the metrics framework's `PA.compute` for the one case that
framework does not cover: a plain, user-supplied `Dict{String, DataFrame}` with no
`ComponentSelector` involved (see [`plot_results`](@ref)).
"""
function _combine_categories(
    data::Dict{String, DataFrames.DataFrame};
    names::Union{AbstractVector, Nothing} = nothing,
)
    isempty(data) && throw(ArgumentError("No results to combine"))
    keep_names = string.(something(names, collect(keys(data))))
    time_vec = PA.get_time_vec(first(values(data)))
    combined = DataFrames.DataFrame(PA.DATETIME_COL => time_vec)
    for k in keep_names
        haskey(data, k) || throw(ArgumentError("$k not found in results"))
        combined[!, k] = vec(sum(Matrix(PA.get_data_df(data[k])); dims = 2))
    end
    return combined
end

"""
Rebuild `selector` so it resolves to exactly one group, so a `compute` call over it can
feed `PA.get_data_vec` (which errors on more than one data column). A
`SingularComponentSelector` already resolves to one group and has no `groupby` field to
rebuild, so it is returned unchanged; anything else gets `groupby = :all`.
"""
_single_group_selector(selector::PSY.SingularComponentSelector) = selector
_single_group_selector(selector::PSY.ComponentSelector) =
    PA.rebuild_selector(selector; groupby = :all)

######################## plot_fuel generator category selector #######################

"""
The `ComponentSelector` naming the generator categories `plot_fuel` stacks: the built-in
`PA.Selectors.categorized_generators`, or a fresh selector parsed from a
`generator_mapping_file` override.
"""
function _categorized_generator_selector(kwargs)
    mapping_file = get(kwargs, :generator_mapping_file, nothing)
    if isnothing(mapping_file)
        selector = PA.Selectors.categorized_generators
    else
        categories = PA.parse_generator_categories(mapping_file)
        isnothing(categories) && throw(
            ArgumentError(
                "$mapping_file defines no generator categories (missing a " *
                "`non_generators` entry in its `__META` block?)",
            ),
        )
        selector = PA.make_selector(values(categories)...)
    end
    isnothing(selector) &&
        throw(ErrorException("No generator categories available to plot"))
    return selector
end

##################### plot_fuel curtailment selector #####################

# `PA.Metrics.calc_curtailment` reads each component's `max_active_power` forecast
# (`IOM.ActivePowerTimeSeriesParameter`) to compare against its solved output. Generators
# dispatched off a fixed rating (most thermal units) carry no such forecast at all, so
# `compute`-ing curtailment over the full `categorized_generators` selector throws
# (`InvalidValue: keys are not stored`) instead of reporting zero. Scope curtailment to the
# generators that actually have the forecast to compare against.
_has_active_power_forecast(comp::PSY.Generator) =
    PSY.has_time_series(comp, PSY.Deterministic, "max_active_power")

"""
The `ComponentSelector` naming the generators `plot_fuel`'s curtailment column sums:
`PSY.Generator`s that carry a `max_active_power` forecast to compare their solved output
against (renewables, run-of-river hydro, ...). Generators with no such forecast (fixed
thermal ratings) are excluded rather than raising an error for a metric that was never
meaningful for them.
"""
_curtailable_selector() = PA.make_selector(
    _has_active_power_forecast,
    PSY.Generator;
    groupby = :all,
    name = "Curtailable",
)
