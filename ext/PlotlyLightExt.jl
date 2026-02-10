module PlotlyLightExt

using PowerGraphics
using DataFrames
using PlotlyLight
using Dates
using Requires

include("plotly_recipes.jl")
include("make_report.jl")

function __init__()
    Requires.@require Weave = "44d3d7a6-8a23-5bf8-98c5-b353f8df5ec9" include(
        "make_report.jl",
    )
    @info "PlotlyLight loaded. Use plot_*_plotly() functions for interactive plots."
end

end