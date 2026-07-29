# [Public API Reference](@id api)

```@autodocs
Modules = [PowerGraphics]
Public = true
Private = false
Filter = t -> !(
    startswith(string(nameof(t)), "plot_powerdata") ||
    occursin("_plotly", string(nameof(t)))
)
```

## Deprecated

Two families are deprecated but still exported, so existing code keeps working:

  - The `_plotly`-suffixed functions. The backend is now a `backend` key word on
    every plot function, so the suffix only doubled the API — write
    [`plot_fuel`](@ref)`(res; backend = PlotlyLightBackend())` instead of
    `plot_fuel_plotly(res)`.
  - The `plot_powerdata` family, which takes a `PowerAnalytics.PowerData` — a
    type that predates the PowerAnalytics 1.0 metrics API. Use
    [`plot_results`](@ref) with a `Dict{String, DataFrame}` (or
    [`plot_dataframe`](@ref) for a single `DataFrame`) instead.

Both emit a deprecation warning and will be removed in a future breaking release.

```@autodocs
Modules = [PowerGraphics]
Public = true
Private = false
Filter = t -> (
    startswith(string(nameof(t)), "plot_powerdata") ||
    occursin("_plotly", string(nameof(t)))
)
```
