# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Development Guidelines:** Always load [Sienna.md](./Sienna.md) for Sienna-wide development preferences, style conventions, performance rules, and the `julia --project=<env>` requirement. Before running tests, confirm that [Sienna.md](./Sienna.md) has been read.

## Overview

PowerGraphics.jl plots results from PowerSimulations.jl. It is part of the Sienna ecosystem and consumes data via PowerSystems.jl and PowerAnalytics.jl.

## Backend Extension Architecture

This is the central design of the package. The core in `src/` is backend-agnostic and contains **no plotting code**. Two plotting backends are loaded as Julia package extensions (weak deps), and the user must load one **before** calling any plot function:

- **CairoMakie** (recommended, static) → `CairoMakieExt` → `ext/plot_recipes.jl`
- **PlotlyLight** (interactive HTML) → `PlotlyLightExt` → `ext/plotly_recipes.jl`
- **Weave + PlotlyLight** → `WeaveExt` (powers `report`)

`src/backends.jl` defines `abstract type PlottingBackend` with `CairoMakieBackend` / `PlotlyLightBackend` singletons. `src/PowerGraphics.jl` declares the extension contract: `_empty_plot`, `_dataframe_plots_internal`, `save_plot`, and `report` are stubs that throw `ArgumentError` (via `_no_backend_loaded`) until an extension provides the dispatch. The public API mirrors this split: every plot function has a CairoMakie form (`plot_powerdata`) and a `_plotly`-suffixed PlotlyLight form (`plot_powerdata_plotly`), each with an in-place `!` variant. Exports live in the main module file.

When changing plotting behavior, the same fix usually must be applied to **both** `ext/plot_recipes.jl` and `ext/plotly_recipes.jl` to keep backends consistent.

## Common Commands

```sh
# Run full test suite (loads both backends + PowerSimulations stack)
julia --project=test test/runtests.jl

# Run a single test file (omit the test_ prefix and .jl, e.g. test_plot_creation.jl)
julia --project=test test/runtests.jl test_plot_creation

# Format (Sienna formatter script; run before considering any task complete)
julia --project=scripts/formatter -e 'include("scripts/formatter/formatter_code.jl")'

# Build docs
julia --project=docs docs/make.jl
```

`test/runtests.jl` uses `TestSetExtensions`/`@includetests`; passing file stems as `ARGS` filters which test files run.
