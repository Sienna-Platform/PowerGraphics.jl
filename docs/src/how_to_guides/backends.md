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

The backend is a value, not a separate function: every `plot_*` function takes a
`backend` key word, defaulting to [`CairoMakieBackend`](@ref)`()`. Pass
[`PlotlyLightBackend`](@ref)`()` to render interactive HTML instead.

```julia
plot_fuel(res)                                   # CairoMakie (default)
plot_fuel(res; backend = PlotlyLightBackend())   # PlotlyLight

# The same key word works for every family and its `!` form:
plot_demand(res; backend = PlotlyLightBackend())
plot_dataframe!(p, df, time_range; backend = PlotlyLightBackend())
```

`report` takes the same key word: `report(res, out_path, template; backend = PlotlyLightBackend())`.

!!! warning "Deprecated: the `_plotly` suffix"
    
    The `_plotly`-suffixed functions — `plot_demand_plotly`,
    `plot_dataframe_plotly`, `plot_results_plotly`, `plot_fuel_plotly`,
    `plot_powerdata_plotly`, and their `!` forms — are deprecated. They still
    work and forward to the un-suffixed function with
    `backend = PlotlyLightBackend()`, but they emit a warning and will be
    removed in a future breaking release. They do not accept a `backend` key
    word; use the un-suffixed function if you need to choose the backend.

If neither backend is loaded, `PowerGraphics.jl` will print a warning and plotting
functions will not be available.

## Switching backends without surprises

The two backends do not render identically. Before you swap one for the other — or before
you change plotting behavior — check the [Backend Parity Contract](@ref), which lists what
is guaranteed to match across backends and which differences are deliberate (save formats,
time-axis ticks, bar-plot tick labels, y-limit anchoring, and the `save_plot` key words
each backend accepts).
