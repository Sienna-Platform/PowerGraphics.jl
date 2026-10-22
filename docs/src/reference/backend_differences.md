# Backend Differences

```@meta
CurrentModule = PowerGraphics
```

Every `plot_*` function takes a `backend` key word: [`CairoMakieBackend`](@ref)`()` (the
default, static figures) or [`PlotlyLightBackend`](@ref)`()` (interactive HTML). The two
backends are not pixel-identical. This page lists what is the same on both and what
differs.

## Identical on both backends

| Behavior            | Behavior on both backends                                                                                                                                                                                                                        |
|:------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Series draw order   | On non-bar plots, series whose values sum to a negative total (storage charging, source input) are drawn first, then the rest, each group keeping its column order.                                                                              |
| Sign-aware stacking | A series is classified by the sign of its total, not per time step. Positive series stack upward from 0 and negative series stack downward from 0. A positive series that is 0 at a time step (PV at night) stays in place as a zero-width band. |
| Series colors       | Both backends use the same colors from the palette given by [`load_palette`](@ref), continuing the color cycle past series already on the plot.                                                                                                  |
| Reserve stacks      | [`plot_fuel`](@ref) with `service` draws the same fuel categories, values and colors on both backends.                                                                                                                                           |

## Differences between backends

| Behavior                  | CairoMakie                                                                                                | PlotlyLight                                                                                                                                       |
|:------------------------- |:--------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------- |
| Save formats              | `png` (default), `pdf`, `svg`. A `.html` filename throws an `ArgumentError`.                              | `html` only. Any other extension warns and is rewritten to `.html`; the rewritten path is returned.                                               |
| Time axis                 | Ticks only at the first and last timestamps.                                                              | Native date-time axis with automatic ticks.                                                                                                       |
| Bar-plot x-axis           | Grouped bars (`stack = false`) get one rotated tick label per category; stacked bars have no tick labels. | No tick labels on bar plots.                                                                                                                      |
| Y-axis range              | Fitted to the data; zero is not forced into range.                                                        | Always includes zero.                                                                                                                             |
| Stacked-area band outline | Not drawn on non-stair stacked plots (drawn with `stair = true`).                                         | Always drawn.                                                                                                                                     |
| `save_plot` key words     | Ignored.                                                                                                  | `autoplay`, `post_script`, `full_html`, `animation_opts`, `default_width` and `default_height` are passed to the HTML writer; others are ignored. |
| Figure size               | Fixed at `1280 × 720`.                                                                                    | Plotly's responsive default.                                                                                                                      |
