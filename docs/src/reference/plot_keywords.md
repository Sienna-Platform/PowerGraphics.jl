# [Plot styling keywords](@id plot-style-keywords)

These keyword arguments are accepted by the CairoMakie and PlotlyLight plot
functions ([`plot_dataframe`](@ref), [`plot_powerdata`](@ref), [`plot_results`](@ref),
[`plot_demand`](@ref), [`plot_fuel`](@ref), and their `!` / `*_plotly` variants).
Function-specific keywords are documented on each method in the
[Public API](@ref api).

| Keyword | Default | Description |
|---------|---------|-------------|
| `stack` | `false` (`true` for [`plot_fuel`](@ref)) | Stack series (area or stacked bar) |
| `bar` | `false` | Draw bars instead of lines/areas |
| `stair` | `false` | Step (stair) line instead of linear interpolation |
| `nofill` | `false` | Prefer unfilled lines (backend-dependent when stacking) |
| `title` | `""` or plot-specific | Figure title; also used as the save basename when `save` is set |
| `seriescolor` | palette-derived | Colors for series |
| `save` | `nothing` | Directory path; when set, writes `$title.$format` via [`save_plot`](@ref) |
| `format` | `"png"` | File extension. CairoMakie: `"png"`, `"pdf"`, `"svg"`. PlotlyLight: `"html"` |
| `set_display` | `true` | When `false`, do not `display` the figure |
| `label_fn` | [`label_short`](@ref) | Transform legend labels. Built-ins: [`label_short`](@ref), [`label_component`](@ref), [`label_variable`](@ref), [`label_acronym`](@ref), [`label_first_word`](@ref), [`label_truncate`](@ref). With `combine_categories = true` (default for powerdata/results/fuel), labels are category names without `__`, so [`label_short`](@ref) is often a no-op |
| `legend_position` | `:right` | `:right` or `:bottom` |
| `legend_font_size` | backend default | Override legend font size |
| `palette` | [`load_palette`](@ref)() | Color palette for series / fuel categories |

See [Select Plot Backends](@ref change-backends) for CairoMakie vs PlotlyLight and
[`save_plot`](@ref) formats.
