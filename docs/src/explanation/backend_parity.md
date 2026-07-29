# Backend Parity Contract

```@meta
CurrentModule = PowerGraphics
```

`PowerGraphics.jl` renders through two plotting backends, and they are not pixel-identical.
Some of what differs is a promise the package intends to keep, and some of it is an
unavoidable consequence of what CairoMakie and PlotlyLight each can do. This page draws
that line explicitly, so that neither users nor maintainers have to guess which is which.

The distinction matters. When a divergence is undocumented, a bug fixed in one recipe
quietly stays broken in the other — which is exactly what happened to the bar-plot
stacking fix in
[PR #140](https://github.com/Sienna-Platform/PowerGraphics.jl/pull/140).

## Choosing a backend

Every `plot_*` function takes a `backend` key word:

```julia
backend::PlottingBackend = CairoMakieBackend()
```

  - [`CairoMakieBackend`](@ref)`()` — the default. Static, publication-quality figures
    written as `png`, `pdf`, or `svg`. Requires `using CairoMakie`.
  - [`PlotlyLightBackend`](@ref)`()` — lightweight interactive figures written as `html`.
    Requires `using PlotlyLight`.

The backend packages are weak dependencies loaded through Julia package extensions, so the
matching package must be `using`-loaded **before** any plot call. Otherwise the stubs in
`src/PowerGraphics.jl` throw an `ArgumentError` telling you which `using` is missing.

```julia
using CairoMakie      # or PlotlyLight
using PowerGraphics

plot_fuel(res)                                   # CairoMakie (default)
plot_fuel(res; backend = PlotlyLightBackend())   # PlotlyLight
```

!!! warning "The `_plotly` names are deprecated"
    
    `plot_fuel_plotly`, `plot_demand_plotly`, `plot_dataframe_plotly`,
    `plot_results_plotly`, `plot_powerdata_plotly`, and their `!` forms still work but
    emit a deprecation warning. The backend is a *value*, not part of a function name —
    write `plot_fuel(res; backend = PlotlyLightBackend())` instead. See
    [Change Backends](@ref) for the task-oriented version of this.

## Guaranteed identical across backends

The behaviors below are resolved **once** in `src/call_plots.jl` (and, for colors,
`src/definitions.jl`) before either recipe is reached. The recipes in `ext/` consume
already-decided values; they do not re-derive them. Treat this list as a stability
promise: **a change to any of these is a change to both backends by construction.**

| Behavior                     | Where it is decided                  | The promise                                                                                                                                                                                                                                                                                          |
|:---------------------------- |:------------------------------------ |:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Series draw order            | `_series_draw_order`                 | On non-bar plots, series whose values sum to a net-negative total are drawn first, then the rest, each group keeping its original column order. Net-negative series (storage charging, source input) sit below the zero axis, so drawing them first leaves the positive bands on top.                |
| Sign-aware stacking          | `_signed_stack_bounds`               | A series is classified by the sign of its *total*, not per timestep. Positive-type series stack upward from 0; negative-type series stack downward from 0. A positive series keeps a zero-width band in place at timesteps where it is 0 (PV at night) rather than jumping to the negative baseline. |
| `nofill` default             | `_PlotOptions`                       | `nofill = !bar && !stack`. A plain line plot draws no area fill; stacked and bar plots do.                                                                                                                                                                                                           |
| `linestyle` / `linewidth`    | `_resolve_linestyle`, `_PlotOptions` | `linestyle::Symbol` is the canonical spelling and defaults to `:solid`; the old PlotlyLight-only `line_dash` spelling is folded into it centrally. `linewidth` defaults to `1` and is converted to `Float64` once.                                                                                   |
| Title resolution             | `_resolve_title`                     | `title` defaults to "no title"; the legacy `" "` (single-space) sentinel for "untitled" is normalized to `nothing` in one place.                                                                                                                                                                     |
| Untitled-save filename       | `_UNTITLED_SAVE_NAME`                | A [`plot_dataframe`](@ref) save with no title lands at `dataframe.<format>`.                                                                                                                                                                                                                         |
| Empty-`DataFrame` handling   | `_plot_dataframe!`                   | An empty input warns `"Plot dataframe empty: skipping plot creation"` and returns the plot handle unchanged. Neither recipe is entered, so no labels, legend, or file are produced.                                                                                                                  |
| Default series color palette | `get_palette_seriescolor`            | Both backends select the *same* colors — the whole palette from [`load_palette`](@ref), so more series get a distinct color before the cycle repeats. The two backends differ only in the representation each library wants (`Colors.RGBA` objects vs. `"rgba(...)"` strings).                       |
| Label handling / `label_fn`  | `_PlotOptions`                       | `label_fn` defaults to [`label_short`](@ref) and is applied by both recipes to the same column names, producing the same legend text.                                                                                                                                                                |

!!! note "Same rule, two mechanisms"
    
    Sign-aware stacking is a shared *rule* with two implementations, because the
    libraries stack differently: CairoMakie is handed explicit `(lower, upper)` band
    envelopes from `_signed_stack_bounds`, while PlotlyLight expresses the same split by
    assigning each trace to one of two Plotly `stackgroup`s keyed on the series' net
    sign. The classification is identical, so the two produce the same picture. If you
    change the classification, change it in both.

## Deliberate, documented differences

These differences are intentional. Each one exists because of a constraint in the
underlying library, and the "Why" column is the reason not to "fix" it.

| Behavior                      | CairoMakie                                                                                                                                                                                           | PlotlyLight                                                                                                                                                | Why the difference exists                                                                                                                                                                                                                                                                                                                                                         |
|:----------------------------- |:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:---------------------------------------------------------------------------------------------------------------------------------------------------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Save formats**              | `png`, `pdf`, `svg` via `CairoMakie.save`. A `.html` filename throws an `ArgumentError` pointing at `PlotlyLightBackend()`.                                                                          | `html` only. Any other extension emits a warning and is rewritten to `.html`; the rewritten path is returned.                                              | PlotlyLight has no built-in image export — it serializes a plot to an HTML/JS payload. Rasterizing would require Kaleido/PlotlyBase, which the package deliberately does not depend on. CairoMakie is a vector/raster renderer with no HTML target.                                                                                                                               |
| **Default save format**       | `"png"`                                                                                                                                                                                              | `"html"`                                                                                                                                                   | `_default_save_format` is dispatched on the backend rather than hardcoded. A shared `"png"` default would make *every* default-path PlotlyLight save trip the rewrite warning above. An explicit `format` key word still wins.                                                                                                                                                    |
| **Time axis**                 | `DateTime`s are converted to unix floats (`Dates.datetime2unix`) and only the first and last timestamps are drawn as ticks.                                                                          | Timestamps are passed through as a native Plotly datetime axis with full automatic tick control.                                                           | `CairoMakie.band!` — the primitive behind stacked areas — cannot take a `DateTime` axis. Every CairoMakie plot therefore uses a float axis so that stacked and non-stacked layers can share one `Axis`. Float ticks would render as raw unix seconds, so the axis is labeled explicitly at the endpoints.                                                                         |
| **Bar-plot x-axis**           | Grouped bars (`stack = false`) get one tick per category with the label rotated 45° and right/top-anchored. Stacked bars get a single unlabeled tick and are identified by legend only.              | Tick labels are hidden for all bar plots (`showticklabels = !bar`); bars are identified by legend only.                                                    | Long category labels such as `RenewableDispatch__Curtailment` overlap when drawn horizontally, hence the rotation. CairoMakie stacked bars all sit at one x position (a single `barplot!` call with per-element stack ids), so there is no per-category tick to label; Plotly's `barmode` handles positioning itself and its legend is interactive, so tick labels are redundant. |
| **Y-limit anchoring**         | `reset_limits!` on the axis; zero is *not* forced into range.                                                                                                                                        | `yaxis.rangemode = "tozero"`.                                                                                                                              | Plotly's `rangemode` is a layout flag with no exact Makie equivalent. Makie's autolimits keep a tight fit around the data, which is usually the better default for a static figure; Plotly's zoom/pan makes an anchored baseline cheap to escape.                                                                                                                                 |
| **Stacked-area band outline** | In the non-stair stacked branch the per-band outline is deliberately **omitted** — only the filled band is drawn. The stair branch does draw a `stairs!` outline.                                    | Every trace is a `scatter` with `mode = "lines"`, so the outline is always drawn alongside the fill.                                                       | For intermittent series (PV at night, idle storage) a CairoMakie outline jumps between the stacked position and the zero anchor, drawing near-vertical streaks across the stack. Plotly's `stackgroup` machinery interpolates the line along the stacked baseline instead, so the same artifact does not appear.                                                                  |
| **Figure size**               | Hardcoded `1280 × 720` (16:9).                                                                                                                                                                       | Plotly's own default.                                                                                                                                      | Makie's 800×600 (4:3) default deforms time-series stack plots badly enough to be worth overriding; Plotly's default is responsive in the browser. Neither backend honors a `size` key word — see [issue #77](https://github.com/Sienna-Platform/PowerGraphics.jl/issues/77).                                                                                                      |
| **`save_plot` key words**     | Accepted and ignored.                                                                                                                                                                                | Filtered to a supported set and forwarded to the HTML writer: `autoplay`, `post_script`, `full_html`, `animation_opts`, `default_width`, `default_height`. | These are `PlotlyLight`'s HTML-serialization options; `CairoMakie.save` has no analogue. Unrecognized key words are dropped rather than erroring so that a single `save_plot` call can be written backend-agnostically.                                                                                                                                                           |
| **Returned plot object**      | `CairoMakiePlot` — a mutable wrapper around a `Figure` and an `Axis`, carrying `series_count::Int` and `has_legend::Bool`.                                                                           | `PlotlyLight.Plot`.                                                                                                                                        | The `!`-form plot functions layer new series onto an existing handle. CairoMakie needs to remember how many series were already drawn (to continue the color cycle) and whether a `Legend` must be replaced; Plotly's `Plot` already carries its traces, so `length(plot.data)` answers the same question.                                                                        |
| **Legend construction**       | A `Legend` is built (and any previous one deleted) on each call, positioned at `figure[1, 2]` or `figure[2, 1]` for `legend_position = :bottom`. Stacked bars need hand-built `PolyElement` entries. | Per-trace `showlegend = true`; `legend_position = :bottom` sets a horizontal layout legend.                                                                | A single Makie `barplot!` with a vector `color` attribute has no per-element color→label mapping, so Makie's automatic legend extraction fails for stacked bars and the entries must be captured manually.                                                                                                                                                                        |

!!! warning "Extension matching is case-sensitive on PlotlyLight"
    
    The CairoMakie writer lowercases the extension before checking it; the PlotlyLight
    writer compares against `".html"` exactly. A filename ending in `.HTML` is therefore
    accepted by CairoMakie's check as HTML (and rejected), but treated as a non-HTML
    extension by PlotlyLight and rewritten to `.html`. Use lowercase extensions.

## Guidance for maintainers

The core in `src/` is backend-agnostic and contains no plotting code. The recipes in
`ext/plot_recipes.jl` and `ext/plotly_recipes.jl` are **drawing layers only**: they receive
a fully-resolved `_PlotOptions` and turn it into library calls. That split is what this
page documents, and it is load-bearing — the two backends drifted apart in the first place
because each recipe derived its own defaults.

When you change plotting behavior, decide explicitly which kind of change it is:

 1. **A Section-2 promise.** Change it *once*, in `src/call_plots.jl` or
    `src/definitions.jl`, so both backends pick it up by construction. Do not add the
    same logic to both recipes; if you find yourself writing it twice, it belongs in
    core. Update the "Guaranteed identical" table above.

 2. **A Section-3 difference.** Change it in one recipe, and **add a row to the table
    above** naming the library constraint that forces the divergence. A difference that
    is not in that table is a bug, not a design decision.

If neither applies cleanly — for example a behavior that *could* be unified but currently
is not — prefer unifying it in core. The default answer is parity.
