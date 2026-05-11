# PowerGraphics

[![Main - CI](https://github.com/Sienna-Platform/PowerGraphics.jl/actions/workflows/main-tests.yml/badge.svg)](https://github.com/Sienna-Platform/PowerGraphics.jl/actions/workflows/main-tests.yml)
[![codecov](https://codecov.io/gh/Sienna-Platform/PowerGraphics.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/Sienna-Platform/PowerGraphics.jl)
[![Documentation Build](https://github.com/Sienna-Platform/PowerGraphics.jl/workflows/Documentation/badge.svg?)](https://sienna-platform.github.io/PowerGraphics.jl/stable)
[<img src="https://img.shields.io/badge/slack-@Sienna/PG-sienna.svg?logo=slack">](https://join.slack.com/t/core-sienna/shared_invite/zt-glam9vdu-o8A9TwZTZqqNTKHa7q3BpQ)
[![PowerGraphics.jl Downloads](https://img.shields.io/badge/dynamic/json?url=http%3A%2F%2Fjuliapkgstats.com%2Fapi%2Fv1%2Ftotal_downloads%2FPowerGraphics&query=total_requests&label=Downloads)](http://juliapkgstats.com/pkg/PowerGraphics)

PowerGraphics.jl is a Julia package for plotting results from [PowerSimulations.jl](https://github.com/Sienna-Platform/PowerSimulations.jl).

## Installation

```julia
julia> ]
(v1.10) pkg> add PowerGraphics
```

## Usage

`PowerGraphics.jl` uses [PowerSystems.jl](https://github.com/Sienna-Platform/PowerSystems.jl) and [PowerSimulations.jl](https://github.com/Sienna-Platform/PowerSimulations.jl) to handle the data and execution power system simulations.

`PowerGraphics.jl` supports two plotting backends, both loaded via Julia
package extensions. Load the backend you want **before** (or alongside)
`PowerGraphics`:

  - [CairoMakie](https://docs.makie.org/stable/) (recommended): static,
    publication-quality plots — `using CairoMakie`
  - [PlotlyLight](https://github.com/JuliaComputing/PlotlyLight.jl):
    lightweight interactive HTML plots — `using PlotlyLight`

```julia
using CairoMakie     # or `using PlotlyLight`
using PowerGraphics
using PowerAnalytics

# where `res` is a PowerSimulations.SimulationResults object
gen = get_generation_data(res)
plot_powerdata(gen)        # CairoMakie
# plot_powerdata_plotly(gen)  # PlotlyLight (`_plotly`-suffixed API)
```

If neither backend is loaded, `PowerGraphics.jl` prints a warning at load
time and the plotting functions throw an `ArgumentError` when called.

## Development

Contributions to the development and enhancement of PowerGraphics is welcome. Please see [CONTRIBUTING.md](https://github.com/Sienna-Platform/PowerGraphics.jl/blob/main/CONTRIBUTING.md) for code contribution guidelines.

## License

PowerGraphics is released under a BSD [license](https://github.com/Sienna-Platform/PowerGraphics.jl/blob/main/LICENSE). PowerGraphics has been developed as part of the Scalable Integrated Infrastructure Planning (SIIP)
initiative at the U.S. Department of Energy's National Laboratory of the Rockies ([NLR](https://www.nlr.gov/)) formerly known as NREL. 
