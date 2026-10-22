# Change Backends

`PowerGraphics.jl` uses Julia package extensions to support multiple plotting backends.
Load the backend you want **before** (or alongside) `PowerGraphics`:

  - [CairoMakie](https://docs.makie.org/stable/) (recommended): creates static, publication-quality
    plots — `using CairoMakie`
  - [PlotlyLight](https://github.com/JuliaComputing/PlotlyLight.jl): creates lightweight
    interactive HTML plots — `using PlotlyLight`

```julia
using CairoMakie   # or PlotlyLight
using PowerGraphics
```

## Pick the backend per plot

Every `plot_*` function takes a `backend` key word, defaulting to
[`CairoMakieBackend`](@ref)`()`. Pass [`PlotlyLightBackend`](@ref)`()` to render
interactive HTML instead.

```julia
plot_fuel(res)                                   # CairoMakie (default)
plot_fuel(res; backend = PlotlyLightBackend())   # PlotlyLight

# The same key word works for every family and its `!` form:
plot_demand(res; backend = PlotlyLightBackend())
plot_dataframe!(p, df, time_range; backend = PlotlyLightBackend())
```

`report` takes the same key word: `report(res, out_path, template; backend = PlotlyLightBackend())`.

If neither backend is loaded, `PowerGraphics.jl` will print a warning and plotting
functions will not be available.

## Differences between backends

The backends do not render identically; see [Backend Differences](@ref).
