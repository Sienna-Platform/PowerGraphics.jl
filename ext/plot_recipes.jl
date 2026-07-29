# CairoMakie backend implementation

# Wrapper for CairoMakie plots to track series and support multiple plot calls
mutable struct CairoMakiePlot
    figure::CairoMakie.Figure
    axis::CairoMakie.Axis
    series_count::Int
    has_legend::Bool
end

function PowerGraphics._empty_plot(backend::PowerGraphics.CairoMakieBackend)
    # 16:9 by default — the Makie 800x600 (4:3) default deforms time-series
    # stack plots too much.
    fig = CairoMakie.Figure(; size = (1280, 720))
    ax = CairoMakie.Axis(fig[1, 1])
    return CairoMakiePlot(fig, ax, 0, false)
end

PowerGraphics._drawn_series_count(
    plot::CairoMakiePlot,
    ::PowerGraphics.CairoMakieBackend,
) = plot.series_count

function PowerGraphics._dataframe_plots_internal(
    plot::CairoMakiePlot,
    time_range::Array,
    backend::PowerGraphics.CairoMakieBackend,
    opts::PowerGraphics._PlotOptions;
    kwargs...,
)
    data = opts.data
    labels = opts.column_labels
    seriescolor = opts.seriescolor
    interval = opts.interval

    # CairoMakie.band doesn't allow for DateTime axes. Every plot now gets
    # float axes instead so plots can be layered on the same Axis.
    time_range_float = Dates.datetime2unix.(time_range)

    plot.axis.xlabel = opts.x_label
    plot.axis.ylabel = opts.y_label
    if !isnothing(opts.title)
        plot.axis.title = opts.title
    end

    # For stacked bar plots CairoMakie's auto-legend extraction fails because a
    # single barplot! object with a vector `color` attribute has no per-element
    # color→label mapping. We capture the entries here and build the legend
    # manually with PolyElement below.
    bar_legend_entries = nothing

    if opts.bar
        plot_data = sum(data; dims = 1) ./ interval

        if opts.stack
            # CairoMakie stacks within a single barplot! call when given
            # per-element stack ids. Plotting one slice per call (each with
            # stack=[1]) just overlays bars at the same x — that's what the
            # previous implementation did and it did not actually stack.
            n = length(labels)
            xs = fill(1, n)
            heights = vec(plot_data)
            bar_colors = collect(seriescolor[1:n])
            CairoMakie.barplot!(
                plot.axis,
                xs,
                heights;
                stack = collect(1:n),
                color = bar_colors,
                label = string.(labels),
            )
            bar_legend_entries = (string.(labels), bar_colors)

            plot.axis.xticks = ([1], [""])
        else
            x_positions = 1:length(labels)
            for (ix, label) in enumerate(labels)
                color = seriescolor[ix]
                CairoMakie.barplot!(
                    plot.axis,
                    [x_positions[ix]],
                    [plot_data[ix]];
                    color = color,
                    label = string(label),
                )
            end
            plot.axis.xticks = (collect(x_positions), string.(labels))
            # Long category labels (e.g. "APV: RenewableDispatch__Curtailment")
            # overlap when drawn horizontally — rotate 45° and anchor the
            # top-right corner under each tick.
            plot.axis.xticklabelrotation = π / 4
            plot.axis.xticklabelalign = (:right, :top)
        end
        plot.axis.xgridvisible = false
    else
        draw_order = PowerGraphics._series_draw_order(opts.series_negative)
        if opts.stack && !opts.nofill
            # Sign-aware stacked area: positive series stack upward from 0,
            # negative series (e.g. storage charging) stack downward from 0 so
            # charging renders below the zero axis.
            lower_b, upper_b =
                PowerGraphics._signed_stack_bounds(data, opts.series_negative)
            for ix in draw_order
                lo = lower_b[:, ix]
                up = upper_b[:, ix]
                # Outer envelope of this band (top for +ve, bottom for -ve).
                outer = ifelse.(data[:, ix] .>= 0, up, lo)
                color = seriescolor[ix]

                if opts.stair
                    CairoMakie.stairs!(
                        plot.axis,
                        time_range_float,
                        outer;
                        color = color,
                        label = string(labels[ix]),
                        step = :post,
                        linestyle = opts.linestyle,
                        linewidth = opts.linewidth,
                    )
                    CairoMakie.band!(
                        plot.axis,
                        time_range_float,
                        lo,
                        up;
                        color = (color, 0.3),
                    )
                else
                    # Filled band only. A per-band outline line is omitted on
                    # purpose: for intermittent series (PV at night, idle
                    # storage) the outline jumps between the stacked position
                    # and the zero anchor, drawing near-vertical streaks across
                    # the stack.
                    CairoMakie.band!(
                        plot.axis,
                        time_range_float,
                        lo,
                        up;
                        color = (color, 0.7),
                        label = string(labels[ix]),
                    )
                end
            end
        elseif opts.stack && opts.nofill
            # Sign-aware stacked lines: outer envelope of each band (positive
            # stacked up, negative stacked down).
            lower_b, upper_b =
                PowerGraphics._signed_stack_bounds(data, opts.series_negative)
            for ix in draw_order
                outer = ifelse.(data[:, ix] .>= 0, upper_b[:, ix], lower_b[:, ix])
                color = seriescolor[ix]
                if opts.stair
                    CairoMakie.stairs!(
                        plot.axis,
                        time_range_float,
                        outer;
                        color = color,
                        label = string(labels[ix]),
                        step = :post,
                        linestyle = opts.linestyle,
                        linewidth = opts.linewidth,
                    )
                else
                    CairoMakie.lines!(
                        plot.axis,
                        time_range_float,
                        outer;
                        color = color,
                        label = string(labels[ix]),
                        linestyle = opts.linestyle,
                        linewidth = opts.linewidth,
                    )
                end
            end
        else
            for ix in draw_order
                color = seriescolor[ix]
                if opts.stair
                    CairoMakie.stairs!(
                        plot.axis,
                        time_range_float,
                        data[:, ix];
                        color = color,
                        label = string(labels[ix]),
                        linestyle = opts.linestyle,
                        linewidth = opts.linewidth,
                        step = :post,
                    )
                else
                    CairoMakie.lines!(
                        plot.axis,
                        time_range_float,
                        data[:, ix];
                        color = color,
                        label = string(labels[ix]),
                        linestyle = opts.linestyle,
                        linewidth = opts.linewidth,
                    )
                end
            end
        end

        tick_positions = [time_range_float[1], last(time_range_float)]
        tick_labels = string.([time_range[1], last(time_range)])
        plot.axis.xticks = (tick_positions, tick_labels)
    end

    CairoMakie.reset_limits!(plot.axis)

    plot.series_count += length(labels)

    if plot.series_count > 0
        if plot.has_legend
            # Collect first, then delete — calling `delete!` on a Legend
            # mutates `plot.figure.content`, so iterating it directly is unsafe.
            old_legends =
                [elem for elem in plot.figure.content if elem isa CairoMakie.Legend]
            for elem in old_legends
                delete!(elem)
            end
        end

        legend_kwargs = Dict{Symbol, Any}()
        if !isnothing(opts.legend_font_size)
            legend_kwargs[:labelsize] = opts.legend_font_size
        end

        if opts.legend_position == :bottom
            if !isnothing(bar_legend_entries)
                bar_labels, bar_colors = bar_legend_entries
                elems = [CairoMakie.PolyElement(; color = c) for c in bar_colors]
                CairoMakie.Legend(
                    plot.figure[2, 1],
                    elems,
                    bar_labels;
                    orientation = :horizontal,
                    tellwidth = false,
                    tellheight = true,
                    legend_kwargs...,
                )
            else
                CairoMakie.Legend(
                    plot.figure[2, 1],
                    plot.axis;
                    orientation = :horizontal,
                    tellwidth = false,
                    tellheight = true,
                    legend_kwargs...,
                )
            end
        else
            if !isnothing(bar_legend_entries)
                bar_labels, bar_colors = bar_legend_entries
                elems = [CairoMakie.PolyElement(; color = c) for c in bar_colors]
                CairoMakie.Legend(
                    plot.figure[1, 2],
                    elems,
                    bar_labels;
                    legend_kwargs...,
                )
            else
                CairoMakie.Legend(plot.figure[1, 2], plot.axis; legend_kwargs...)
            end
        end
        plot.has_legend = true
    end

    opts.set_display && display(plot.figure)

    if !isnothing(opts.save_file)
        save_plot(plot, opts.save_file, backend; kwargs...)
    end

    return plot
end

# Two-arg `save_plot` for CairoMakie plots; inferred from the plot type so callers
# can write `save_plot(p, "out.png")` regardless of which backend produced `p`.
function PowerGraphics.save_plot(plot::CairoMakiePlot, filename::String; kwargs...)
    return PowerGraphics.save_plot(
        plot,
        filename,
        PowerGraphics.CairoMakieBackend();
        kwargs...,
    )
end

function PowerGraphics.save_plot(
    plot::CairoMakiePlot,
    filename::String,
    backend::PowerGraphics.CairoMakieBackend;
    kwargs...,
)
    ext = lowercase(last(splitext(filename)))
    if ext == ".html"
        throw(
            ArgumentError(
                "HTML output is not supported by the CairoMakie backend; " *
                "pass `backend = PlotlyLightBackend()` to the plot function or " *
                "choose a raster/vector format such as png, pdf, or svg.",
            ),
        )
    end
    CairoMakie.save(filename, plot.figure)
    @info "saved plot" filename
    return filename
end
