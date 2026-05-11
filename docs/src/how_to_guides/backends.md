# Change Backends

`PowerGraphics.jl` ships with [CairoMakie](https://docs.makie.org/stable/) as its
default static plotting backend — `using PowerGraphics` is sufficient to call the
`plot_*` functions and produce publication-quality png/pdf/svg output.

For interactive HTML plots, additionally load
[PlotlyLight](https://github.com/JuliaComputing/PlotlyLight.jl). PowerGraphics
exposes a parallel `_plotly`-suffixed API via a package extension:

```julia
using PowerGraphics              # CairoMakie is always available
plot_powerdata(gen)              # static / CairoMakie

using PlotlyLight                # opt-in for interactive HTML
plot_powerdata_plotly(gen)       # interactive / PlotlyLight
```
