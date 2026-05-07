isdefined(Base, :__precompile__) && __precompile__()
module PowerGraphics

export load_palette
export plot_demand, plot_demand_plotly
export plot_dataframe, plot_dataframe_plotly
export plot_powerdata, plot_powerdata_plotly
export plot_results, plot_results_plotly
export plot_fuel, plot_fuel_plotly
export plot_demand!, plot_demand_plotly!
export plot_dataframe!, plot_dataframe_plotly!
export plot_powerdata!, plot_powerdata_plotly!
export plot_results!, plot_results_plotly!
export plot_fuel!, plot_fuel_plotly!
export report
export save_plot
export label_component, label_variable, label_acronym, label_first_word
export label_short, label_truncate

#I/O Imports
import Dates
import TimeSeries
import Colors
import DataFrames
import YAML
import DataStructures: OrderedDict, SortedDict
import PowerSystems
import InfrastructureSystems
import InteractiveUtils
import PowerAnalytics

const PSY = PowerSystems
const IS = InfrastructureSystems
const PA = PowerAnalytics

include("backends.jl")
include("definitions.jl")
include("label_utils.jl")
include("call_plots.jl")

# Methods for these are provided by package extensions:
#   - `_empty_plot(::PlottingBackend)` — CairoMakieExt / PlotlyLightExt
#   - `_dataframe_plots_internal(p, df, time, ::PlottingBackend; kwargs...)` — same
#   - `save_plot(plot, filename, ::PlottingBackend; kwargs...)` — same
#   - `report(results, out_path, template; kwargs...)` — WeaveExt
function report end

function _no_backend_loaded()
    throw(
        ArgumentError(
            "No plotting backend loaded. Run `using CairoMakie` or " *
            "`using PlotlyLight` before calling PowerGraphics plot functions.",
        ),
    )
end

_empty_plot(::PlottingBackend) = _no_backend_loaded()
function _dataframe_plots_internal(
    ::Any,
    ::DataFrames.DataFrame,
    ::Any,
    ::PlottingBackend;
    kwargs...,
)
    return _no_backend_loaded()
end

function set_seriescolor(seriescolor::Array, vars::Array)
    color_length = length(seriescolor)
    var_length = length(vars)
    n = Int(ceil(var_length / color_length))
    colors = repeat(seriescolor, n)[1:var_length]
    return colors
end


end #module
