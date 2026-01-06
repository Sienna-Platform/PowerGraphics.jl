# Backend system for PowerGraphics.jl
# Supports CairoMakie (default) and PlotlyJS (optional)

abstract type PlottingBackend end

struct CairoMakieBackend <: PlottingBackend end
struct PlotlyJSBackend <: PlottingBackend end
