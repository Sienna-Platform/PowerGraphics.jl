# PowerGraphics.jl — Claude Guide

Platform-wide Sienna conventions (performance, type stability, formatter, environments, code style) live in `.claude/Sienna.md` — read it too. This file is repo-specific and does not restate them.

## Purpose & place in the stack

**This is the psy6 line.** PowerSimulations does not exist here — it was split into
InfrastructureOptimizationModels (IOM) and PowerOperationsModels (POM). Translate anything
from psy5 docs or the registered package before acting on it.

PowerGraphics.jl plots the **outputs** of a Sienna\Ops optimization problem. It is a leaf of
the stack: it consumes `IS.Outputs` and `PSY.System`, and builds its data through
PowerAnalytics' metrics framework. Direct deps (Project.toml): PowerSystems (`PSY`),
PowerAnalytics (`PA`), InfrastructureSystems (`IS`), DataFrames, TimeSeries, Colors, YAML,
DataStructures, CSV, InteractiveUtils.

**Runtime surface is PSY + IS + PA only.** IOM and POM appear solely in `test/Project.toml`,
to build a solved model for fixtures. Do not add either to `[deps]` or import them in `src/`
or `ext/`. `IS.get_source_data(outputs)` retrieves the attached System — the generic comes
from InfrastructureSystems, so it needs no new dependency.

## Backend-extension architecture (the central design)

The core in `src/` is backend-agnostic and contains **no plotting code**. The two plotting
backends are Julia package extensions (weak deps); a user must `using` one **before**
calling any plot function or the stubs throw.

- `src/PowerGraphics.jl` — module file. Holds all exports, the `PSY`/`IS`/`PA` aliases,
  include order (`backends.jl` → `definitions.jl` → `label_utils.jl` → `plot_data.jl` →
  `call_plots.jl`),
  and the extension contract: `_empty_plot`, `_dataframe_plots_internal`,
  `save_plot` are declared here and route to `_no_backend_loaded()` (throws `ArgumentError`)
  until an extension supplies the dispatch. `__init__` `@warn`s if no backend module is
  loaded.
- `src/backends.jl` — `abstract type PlottingBackend` with `CairoMakieBackend` /
  `PlotlyLightBackend` singletons. Backend selection is by dispatch on these types.
- `src/definitions.jl` — color palette (`PaletteColor`, `load_palette`, `DEFAULT_PALETTE_FILE`
  = `report_templates/color-palette.yaml`; overridable via `ENV["PG_PALETTE"]`).
- `src/label_utils.jl` — label helpers (`label_component`, `label_variable`, `label_acronym`,
  `label_first_word`, `label_short`, `label_truncate`).
- `src/plot_data.jl` — the data layer: turns outputs into plot-ready frames via `PA.compute`
  over `ComponentSelector`s, plus the private `_combine_categories` helper `plot_results`
  uses for its `Dict{String, DataFrame}` input.
- `src/call_plots.jl` — the public plot functions (backend-agnostic orchestration).

Extensions (`ext/`, declared in Project.toml `[weakdeps]`/`[extensions]`):
- `CairoMakieExt.jl` → includes `ext/plot_recipes.jl` (static, recommended).
- `PlotlyLightExt.jl` → includes `ext/plotly_recipes.jl` (interactive HTML).
- `WeaveExt.jl` — **RETIRED and inert.** Weave.jl is unmaintained and pins JSON 0.21
  against the psy6 stack's JSON ^1.5, so it cannot be installed. The module is commented
  out, `Weave` is gone from `[weakdeps]`/`[extensions]`/`[compat]`, and `report` is no
  longer declared or exported. `report_templates/generic_report_template.jmd` and
  `test/test_reports.jl` are commented out too. Do not re-add Weave.

## Public API

Every plot family has a CairoMakie form, a `_plotly`-suffixed PlotlyLight form, and in-place
`!` variants of both. Exports (all in the module file):

- `plot_demand` / `plot_demand_plotly` (+ `!`) — input `Union{IS.Outputs, PSY.System}`
- `plot_dataframe` / `plot_dataframe_plotly` (+ `!`) — input `DataFrames.DataFrame`
- `plot_results` / `plot_results_plotly` (+ `!`) — input `Dict{String, DataFrame}`
- `plot_fuel` / `plot_fuel_plotly` (+ `!`) — input `IS.Outputs`

