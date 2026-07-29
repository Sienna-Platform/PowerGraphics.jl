# Backend-agnostic introspection of a PowerGraphics plot object.
#
# Value assertions used to be written against `PlotlyLight.Plot.data` only, so
# CairoMakie was covered by shallow counts and a numeric regression could be
# fixed in one backend while staying broken in the other (this is exactly how
# PR #140's bar-plot bug survived). These helpers read the drawn series back out
# of either backend's plot object so the same assertion can run against both.
#
# The two object models are genuinely different, so the extraction is documented
# per case below rather than pretended to be identical.

const CairoMakiePlot = Base.get_extension(PowerGraphics, :CairoMakieExt).CairoMakiePlot

"""
One drawn series read back out of a plot object.

- `label`: the legend label the series was drawn with.
- `values`: the y-values, see [`series_ydata`](@ref) for what "y-values" means
  per backend and per `kind`.
- `color`: the series color canonicalized to `(r, g, b)` bytes in `0:255`, so a
  CairoMakie `Colors.RGBA` and a PlotlyLight `"rgba(r, g, b, a)"` string compare
  equal when they select the same palette entry.
- `kind`: `:line`, `:stairs`, `:band`, `:bar` (CairoMakie) or `:scatter`,
  `:bar` (PlotlyLight).
- `linewidth`: the drawn line width, or `nothing` for marks that carry none
  (bands and bars on either backend).
"""
struct PlotSeries
    label::String
    values::Vector{Float64}
    color::Union{NTuple{3, Int}, Nothing}
    kind::Symbol
    linewidth::Union{Float64, Nothing}
end

########################### color canonicalization ###########################

# CairoMakie hands back a `Colorant`; `band!` wraps it as `(color, alpha)`;
# PlotlyLight keeps the palette's `"rgba(r, g, b, a)"` string, and callers may
# pass a named color such as `"black"` (the net-load overlay does). All four
# reduce to the same `(r, g, b)` byte triple.
_canonical_color(c::PowerGraphics.Colors.Colorant) = (
    round(Int, 255 * PowerGraphics.Colors.red(c)),
    round(Int, 255 * PowerGraphics.Colors.green(c)),
    round(Int, 255 * PowerGraphics.Colors.blue(c)),
)

_canonical_color(c::Tuple) = _canonical_color(first(c))

function _canonical_color(s::AbstractString)
    m = match(r"^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)", s)
    if isnothing(m)
        return _canonical_color(parse(PowerGraphics.Colors.RGB, s))
    end
    return (parse(Int, m[1]), parse(Int, m[2]), parse(Int, m[3]))
end

# Anything else (e.g. a colormap symbol) is reported as "no comparable color"
# rather than guessed at.
_canonical_color(::Any) = nothing

######################### PlotlyLight plot objects ###########################

"""
    plot_series(plot)

The drawn series of `plot`, in draw order, as [`PlotSeries`](@ref).

**PlotlyLight**: one entry per trace in `plot.data`; `values` is the trace's
stored `y`, always the series' own (raw) data, because Plotly stacks at render
time through `stackgroup`.

**CairoMakie**: one entry per *labeled* plot object on `plot.axis`; unlabeled
objects are skipped, which drops the companion `band!` of a stacked stair plot.
`values` depends on the mark:

- `:line` / `:stairs` — the y-values as drawn, which under a stacked `nofill` or
  `stair` call is the *cumulative outer envelope*, not the series' own data.
- `:band` — the series' own contribution, recovered from the stored
  `(lower, upper)` envelopes. The stack baseline is whichever envelope sits
  nearer zero, so `sum(abs, upper) < sum(abs, lower)` identifies a
  downward-stacked band; the comparison is scale-free, which matters because a
  category generating nothing sums to float noise and is stacked downward.
- `:bar` — the bar heights. A stacked bar plot is a *single* `barplot!` with
  vector attributes, flattened here into one `PlotSeries` per bar to line up
  with PlotlyLight's one-trace-per-series output.
"""
function plot_series(plot::PlotlyLight.Plot)
    return [_plotly_series(trace) for trace in plot.data]
end

# `type = "bar"` traces keep their color under `marker`, scatter traces under
# `line`; only scatter traces carry a width.
function _plotly_series(trace)
    is_bar = get(trace, :type, "scatter") == "bar"
    color = if is_bar
        haskey(trace, :marker) ? _canonical_color(trace.marker.color) : nothing
    else
        haskey(trace, :line) ? _canonical_color(trace.line.color) : nothing
    end
    linewidth = if !is_bar && haskey(trace, :line) && haskey(trace.line, :width)
        Float64(trace.line.width)
    else
        nothing
    end
    return PlotSeries(
        String(trace.name),
        collect(Float64, trace.y),
        color,
        is_bar ? :bar : :scatter,
        linewidth,
    )
end

########################## CairoMakie plot objects ###########################

function plot_series(plot::CairoMakiePlot)
    series = PlotSeries[]
    for mark in plot.axis.scene.plots
        append!(series, _makie_series(mark))
    end
    return series
end

