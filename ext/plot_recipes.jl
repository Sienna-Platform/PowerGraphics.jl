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

function PowerGraphics._dataframe_plots_internal(
    plot::Union{CairoMakiePlot, Nothing},
    variable::DataFrames.DataFrame,
    time_range::Array,
    backend::PowerGraphics.CairoMakieBackend;
    kwargs...,
)
    save_fig = get(kwargs, :save, nothing)
    title = get(kwargs, :title, " ")
    bar = get(kwargs, :bar, false)
    stack = get(kwargs, :stack, false)
    nofill = get(kwargs, :nofill, false)
    stair = get(kwargs, :stair, false)
    label_fn = get(kwargs, :label_fn, PowerGraphics.label_short)
    linestyle = get(kwargs, :linestyle, :solid)
    linewidth = get(kwargs, :linewidth, 1)

    time_interval = PowerGraphics.IS.convert_compound_period(
        length(time_range) * (time_range[2] - time_range[1]),
    )
    interval =
        Dates.Millisecond(Dates.Hour(1)) / Dates.Millisecond(time_range[2] - time_range[1])

    if isnothing(plot)
        plot = PowerGraphics._empty_plot(backend)
    end

    ndf = PowerGraphics.PA.no_datetime(variable)
    column_names = DataFrames.names(ndf)
    existing_series = plot.series_count
    seriescolor = PowerGraphics.set_seriescolor(
        get(
            kwargs,
            :seriescolor,
            PowerGraphics.get_palette_cairomakie(
                get(kwargs, :palette, PowerGraphics.PALETTE),
            ),
        ),
        vcat(ones(existing_series), column_names),
    )[(existing_series + 1):end]

    if isempty(variable)
        @warn "Plot dataframe empty: skipping plot creation"
        return plot
    end

    # CairoMakie.band doesn't allow for DateTime axes. Every plot now gets
    # float axes instead so plots can be layered on the same Axis.
    time_range_float = Dates.datetime2unix.(time_range)

    data = Matrix(ndf)
    power_scale = get(kwargs, :power_scale, 1.0)
    if power_scale != 1.0
        data = data ./ power_scale
    end
    labels = [label_fn(label) for label in column_names]

    plot.axis.xlabel = "$time_interval"
    plot.axis.ylabel = get(kwargs, :y_label, "")
    if title != " "  # Only set title if not default
        plot.axis.title = title
    end

    if bar
        plot_data = sum(data; dims = 1) ./ interval

        if stack
            # CairoMakie stacks within a single barplot! call when given
            # per-element stack ids. Plotting one slice per call (each with
            # stack=[1]) just overlays bars at the same x — that's what the
            # previous implementation did and it did not actually stack.
            n = length(labels)
            xs = fill(1, n)
            heights = vec(plot_data)
            CairoMakie.barplot!(
                plot.axis,
                xs,
                heights;
                stack = collect(1:n),
                color = collect(seriescolor[1:n]),
                label = string.(labels),
            )

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
        if stack && !nofill
            # Sign-aware stacked area: positive series stack upward from 0,
            # negative series (e.g. storage charging) stack downward from 0 so
            # charging renders below the zero axis.
            lower_b, upper_b = PowerGraphics._signed_stack_bounds(data)
            # Draw negative (e.g. storage charging) series first so they sit at
            # the back; positive generation bands/outlines render on top.
            is_neg = [sum(view(data, :, ix)) < 0 for ix in 1:length(labels)]
            draw_order = vcat(findall(is_neg), findall(.!is_neg))
            for ix in draw_order
                lo = lower_b[:, ix]
                up = upper_b[:, ix]
                # Outer envelope of this band (top for +ve, bottom for -ve).
                outer = ifelse.(data[:, ix] .>= 0, up, lo)
                color = seriescolor[ix]

                if stair
                    CairoMakie.stairs!(
                        plot.axis,
                        time_range_float,
                        outer;
                        color = color,
                        label = string(labels[ix]),
                        step = :post,
                        linestyle = linestyle,
                        linewidth = linewidth,
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
        elseif stack && nofill
            # Sign-aware stacked lines: outer envelope of each band (positive
            # stacked up, negative stacked down).
            lower_b, upper_b = PowerGraphics._signed_stack_bounds(data)
            is_neg = [sum(view(data, :, ix)) < 0 for ix in 1:length(labels)]
            draw_order = vcat(findall(is_neg), findall(.!is_neg))
            for ix in draw_order
                outer = ifelse.(data[:, ix] .>= 0, upper_b[:, ix], lower_b[:, ix])
                color = seriescolor[ix]
                if stair
                    CairoMakie.stairs!(
                        plot.axis,
                        time_range_float,
                        outer;
                        color = color,
                        label = string(labels[ix]),
                        step = :post,
                        linestyle = linestyle,
                        linewidth = linewidth,
                    )
                else
                    CairoMakie.lines!(
                        plot.axis,
                        time_range_float,
                        outer;
                        color = color,
                        label = string(labels[ix]),
                        linestyle = linestyle,
                        linewidth = linewidth,
                    )
                end
            end
        else
            for ix in 1:length(labels)
                color = seriescolor[ix]
                if stair
                    CairoMakie.stairs!(
                        plot.axis,
                        time_range_float,
                        data[:, ix];
                        color = color,
                        label = string(labels[ix]),
                        linestyle = linestyle,
                        linewidth = linewidth,
                        step = :post,
                    )
                else
                    CairoMakie.lines!(
                        plot.axis,
                        time_range_float,
                        data[:, ix];
                        color = color,
                        label = string(labels[ix]),
                        linestyle = linestyle,
                        linewidth = linewidth,
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

        legend_position = get(kwargs, :legend_position, :right)
        legend_font_size = get(kwargs, :legend_font_size, nothing)
        legend_kwargs = Dict{Symbol, Any}()
        if !isnothing(legend_font_size)
            legend_kwargs[:labelsize] = legend_font_size
        end

        if legend_position == :bottom
            CairoMakie.Legend(
                plot.figure[2, 1],
                plot.axis;
                orientation = :horizontal,
                tellwidth = false,
                tellheight = true,
                legend_kwargs...,
            )
        else
            CairoMakie.Legend(plot.figure[1, 2], plot.axis; legend_kwargs...)
        end
        plot.has_legend = true
    end

    get(kwargs, :set_display, true) && display(plot.figure)

    title = title == " " ? "dataframe" : title
    if !isnothing(save_fig)
        format = get(kwargs, :format, "png")
        save_plot(plot, joinpath(save_fig, "$title.$format"), backend; kwargs...)
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
                "use a `_plotly` plot function (which uses PlotlyLight) or " *
                "choose a raster/vector format such as png, pdf, or svg.",
            ),
        )
    end
    CairoMakie.save(filename, plot.figure)
    @info "saved plot" filename
    return filename
end
