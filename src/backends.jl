# Backend system for PowerGraphics.jl
# Supports CairoMakie (default) and PlotlyJS (optional, loaded via Requires)

abstract type PlottingBackend end

struct CairoMakieBackend <: PlottingBackend end
struct PlotlyJSBackend <: PlottingBackend end

# Global backend state
const CURRENT_BACKEND = Ref{PlottingBackend}(CairoMakieBackend())

"""
    backend()

Returns the current plotting backend.
"""
function backend()
    return CURRENT_BACKEND[]
end

"""
    backend!(b::PlottingBackend)

Sets the current plotting backend to `b`.

# Arguments
- `b::PlottingBackend`: The backend to use. Can be `CairoMakieBackend()` or `PlotlyJSBackend()`

# Example
```julia
# Use CairoMakie for static plots (default)
backend!(CairoMakieBackend())

# Use PlotlyJS for interactive plots (requires PlotlyJS to be loaded)
using PlotlyJS
backend!(PlotlyJSBackend())
```
"""
function backend!(b::PlottingBackend)
    CURRENT_BACKEND[] = b
    return b
end

"""
    cairomakie()

Set the backend to CairoMakie for static plots.
"""
function cairomakie()
    backend!(CairoMakieBackend())
end

"""
    plotlyjs()

Set the backend to PlotlyJS for interactive plots.
Requires PlotlyJS to be loaded first.
"""
function plotlyjs()
    backend!(PlotlyJSBackend())
end
