# CairoMakie backend implementation

# Wrapper for CairoMakie plots to track series and support multiple plot calls
mutable struct CairoMakiePlot
    figure::CairoMakie.Figure
    axis::CairoMakie.Axis
    series_count::Int
    has_legend::Bool  # Track if legend has been created
end

function PowerGraphics._empty_plot(backend::PowerGraphics.CairoMakieBackend)
    fig = CairoMakie.Figure()
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
    # Get plot kwargs
    save_fig = get(kwargs, :save, nothing)
    title = get(kwargs, :title, " ")
    bar = get(kwargs, :bar, false)
    stack = get(kwargs, :stack, false)
    nofill = get(kwargs, :nofill, false)
    stair = get(kwargs, :stair, false)

    time_interval =
        PowerGraphics.IS.convert_compound_period(length(time_range) * (time_range[2] - time_range[1]))
    interval =
        Dates.Millisecond(Dates.Hour(1)) / Dates.Millisecond(time_range[2] - time_range[1])

    if isnothing(plot)
        plot = _empty_plot(backend)
    end

    # Get colors
    existing_series = plot.series_count
    seriescolor = PowerGraphics.set_seriescolor(
        get(kwargs, :seriescolor, PowerGraphics.get_palette_cairomakie(get(kwargs, :palette, PowerGraphics.PALETTE))),
        vcat(ones(existing_series), DataFrames.names(variable)),
    )[(existing_series + 1):end]

    if isempty(variable)
        @warn "Plot dataframe empty: skipping plot creation"
        return plot
    end

    # CairoMakie.band doesn't allow for DateTime axes. Every plot now gets
    # float axes instead so plots can be layered on the same Axis.
    time_range_float = Dates.datetime2unix.(time_range)

    data = Matrix(PowerGraphics.PA.no_datetime(variable))
    labels = DataFrames.names(PowerGraphics.PA.no_datetime(variable))

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
            for (i, label) in enumerate(labels)
                CairoMakie.barplot!(
                    plot.axis,
                    [1],                        # x position
                    [plot_data[i]],             # height
                    stack = [1],                # same stack group
                    color = seriescolor[i],
                    label = string(label)                 # legend label
                )
            end
            cum = 0
            for (i, val) in enumerate(plot_data)
                CairoMakie.text!(
                    plot.axis,
                    1,                          # x
                    cum + val/2,                # center of segment
                    text = string(val),
                    align = (:center, :center)
                )
                cum += val
            end

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
                    )
                else
                    CairoMakie.lines!(
                        plot.axis,
                        time_range_float,
                        cumulative;
                        color = color,
                        label = string(labels[ix]),
                    )
                end
            end
        else
            # Regular line plot (no stacking)
            for ix in 1:length(labels)
                color = seriescolor[ix]
                plot_func = stair ? CairoMakie.stairs! : CairoMakie.lines!
                plot_kwargs = Dict(:color => color, :label => string(labels[ix]))
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
            # Remove the old legend before creating a new one
            for elem in plot.figure.content
                if elem isa CairoMakie.Legend
                    delete!(elem)
                end
            end
        end
        # Create legend outside the axis area (similar to Plots.jl :outerright)
        CairoMakie.Legend(plot.figure[1, 2], plot.axis)
        plot.has_legend = true
    end

    # Display if requested
    get(kwargs, :set_display, false) && display(plot.figure)

    # Save if requested
    title = title == " " ? "dataframe" : title
    !isnothing(save_fig) &&
        save_plot(plot, joinpath(save_fig, "$(title).png"), backend; kwargs...)

    return plot
end

function PowerGraphics.save_plot(plot::CairoMakiePlot, filename::String, backend::PowerGraphics.CairoMakieBackend; kwargs...)
    CairoMakie.save(filename, plot.figure)
    @info "saved plot" filename
    return filename
end