# A mark drawn without a `label` is decoration, not a series.
_makie_labels(mark) =
    haskey(mark.attributes, :label) ? _as_label_vector(mark.label[]) : String[]

_as_label_vector(label::AbstractString) = [String(label)]
_as_label_vector(labels::AbstractVector) = String.(labels)

# `barplot!` takes vector attributes for a stacked bar; every other mark takes
# scalars. Dispatch keeps the two shapes apart instead of testing at run time.
_color_vector(color::AbstractVector, n::Int) = [_canonical_color(c) for c in color]
_color_vector(color, n::Int) = fill(_canonical_color(color), n)

# Makie stores positional data as `Point{2}`; the y-component is element 2.
_ycoords(points) = [Float64(p[2]) for p in points]

_makie_linewidth(mark) =
    haskey(mark.attributes, :linewidth) ? Float64(mark.attributes[:linewidth][]) : nothing

# Fallback: any mark PowerGraphics does not draw contributes no series.
_makie_series(::Any) = PlotSeries[]

function _makie_series(mark::Makie.Lines)
    return _makie_point_series(mark, :line)
end

function _makie_series(mark::Makie.Stairs)
    return _makie_point_series(mark, :stairs)
end

function _makie_point_series(mark, kind::Symbol)
    labels = _makie_labels(mark)
    isempty(labels) && return PlotSeries[]
    return [
        PlotSeries(
            only(labels),
            _ycoords(mark[1][]),
            _canonical_color(mark.attributes[:color][]),
            kind,
            _makie_linewidth(mark),
        ),
    ]
end

function _makie_series(mark::Makie.Band)
    labels = _makie_labels(mark)
    isempty(labels) && return PlotSeries[]
    lower = _ycoords(mark[1][])
    upper = _ycoords(mark[2][])
    # See `plot_series`: the stack baseline is whichever envelope sits nearer
    # zero, and a downward-stacked band is baselined on its upper envelope.
    values = if sum(abs, upper) < sum(abs, lower)
        lower .- upper
    else
        upper .- lower
    end
    return [
        PlotSeries(
            only(labels),
            values,
            _canonical_color(mark.attributes[:color][]),
            :band,
            nothing,
        ),
    ]
end

function _makie_series(mark::Makie.BarPlot)
    labels = _makie_labels(mark)
    isempty(labels) && return PlotSeries[]
    heights = _ycoords(mark[1][])
    colors = _color_vector(mark.attributes[:color][], length(labels))
    return [
        PlotSeries(labels[ix], [heights[ix]], colors[ix], :bar, nothing) for
        ix in eachindex(labels)
    ]
end

############################## shared accessors ##############################

"""
    series_labels(plot)

Ordered legend labels of the drawn series — the backend's draw order, which is
`_series_draw_order` (net-negative series first) for every non-bar plot.
"""
series_labels(plot) = [s.label for s in plot_series(plot)]

"""
    series_count(plot)

Number of drawn series. Counts what is actually on the plot, so it is an
independent check of CairoMakie's own `series_count` bookkeeping field.
"""
series_count(plot) = length(plot_series(plot))

"""
    series_ydata(plot)

Y-values of the drawn series, in draw order. See [`plot_series`](@ref) for what
these mean per backend and mark.
"""
series_ydata(plot) = [s.values for s in plot_series(plot)]

"""
    series_colors(plot)

Series colors as `(r, g, b)` byte triples in draw order, comparable across
backends even though CairoMakie stores `Colors.RGBA` and PlotlyLight stores
`"rgba(…)"` strings.
"""
series_colors(plot) = [s.color for s in plot_series(plot)]

"""
    series_linewidths(plot)

Drawn line widths in draw order; `nothing` for bands and bars, which carry none.
"""
series_linewidths(plot) = [s.linewidth for s in plot_series(plot)]

"""
    series_map(plot)

`label => values` for every drawn series. Throws if two series share a label,
because a duplicate label would silently drop coverage.
"""
function series_map(plot)
    out = Dict{String, Vector{Float64}}()
    for s in plot_series(plot)
        haskey(out, s.label) &&
            error("duplicate series label $(repr(s.label)) in plot introspection")
        out[s.label] = s.values
    end
    return out
end

"""
    series_values(plot, label)

Y-values of the single series drawn with `label`.
"""
function series_values(plot, label::AbstractString)
    matches = [s for s in plot_series(plot) if s.label == label]
    length(matches) == 1 || error(
        "expected exactly one series labeled $(repr(label)), found $(length(matches))",
    )
    return only(matches).values
end

"""
    plot_title(plot)

The visible plot title, or `nothing` when the plot carries none. CairoMakie
leaves `Axis.title` as `""` when unset and PlotlyLight omits `layout.title`
entirely; both are reported as `nothing`.
"""
function plot_title(plot::CairoMakiePlot)
    title = plot.axis.title[]
    return isempty(title) ? nothing : String(title)
end

function plot_title(plot::PlotlyLight.Plot)
    haskey(plot.layout, :title) || return nothing
    haskey(plot.layout.title, :text) || return nothing
    return String(plot.layout.title.text)
end
