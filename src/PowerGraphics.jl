isdefined(Base, :__precompile__) && __precompile__()
@info "PowerGraphics.jl loads CairoMakie. Precompile might take a while"
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
export backend, backend!, cairomakie, plotlyjs
export CairoMakieBackend, PlotlyJSBackend

#I/O Imports
import Dates
import TimeSeries
import Requires
import Colors
import DataFrames
import YAML
import CairoMakie
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
include("plot_recipes.jl")
include("plotly_recipes.jl")
include("make_report.jl")
include("call_plots.jl")

function __init__()
    Requires.@require Weave = "44d3d7a6-8a23-5bf8-98c5-b353f8df5ec9" include(
        "make_report.jl",
    )
    Requires.@require PlotlyJS = "f0f68f2c-4968-5e81-91da-67840de0976a" begin
        @info "PlotlyJS backend loaded. Use plotlyjs() to switch to it."
    end
end

end #module
