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

If neither backend is loaded, `PowerGraphics.jl` will print a warning and plotting
functions will not be available.
