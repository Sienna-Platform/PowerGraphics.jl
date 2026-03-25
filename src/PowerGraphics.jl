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

function _dataframe_plots_internal()
    @error "Either CairoMakie or PlotlyLight required."
end

function set_seriescolor(seriescolor::Array, vars::Array)
    color_length = length(seriescolor)
    var_length = length(vars)
    n = Int(ceil(var_length / color_length))
    colors = repeat(seriescolor, n)[1:var_length]
    return colors
end

if !(@isdefined CairoMakie) && !(@isdefined PlotlyLight)
    @warn "PowerGraphics.jl has been loaded, but neither CairoMakie nor PlotlyLight has been loaded yet. " *
    "At least one must be included for PowerGraphics to function properly. Move either import above this one " *
    "to suppress this warning."
end

end #module
