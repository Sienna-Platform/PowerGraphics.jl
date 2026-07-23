# [Select Plot Backends](@id change-backends)

`PowerGraphics.jl` supports two plotting backends through Julia package extensions.
Load the backend you want **before** or **alongside** `PowerGraphics`:

  - [CairoMakie](https://docs.makie.org/stable/) (recommended): static, publication-quality
    plots — `using CairoMakie`
  - [PlotlyLight](https://github.com/JuliaComputing/PlotlyLight.jl): lightweight interactive
    HTML plots — `using PlotlyLight`

```julia
using CairoMakie   # or PlotlyLight
using PowerGraphics
using PowerAnalytics
```

If neither backend is loaded, `PowerGraphics` prints a warning at load time and plotting
functions throw an `ArgumentError` when called.

## API selects the backend

Choose the function name to choose the backend:

  - Unsuffixed functions (e.g. [`plot_powerdata`](@ref), [`plot_fuel`](@ref),
    [`plot_demand`](@ref), [`plot_dataframe`](@ref)) use **CairoMakie**
  - `*_plotly` variants (e.g. [`plot_powerdata_plotly`](@ref), [`plot_fuel_plotly`](@ref))
    use **PlotlyLight**

```julia
# where `gen` is a PowerAnalytics.PowerData from get_generation_data(res)
plot_powerdata(gen)           # CairoMakie
plot_powerdata_plotly(gen)    # PlotlyLight
```

Mutating `!` forms ([`plot_powerdata!`](@ref), [`plot_fuel!`](@ref), …) overlay series onto
an existing plot handle from the same backend family.

## Saving plots

Use [`save_plot`](@ref) (or the `save` / `format` kwargs on plot calls):

  - CairoMakie: `"png"`, `"pdf"`, `"svg"`
  - PlotlyLight: `"html"` (other extensions are written as `.html` with a warning)

```julia
p = plot_fuel(res)
save_plot(p, "fuel.png")

p = plot_fuel_plotly(res)
save_plot(p, "fuel.html")
```

## Reports

[`report`](@ref) (requires [Weave.jl](https://weavejl.mpastell.com/stable/) plus a plotting
backend) builds HTML or PDF summaries from a `.jmd` template. Choose the plot backend with
the `backend` keyword (`CairoMakieBackend()` or `PlotlyLightBackend()`):

```julia
using Weave
report(res, out_path, template; doctype = "md2pdf", backend = PowerGraphics.CairoMakieBackend())
```

See the [Gallery](@ref gallery) for CairoMakie plot archetypes and the
[Public API](@ref api) for full keyword lists.
