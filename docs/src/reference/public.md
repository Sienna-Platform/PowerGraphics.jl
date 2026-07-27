# [Public API Reference](@id api)

```@autodocs
Modules = [PowerGraphics]
Public = true
Private = false
Filter = t -> !startswith(string(nameof(t)), "plot_powerdata")
```

## Deprecated

The `plot_powerdata` family takes a `PowerAnalytics.PowerData`, which predates
the PowerAnalytics 1.0 metrics API. These methods keep working as forwarding
shims but emit a deprecation warning and will be removed in a future breaking
release — use [`plot_results`](@ref) with a `Dict{String, DataFrame}` (or
[`plot_dataframe`](@ref) for a single `DataFrame`) instead.

```@autodocs
Modules = [PowerGraphics]
Public = true
Private = false
Filter = t -> startswith(string(nameof(t)), "plot_powerdata")
```
