"""
Pre-built label transformation functions for use with the `label_fn` kwarg.

These are designed to shorten long legend labels like
`"ActivePowerVariable__HydroDispatch"` that appear in power system result plots.

The default label function is [`label_short`](@ref), which abbreviates the variable
prefix to its acronym while keeping the full component name.

# Usage

```julia
plot_powerdata(gen)                                # default: "APV: HydroDispatch"
plot_powerdata(gen; label_fn = label_component)    # "HydroDispatch"
plot_powerdata(gen; label_fn = label_acronym)       # "APV__HD"
plot_powerdata(gen; label_fn = label_truncate(20))  # truncate to 20 chars
plot_powerdata(gen; label_fn = s -> s)              # original full labels
```
"""

const _DOUBLE_UNDERSCORE = "__"

"""
    label_component(s::AbstractString) -> String

Extract the component type (part after `__`) from a label.

# Example
```julia
label_component("ActivePowerVariable__HydroDispatch")  # => "HydroDispatch"
label_component("SomeLabel")                            # => "SomeLabel"
```
"""
function label_component(s::AbstractString)
    idx = findlast(_DOUBLE_UNDERSCORE, s)
    isnothing(idx) && return String(s)
    return String(s[(last(idx) + 1):end])
end

"""
    label_variable(s::AbstractString) -> String

Extract the variable type (part before `__`) from a label.

# Example
```julia
label_variable("ActivePowerVariable__HydroDispatch")  # => "ActivePowerVariable"
label_variable("SomeLabel")                            # => "SomeLabel"
```
"""
function label_variable(s::AbstractString)
    idx = findfirst(_DOUBLE_UNDERSCORE, s)
    isnothing(idx) && return String(s)
    return String(s[1:(first(idx) - 1)])
end

"""
    label_acronym(s::AbstractString) -> String

Convert CamelCase segments to their uppercase initials, preserving the `__` separator.

# Example
```julia
label_acronym("ActivePowerVariable__HydroDispatch")       # => "APV__HD"
label_acronym("ActivePowerOutVariable__EnergyReservoirStorage")  # => "APOV__ERS"
label_acronym("SomeLabel")                                 # => "SL"
```
"""
function label_acronym(s::AbstractString)
    parts = split(s, _DOUBLE_UNDERSCORE)
    return join([_camelcase_initials(p) for p in parts], _DOUBLE_UNDERSCORE)
end

"""
    label_first_word(s::AbstractString) -> String

Extract the first CamelCase word from the label (ignoring the `__` separator structure).

# Example
```julia
label_first_word("ActivePowerVariable__HydroDispatch")  # => "Active"
label_first_word("HydroDispatch")                        # => "Hydro"
```
"""
function label_first_word(s::AbstractString)
    m = match(r"^([A-Z][a-z]*)", s)
    isnothing(m) && return String(s)
    return String(m.match)
end

"""Extract uppercase initials from a CamelCase string."""
function _camelcase_initials(s::AbstractString)
    return String(join(c for c in s if isuppercase(c)))
end

"""
    label_short(s::AbstractString) -> String

Abbreviate the variable prefix (part before `__`) to its uppercase initials while
keeping the full component name (part after `__`). Labels without `__` are returned
unchanged. This is the default `label_fn`.

# Example
```julia
label_short("ActivePowerVariable__HydroDispatch")             # => "APV: HydroDispatch"
label_short("ActivePowerOutVariable__EnergyReservoirStorage")  # => "APOV: EnergyReservoirStorage"
label_short("SomeLabel")                                       # => "SomeLabel"
```
"""
function label_short(s::AbstractString)
    idx = findfirst(_DOUBLE_UNDERSCORE, s)
    isnothing(idx) && return String(s)
    variable_part = s[1:(first(idx) - 1)]
    component_part = s[(last(idx) + 1):end]
    return _camelcase_initials(variable_part) * ": " * String(component_part)
end

"""
    label_truncate(n::Int) -> Function

Return a label function that truncates labels longer than `n` characters, appending `"…"`.
Can be composed with other label functions.

# Example
```julia
plot_powerdata(gen; label_fn = label_truncate(20))
# "ActivePowerVariable…"

# Compose with label_short:
plot_powerdata(gen; label_fn = s -> label_truncate(15)(label_short(s)))
```
"""
function label_truncate(n::Int)
    return function (s::AbstractString)
        length(s) <= n && return String(s)
        return String(s[1:n]) * "…"
    end
end
