# Welcome to PowerGraphics.jl

```@meta
CurrentModule = PowerGraphics
```

## Overview

`PowerGraphics.jl` is a [`Julia`](http://www.julialang.org) package for plotting results
from [PowerSimulations.jl](https://sienna-platform.github.io/PowerSimulations.jl/stable/)
and related Sienna\Ops analysis workflows.

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
programming language. `PowerGraphics.jl` supports Sienna\Ops by turning simulation and
analytics results into figures.

## How to use this documentation

  - **Tutorials** — examples to help you *learn* plotting workflows
  - **How to...** — task guides such as changing backends
  - **Reference** — public API and developer notes for quick look-up

`PowerGraphics.jl` follows the [Diátaxis](https://diataxis.fr/) documentation framework.

## Installation and Quick Links

  - [Sienna installation page](https://sienna-platform.github.io/Sienna/SiennaDocs/docs/build/how-to/install/):
    Instructions to install `PowerGraphics.jl` and other Sienna packages
  - [Central Sienna documentation](https://sienna-platform.github.io/Sienna/SiennaDocs/docs/build/index.html):
    Cross-linked documentation website for the core user-facing Sienna packages
