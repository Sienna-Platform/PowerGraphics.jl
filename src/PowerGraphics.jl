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

using DocStringExtensions

@template (FUNCTIONS, METHODS) = """
                                 $(TYPEDSIGNATURES)
                                 $(DOCSTRING)
                                 """

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
"""
Generate a Weave report (PDF or HTML) from simulation results.

Uses [Weave.jl](https://weavejl.mpastell.com/stable/) with a Julia markdown
(`.jmd`) template. An example template is available
[here](https://github.com/Sienna-Platform/PowerGraphics.jl/blob/main/report_templates/generic_report_template.jmd).

Requires `using Weave` so the WeaveExt package extension is loaded.

# Arguments
- `res`: an [`InfrastructureSystems.Results`](@extref) object
- `out_path::String`: directory for the generated report
- `design_template::String`: path to the `.jmd` report design

# Keyword Arguments
- `doctype::String = "md2pdf"`: Weave output type (`"md2pdf"` or `"md2html"`)
- `backend::PlottingBackend = CairoMakieBackend()`: plotting backend for figures in the report

# Example
```julia
report(results, out_path, template)
```
"""
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
