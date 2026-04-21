isdefined(Base, :__precompile__) && __precompile__()
@info "PowerGraphics.jl loads Plots.jl. Precompile might take a while"
module PowerGraphics

export load_palette
export plot_demand
export plot_dataframe
export plot_powerdata
export plot_results
export plot_fuel
export plot_demand!
export plot_dataframe!
export plot_powerdata!
export plot_results!
export plot_fuel!
export report
export save_plot

#I/O Imports
import Dates
import TimeSeries
import Reexport
import Requires
import Colors
import DataFrames
import YAML
Reexport.@reexport using Plots
import DataStructures: OrderedDict, SortedDict
import PowerSystems as PSY
import InfrastructureSystems as IS
import InteractiveUtils
import PowerAnalytics as PA

include("definitions.jl")
include("plot_recipes.jl")
include("plotly_recipes.jl")
include("make_report.jl")
include("call_plots.jl")

function __init__()
    Requires.@require Weave = "44d3d7a6-8a23-5bf8-98c5-b353f8df5ec9" include(
        "make_report.jl",
    )
end

end #module
