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

These functions still work but emit a deprecation warning naming their replacement.

```@autodocs
Modules = [PowerGraphics]
Public = true
Private = false
Filter = t -> (
    startswith(string(nameof(t)), "plot_powerdata") ||
    occursin("_plotly", string(nameof(t)))
)
```
