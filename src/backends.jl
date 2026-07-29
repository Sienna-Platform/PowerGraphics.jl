# Backend system for PowerGraphics.jl
# Supports CairoMakie (default) and PlotlyLight (optional)

"""
Supertype of the plotting backends. A backend is a *value*, not a function name:
every `plot_*` function takes it as a `backend` key word and selects the drawing
code by dispatch on the concrete subtype.

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

# File extension used when the caller does not pass `format`; an explicit user
# `format` still wins. See the Backend Parity Contract for why it is dispatched.
_default_save_format(::CairoMakieBackend) = "png"
_default_save_format(::PlotlyLightBackend) = "html"