The **`plot_powerdata` family is deleted** along with `PA.PowerData`. `plot_dataframe` does
what it did. `plot_fuel`'s `slacks::Bool` became `slack_selector` — `calc_system_slack_up`
has no default selector, because `ACBus` would silently be wrong under an area-balance
network model.
- `save_plot`, `load_palette`, and the `label_*` helpers above.

There is no report generation. `report` was retired with WeaveExt (above); writing a
replacement means picking a maintained renderer, not reviving Weave.

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

- **PowerAnalytics** (`PA`): supplies the metrics framework `plot_fuel` and `plot_demand` are
  built on. One `PA.compute` over a grouped `ComponentSelector` replaces the deleted
  `get_generation_data` → `make_fuel_dictionary` → `categorize_data` → `combine_categories`
  pipeline: categorisation is the selector's grouping, combination is `compute`'s per-group
  aggregation. `PA.get_data_df` / `get_data_cols` / `get_time_vec` are the accessors.
  Tests build their own fixture (`test/test_data/outputs_data.jl`); they no longer include
  PowerAnalytics' test data.
- **PowerSystems** (`PSY`) / **InfrastructureSystems** (`IS`): `System` and `Outputs` input
  types; compat pinned to PSY `^5.10`, IS `3`. These read lower than the actual lines *on
  purpose* — no version or compat bumps until release.
- **PowerOperationsModels / InfrastructureOptimizationModels**: test-only. The fixture builds
  and solves one `DecisionModel` (templates are built explicitly — there is no
  `template_unit_commitment` in psy6). PSB shared-state caveats apply (see Sienna.md).
- **Path pins in `[sources]` are local-development only** and will not resolve in CI.

## Verified commands

```sh
# Full test suite — loads BOTH backends + the POM/IOM/HiGHS/PSB stack. Currently 32 passing.
# The fixture solves a real DecisionModel once per run, so a full run takes ~1 min.
julia --project=test test/runtests.jl

# Single test file: pass the full file stem INCLUDING the `test_` prefix, e.g. test_plot_creation
julia --project=test test/runtests.jl test_plot_creation
# (runtests.jl maps each ARG `f` -> `"$f.jl"` and includes it from test/; with no ARGS it
#  globs every test/test_*.jl, skipping DISABLED_TEST_FILES. It uses TestSetExtensions and
#  an IS MultiLogger that fails the run if any Error-level log event is recorded.)

# Format (run before considering any task done)
julia --project=scripts/formatter -e 'include("scripts/formatter/formatter_code.jl")'
# (formats ./src, ./test, ./docs/src; the script also runs Pkg.update())

# Build docs
julia --project=docs docs/make.jl
```

Test files: `test/test_plot_creation.jl`, `test/test_signed_stack_bounds.jl`
(`test/test_reports.jl` is inert and in `DISABLED_TEST_FILES`) (+ `test/test_yamls/`). CI workflows live in
`.github/workflows/` (`main-tests.yml`, `pr_testing.yml`, `docs.yml`, `format-check.yml`).

## Durable knowledge from the psy6 migration

- **Test the integration, not just the layer.** Refactoring this package onto PowerAnalytics'
  metrics API exposed four real defects in PowerAnalytics that its own green suite never caught,
  because nothing there exercised `compute` against a real `IS.Outputs`. If a plot path throws
  in a way that looks like an upstream bug, report it upstream — do not work around it here.

- **`make_selector` defaults to `groupby = :each`.** A selector handed straight to `PA.compute`
  yields one column per component. Single-column accessors like `PA.get_data_vec` then throw.
  Regroup with `PA.rebuild_selector(sel; groupby = :all)` — the curtailment and slack paths in
  `_plot_fuel!` both do this.

- **`gentype: Any` in a generator-mapping YAML means every `StaticInjection`**, loads included —
  not every generator. An `Any` catch-all sweeps in load components whose `ActivePowerVariable`
  a `StaticPowerLoad` formulation never creates, and the read then throws. Use
  `gentype: Generator`.

- **`PA.get_data_df`, not a hand-rolled DateTime drop.** It also excludes the metrics framework's
  metadata columns, which would otherwise appear as spurious plot series.

- **Weave is retired and must not come back** — see the extension section above.
