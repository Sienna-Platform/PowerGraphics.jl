# PowerGraphics

[![Main - CI](https://github.com/NREL-Sienna/PowerGraphics.jl/actions/workflows/main-tests.yml/badge.svg)](https://github.com/NREL-Sienna/PowerGraphics.jl/actions/workflows/main-tests.yml)
[![codecov](https://codecov.io/gh/NREL-Sienna/PowerGraphics.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/NREL-Sienna/PowerGraphics.jl)
[![Documentation Build](https://github.com/NREL-Sienna/PowerGraphics.jl/workflows/Documentation/badge.svg?)](https://nrel-sienna.github.io/PowerGraphics.jl/stable)
[<img src="https://img.shields.io/badge/slack-@Sienna/PG-sienna.svg?logo=slack">](https://join.slack.com/t/nrel-sienna/shared_invite/zt-glam9vdu-o8A9TwZTZqqNTKHa7q3BpQ)
[![PowerGraphics.jl Downloads](https://img.shields.io/badge/dynamic/json?url=http%3A%2F%2Fjuliapkgstats.com%2Fapi%2Fv1%2Ftotal_downloads%2FPowerGraphics&query=total_requests&label=Downloads)](http://juliapkgstats.com/pkg/PowerGraphics)

PowerGraphics.jl is a Julia package for plotting results from [PowerSimulations.jl](https://github.com/NREL-Sienna/PowerSimulations.jl).

## Installation

```julia
julia> ]
(v1.10) pkg> add PowerGraphics
```

## Usage

`PowerGraphics.jl` uses [PowerSystems.jl](https://github.com/NREL-Sienna/PowerSystems.jl) and [PowerSimulations.jl](https://github.com/NREL-Sienna/PowerSimulations.jl) to handle the data and execution power system simulations.

```julia
using PowerGraphics
using PowerAnalytics
# where "res" is a PowerSimulations.SimulationResults object
gen = get_generation_data(res)
plot_powerdata(gen)
```

`PowerGraphics.jl` creates figures using a number of optional backends using `Plots.jl`. For interactive figures, it is recommended to use the `PlotlyLight.jl` backend, which requires the `PlotlyLight.jl`:

```julia
using Pkg
Pkg.add("PlotlyLight")
```

When using `PowerGraphics.jl` within a jupyter notebook, `WebIO.jl` is also required:

```julia
Pkg.add("WebIO")
```

An additional command (`plotlylight()`) to startup the `PlotlyLight` backend from `Plots` is required:

```julia
using PowerGraphics
plotlylight()
# where "res" is a PowerSimulations.SimulationResults object
plot_fuel(res)
```

## Development

Contributions to the development and enhancement of PowerGraphics is welcome. Please see [CONTRIBUTING.md](https://github.com/NREL-Sienna/PowerGraphics.jl/blob/main/CONTRIBUTING.md) for code contribution guidelines.

## License

PowerGraphics is released under a BSD [license](https://github.com/nrel-sienna/PowerGraphics.jl/blob/main/LICENSE). PowerGraphics has been developed as part of the Scalable Integrated Infrastructure Planning (SIIP)
initiative at the U.S. Department of Energy's National Renewable Energy Laboratory ([NREL](https://www.nrel.gov/))
