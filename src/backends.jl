# Backend system for PowerGraphics.jl
# Supports CairoMakie (default) and PlotlyLight (optional)

"""
Supertype of the plotting backends, passed to every `plot_*` function as the
`backend` key word.

Subtypes: [`CairoMakieBackend`](@ref), [`PlotlyLightBackend`](@ref).
"""
abstract type PlottingBackend end

"""
Render with [CairoMakie](https://docs.makie.org/stable/) — static,
publication-quality plots saved as `png`, `pdf`, or `svg`. This is the default
`backend` of every `plot_*` function. Requires `using CairoMakie`.
"""
struct CairoMakieBackend <: PlottingBackend end

"""
Render with [PlotlyLight](https://github.com/JuliaComputing/PlotlyLight.jl) —
lightweight interactive plots saved as `html`. Pass it as
`backend = PlotlyLightBackend()`. Requires `using PlotlyLight`.
"""
struct PlotlyLightBackend <: PlottingBackend end

# Default file extension when `format` is not passed.
_default_save_format(::CairoMakieBackend) = "png"
_default_save_format(::PlotlyLightBackend) = "html"
