# CairoMakie backend implementation

# Wrapper for CairoMakie plots to track series and support multiple plot calls
mutable struct CairoMakiePlot
    figure::CairoMakie.Figure
    axis::CairoMakie.Axis
    series_count::Int
    has_legend::Bool  # Track if legend has been created
end

function _empty_plot(backend::CairoMakieBackend)
    fig = CairoMakie.Figure()
    ax = CairoMakie.Axis(fig[1, 1])
    return CairoMakiePlot(fig, ax, 0, false)
end

function _dataframe_plots_internal(
    plot::Union{CairoMakiePlot, Nothing},
    variable::DataFrames.DataFrame,
    time_range::Array,
    backend::CairoMakieBackend;
    kwargs...,
)
    # Get plot kwargs
    save_fig = get(kwargs, :save, nothing)
    title = get(kwargs, :title, " ")
    bar = get(kwargs, :bar, false)
    stack = get(kwargs, :stack, false)
    nofill = get(kwargs, :nofill, false)
    stair = get(kwargs, :stair, false)
    label_fn = get(kwargs, :label_fn, label_short)
    linestyle = get(kwargs, :linestyle, :solid)
    linewidth = get(kwargs, :linewidth, 1)

    time_interval = IS.convert_compound_period(
        length(time_range) * (time_range[2] - time_range[1]),
    )
    interval =
        Dates.Millisecond(Dates.Hour(1)) / Dates.Millisecond(time_range[2] - time_range[1])

    if isnothing(plot)
        plot = _empty_plot(backend)
    end

    # Get colors
    existing_series = plot.series_count
    seriescolor = set_seriescolor(
        get(
            kwargs,
            :seriescolor,
            get_palette_cairomakie(get(kwargs, :palette, PALETTE)),
        ),
        vcat(ones(existing_series), DataFrames.names(variable)),
    )[(existing_series + 1):end]

    if isempty(variable)
        @warn "Plot dataframe empty: skipping plot creation"
        return plot
    end

    # CairoMakie.band doesn't allow for DateTime axes. Every plot now gets
    # float axes instead so plots can be layered on the same Axis.
    time_range_float = Dates.datetime2unix.(time_range)

    data = Matrix(PA.no_datetime(variable))
    labels = DataFrames.names(PA.no_datetime(variable))
    labels = [label_fn(label) for label in labels]

    # Set axis properties
    plot.axis.xlabel = "$time_interval"
    plot.axis.ylabel = get(kwargs, :y_label, "")
    if title != " "  # Only set title if not default
        plot.axis.title = title
    end

    if bar
        # Bar plot
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

            # Set x-axis to show single bar
            plot.axis.xticks = ([1], [""])
        else
            # Grouped bar plot
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
        end
        plot.axis.xgridvisible = false
    else
        # Line plot
        if stack && !nofill
            # Stacked area plot
            cumulative = zeros(length(time_range_float))
            for ix in 1:length(labels)
                upper = cumulative .+ data[:, ix]
                color = seriescolor[ix]

                # Use stairs or band based on stair option
                if stair
                    # For stair plots, use stairs with fill
                    CairoMakie.stairs!(
                        plot.axis,
                        time_range_float,
                        upper;
                        color = color,
                        label = string(labels[ix]),
                        step = :post,
                        linestyle = linestyle,
                        linewidth = linewidth,
                    )
                    # Add band for fill
                    CairoMakie.band!(
                        plot.axis,
                        time_range_float,
                        cumulative,
                        upper;
                        color = (color, 0.3),
                    )
                else
                    # Regular area plot
                    CairoMakie.band!(
                        plot.axis,
                        time_range_float,
                        cumulative,
                        upper;
                        color = (color, 0.5),
                        label = string(labels[ix]),
                    )
                    # Add line on top for better visibility
                    CairoMakie.lines!(
                        plot.axis,
                        time_range_float,
                        upper;
                        color = color,
                        linestyle = linestyle,
                        linewidth = linewidth,
                    )
                end
                cumulative = upper
            end
        elseif stack && nofill
            # Stacked lines without fill
            cumulative = zeros(length(time_range_float))
            for ix in 1:length(labels)
                cumulative .+= data[:, ix]
                color = seriescolor[ix]
                if stair
                    CairoMakie.stairs!(
                        plot.axis,
                        time_range_float,
                        cumulative;
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
                        cumulative;
                        color = color,
                        label = string(labels[ix]),
                        linestyle = linestyle,
                        linewidth = linewidth,
                    )
                end
            end
        else
            # Regular line plot (no stacking)
            for ix in 1:length(labels)
                color = seriescolor[ix]
                plot_func = stair ? CairoMakie.stairs! : CairoMakie.lines!
                plot_kwargs = Dict(
                    :color => color,
                    :label => string(labels[ix]),
                    :linestyle => linestyle,
                    :linewidth => linewidth,
                )
                if stair
                    plot_kwargs[:step] = :post
                end
                plot_func(plot.axis, time_range_float, data[:, ix]; plot_kwargs...)
            end
        end

        tick_positions = [time_range_float[1], last(time_range_float)]
        tick_labels = string.([time_range[1], last(time_range)])
        plot.axis.xticks = (tick_positions, tick_labels)
    end

    # Reset axes limits
    CairoMakie.reset_limits!(plot.axis)

    # Update series count
    plot.series_count += length(labels)

    # Add or update legend if there are series
    # Delete old legend if it exists, then create a new one
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

    # Display if requested
    get(kwargs, :set_display, true) && display(plot.figure)

    # Save if requested
    title = title == " " ? "dataframe" : title
    if !isnothing(save_fig)
        format = get(kwargs, :format, "png")
        save_plot(plot, joinpath(save_fig, "$title.$format"), backend; kwargs...)
    end

    return plot
end

# Two-arg `save_plot` for CairoMakie plots; inferred from the plot type so callers
# can write `save_plot(p, "out.png")` regardless of which backend produced `p`.
function save_plot(plot::CairoMakiePlot, filename::String; kwargs...)
    return save_plot(plot, filename, CairoMakieBackend(); kwargs...)
end

function save_plot(
    plot::CairoMakiePlot,
    filename::String,
    backend::CairoMakieBackend;
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
