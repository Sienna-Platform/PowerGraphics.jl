# PowerGraphics.jl — Claude Guide

Platform-wide Sienna conventions (performance, type stability, formatter, environments, code style) live in `.claude/Sienna.md` — read it too. This file is repo-specific and does not restate them.

## Purpose & place in the stack

PowerGraphics.jl generates plots/visualizations from PowerSimulations.jl simulation
results. It is a leaf of the Sienna stack: it consumes `IS.Results`, `PSY.System`, and
`PA.PowerData` and produces figures and reports. Direct deps (Project.toml): PowerSystems
(`PSY`), PowerAnalytics (`PA`), InfrastructureSystems (`IS`), DataFrames, TimeSeries,
Colors, YAML, DataStructures. It does **not** depend on PowerSimulations directly —
PowerSimulations enters only via the test stack to produce results.

## Backend-extension architecture (the central design)

The core in `src/` is backend-agnostic and contains **no plotting code**. The two plotting
backends are Julia package extensions (weak deps); a user must `using` one **before**
calling any plot function or the stubs throw.

- `src/PowerGraphics.jl` — module file. Holds all exports, the `PSY`/`IS`/`PA` aliases,
  include order (`backends.jl` → `definitions.jl` → `label_utils.jl` → `call_plots.jl`),
  and the extension contract: `report`, `_empty_plot`, `_dataframe_plots_internal`,
  `save_plot` are declared here and route to `_no_backend_loaded()` (throws `ArgumentError`)
  until an extension supplies the dispatch. `__init__` `@warn`s if no backend module is
  loaded.
- `src/backends.jl` — `abstract type PlottingBackend` with `CairoMakieBackend` /
  `PlotlyLightBackend` singletons. Backend selection is by dispatch on these types.
- `src/definitions.jl` — color palette (`PaletteColor`, `load_palette`, `DEFAULT_PALETTE_FILE`
  = `report_templates/color-palette.yaml`; overridable via `ENV["PG_PALETTE"]`).
- `src/label_utils.jl` — label helpers (`label_component`, `label_variable`, `label_acronym`,
  `label_first_word`, `label_short`, `label_truncate`).
- `src/call_plots.jl` — the public plot functions (backend-agnostic orchestration; ~40K).

Extensions (`ext/`, declared in Project.toml `[weakdeps]`/`[extensions]`):
- `CairoMakieExt.jl` → includes `ext/plot_recipes.jl` (static, recommended).
- `PlotlyLightExt.jl` → includes `ext/plotly_recipes.jl` (interactive HTML).
- `WeaveExt.jl` — triggered by `["PlotlyLight", "Weave"]`; supplies `report`.

## Public API

Every plot family has a CairoMakie form, a `_plotly`-suffixed PlotlyLight form, and in-place
`!` variants of both. Exports (all in the module file):

- `plot_demand` / `plot_demand_plotly` (+ `!`) — input `Union{IS.Results, PSY.System}`
- `plot_dataframe` / `plot_dataframe_plotly` (+ `!`) — input `DataFrames.DataFrame`
- `plot_powerdata` / `plot_powerdata_plotly` (+ `!`) — input `PA.PowerData`
- `plot_results` / `plot_results_plotly` (+ `!`) — input `Dict{String, DataFrame}`
- `plot_fuel` / `plot_fuel_plotly` (+ `!`) — input `IS.Results`
- `report(res::IS.Results, out_path, design_template; doctype="md2pdf", backend=CairoMakieBackend())`
- `save_plot`, `load_palette`, and the `label_*` helpers above.

`report` uses Weave to render a `.jmd` template; example template at
`report_templates/generic_report_template.jmd`. `doctype="md2html"` for HTML; default is
PDF via `xelatex`.

## Conventions & gotchas

- **Mirror both backends.** A change to plotting behavior almost always must be applied to
  **both** `ext/plot_recipes.jl` and `ext/plotly_recipes.jl` to keep them consistent. The
  per-backend `save_plot(plot, filename)` 2-arg forms are also defined per extension.
- **Editing core vs ext.** New plot-orchestration logic goes in `src/call_plots.jl`; actual
  drawing code lives only in the `ext/` recipe files. Do not add backend packages to
  `[deps]` — they stay weak deps.
- **Headless.** CairoMakie writes image files directly with no display server, so tests need
  no `GKSwstype`/Xvfb workaround; figures are emitted to `test/test_results/`.
- Respect the include order in the module file when adding constants/types.

## Cross-package coupling

- **PowerAnalytics** (`PA`): supplies `PowerData` and the results-aggregation layer that
  `plot_powerdata`/`plot_fuel` consume. Tests reuse PowerAnalytics' own test data
  (`<PA>/test/test_data/results_data.jl`) — its layout is a coupling point.
- **PowerSystems** (`PSY`) / **InfrastructureSystems** (`IS`): `System` and `Results` input
  types; compat pinned to PSY `^5.10`, IS `3`.
- **PowerSimulations**: not a runtime dep — only the test environment uses it (plus
  StorageSystemsSimulations, HydroPowerSimulations, HiGHS, PowerSystemCaseBuilder) to build
  the simulation results that the plot functions render. PSB shared-state caveats apply (see
  Sienna.md).

## Verified commands

```sh
# Full test suite — loads BOTH backends + the PowerSimulations/HiGHS/PSB stack
julia --project=test test/runtests.jl

# Single test file: pass the full file stem INCLUDING the `test_` prefix, e.g. test_plot_creation
julia --project=test test/runtests.jl test_plot_creation
# (runtests.jl maps each ARG `f` -> `"$f.jl"` and includes it from test/; with no ARGS it
#  globs every test/test_*.jl. It uses TestSetExtensions and an IS MultiLogger that fails
#  the run if any Error-level log event is recorded.)

# Format (run before considering any task done)
julia --project=scripts/formatter -e 'include("scripts/formatter/formatter_code.jl")'
# (formats ./src, ./test, ./docs/src; the script also runs Pkg.update())

# Build docs
julia --project=docs docs/make.jl
```

Test files: `test/test_plot_creation.jl`, `test/test_reports.jl`,
`test/test_signed_stack_bounds.jl` (+ `test/test_yamls/`). CI workflows live in
`.github/workflows/` (`main-tests.yml`, `pr_testing.yml`, `docs.yml`, `format-check.yml`).
