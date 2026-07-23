# Welcome to PowerGraphics.jl

```@meta
CurrentModule = PowerGraphics
```

## Overview

`PowerGraphics.jl` is a [`Julia`](http://www.julialang.org) package for plotting power-system
simulation results. It sits downstream of
[PowerSimulations.jl](https://sienna-platform.github.io/PowerSimulations.jl/stable/) and
[PowerAnalytics.jl](https://sienna-platform.github.io/PowerAnalytics.jl/stable/): Analytics
assembles generation, load, and fuel-category tables; PowerGraphics turns those tables into
figures.

Typical entry points:

  - [`plot_demand`](@ref) — demand from an [`InfrastructureSystems.Results`](@extref) object
    or a [`PowerSystems.System`](@extref)
  - [`plot_powerdata`](@ref) / [`plot_results`](@ref) — generation or other
    [`PowerAnalytics.PowerData`](https://sienna-platform.github.io/PowerAnalytics.jl/stable/) / dictionary results
  - [`plot_fuel`](@ref) — stacked generation by fuel with an optional load overlay
  - [`plot_dataframe`](@ref) — any time-indexed [`DataFrames.DataFrame`](@extref)

Plots use [CairoMakie](https://docs.makie.org/stable/) by default or
[PlotlyLight](https://github.com/JuliaComputing/PlotlyLight.jl) via `*_plotly` variants.
See [Change Backends](@ref change-backends) for loading extensions, [`save_plot`](@ref), and [`report`](@ref).
Browse archetypes in the [Gallery](@ref gallery).

## About Sienna

`PowerGraphics.jl` is part of the National Laboratory of the Rockies (formerly known as NREL)'s
[Sienna ecosystem](https://sienna-platform.github.io/Sienna/), an open source framework for
scheduling problems and dynamic simulations for power systems. The Sienna ecosystem can be
[found on GitHub](https://github.com/Sienna-Platform). It contains three applications:

  - [Sienna\Data](https://sienna-platform.github.io/Sienna/pages/applications/sienna_data.html) enables
    efficient data input, analysis, and transformation
  - [Sienna\Ops](https://sienna-platform.github.io/Sienna/pages/applications/sienna_ops.html) enables
    system scheduling simulations by formulating and solving optimization problems
  - [Sienna\Dyn](https://sienna-platform.github.io/Sienna/pages/applications/sienna_dyn.html) enables
    system transient analysis including small signal stability and full system dynamic
    simulations

Each application uses multiple packages in the [`Julia`](http://www.julialang.org)
programming language.

## How to use this documentation

  - **How to...** — task guides such as [Change Backends](@ref change-backends)
  - **Reference** — [Public API](@ref api), [Gallery](@ref gallery) of plot archetypes, and developer notes

`PowerGraphics.jl` follows the [Diátaxis](https://diataxis.fr/) documentation framework.

## Installation and Quick Links

  - [Sienna installation page](https://sienna-platform.github.io/Sienna/SiennaDocs/docs/build/how-to/install/):
    Instructions to install `PowerGraphics.jl` and other Sienna packages
  - [Sienna Documentation Hub](https://sienna-platform.github.io/Sienna/SiennaDocs/docs/build/index.html):
    Links to other Sienna packages' documentation
