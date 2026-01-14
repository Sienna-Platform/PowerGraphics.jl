# Backend system for PowerGraphics.jl
# Supports CairoMakie (default) and PlotlyLight (optional)

abstract type PlottingBackend end

struct CairoMakieBackend <: PlottingBackend end
struct PlotlyLightBackend <: PlottingBackend end
