isdefined(Base, :__precompile__) && __precompile__()
module PowerGraphics

export load_palette
export PlottingBackend, CairoMakieBackend, PlotlyLightBackend
export plot_demand, plot_demand!
export plot_dataframe, plot_dataframe!
export plot_results, plot_results!
export plot_fuel, plot_fuel!
export report
export save_plot
export label_component, label_variable, label_acronym, label_first_word
export label_short, label_truncate

# Deprecated exports — kept so existing user code keeps working. The `_plotly`
# suffix has been replaced by the `backend` key word, and the `plot_powerdata`
# family by `plot_results`/`plot_dataframe`; see `src/deprecated.jl`.
export plot_powerdata, plot_powerdata!
export plot_demand_plotly, plot_demand_plotly!
export plot_dataframe_plotly, plot_dataframe_plotly!
export plot_results_plotly, plot_results_plotly!
export plot_fuel_plotly, plot_fuel_plotly!
export plot_powerdata_plotly, plot_powerdata_plotly!

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
include("deprecated.jl")

# Methods for these are provided by package extensions:
#   - `_empty_plot(::PlottingBackend)` — CairoMakieExt / PlotlyLightExt
#   - `_dataframe_plots_internal(p, df, time, ::PlottingBackend, ::_PlotOptions; kwargs...)` — same
#   - `save_plot(plot, filename, ::PlottingBackend; kwargs...)` — same
#   - `report(results, out_path, template; kwargs...)` — WeaveExt
function report end

# Each stub names the package that its own backend needs, because `backend`
# defaults to `CairoMakieBackend()`: a user who loaded only PlotlyLight reaches
# the CairoMakie stub without having asked for CairoMakie, so a message naming
# both packages would point at the wrong remedy. The default backend's message
# also names the key word that selects the other one.
function _no_backend_loaded(::CairoMakieBackend)
    throw(
        ArgumentError(
            "CairoMakie is not loaded. Run `using CairoMakie` before calling " *
            "PowerGraphics plot functions, or pass `backend = PlotlyLightBackend()` " *
            "to plot with PlotlyLight instead.",
        ),
    )
end

function _no_backend_loaded(::PlotlyLightBackend)
    throw(
        ArgumentError(
            "PlotlyLight is not loaded. Run `using PlotlyLight` before calling " *
            "PowerGraphics plot functions with `backend = PlotlyLightBackend()`.",
        ),
    )
end

_empty_plot(backend::PlottingBackend) = _no_backend_loaded(backend)
function _dataframe_plots_internal(
    ::Any,
    ::DataFrames.DataFrame,
    ::Any,
    backend::PlottingBackend,
    ::_PlotOptions;
    kwargs...,
)
    return _no_backend_loaded(backend)
end

function set_seriescolor(seriescolor::Array, vars::Array)
    color_length = length(seriescolor)
    var_length = length(vars)
    n = Int(ceil(var_length / color_length))
    colors = repeat(seriescolor, n)[1:var_length]
    return colors
end

const _CAIROMAKIE_PKGID =
    Base.PkgId(Base.UUID("13f3f980-e62b-5c42-98c6-ff1f3baf88f0"), "CairoMakie")
const _PLOTLYLIGHT_PKGID =
    Base.PkgId(Base.UUID("ca7969ec-10b3-423e-8d99-40f33abb42bf"), "PlotlyLight")

function __init__()
    has_makie = haskey(Base.loaded_modules, _CAIROMAKIE_PKGID)
    has_plotly = haskey(Base.loaded_modules, _PLOTLYLIGHT_PKGID)
    if !(has_makie || has_plotly)
        @warn "PowerGraphics: no plotting backend loaded. Run " *
              "`using CairoMakie` or `using PlotlyLight` before calling " *
              "PowerGraphics plot functions."
    end
end

end #module
