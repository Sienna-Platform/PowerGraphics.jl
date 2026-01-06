# CairoMakie backend implementation

# Wrapper for CairoMakie plots to track series and support multiple plot calls
mutable struct CairoMakiePlot
    figure::CairoMakie.Figure
    axis::CairoMakie.Axis
    series_count::Int
    has_legend::Bool  # Track if legend has been created
end

function set_seriescolor(seriescolor::Array, vars::Array)
    color_length = length(seriescolor)
    var_length = length(vars)
    n = Int(ceil(var_length / color_length))
    colors = repeat(seriescolor, n)[1:var_length]
    return colors
end

function _empty_plot(backend::CairoMakieBackend)
    fig = CairoMakie.Figure()
    ax = CairoMakie.Axis(fig[1, 1])
    return CairoMakiePlot(fig, ax, 0, false)
end

function _get_ylims(plot::CairoMakiePlot, plot_data)
    maxnan(a) = maximum(x -> isnan(x) ? -Inf : x, a)
    minnan(a) = minimum(x -> isnan(x) ? Inf : x, a)

    series_min, series_max = minnan(plot_data), maxnan(plot_data)

    # Get existing limits from axis if there are already series
    if plot.series_count > 0
        existing_limits = CairoMakie.ylims(plot.axis)
        series_min = min(existing_limits[1], series_min)
        series_max = max(existing_limits[2], series_max)
    end

    ymin = series_min <= 0.0 ? nothing : 0.0
    ymax = series_max >= 0.0 ? nothing : 0.0

    return (ymin, ymax)
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

    time_interval =
        IS.convert_compound_period(length(time_range) * (time_range[2] - time_range[1]))
    interval =
        Dates.Millisecond(Dates.Hour(1)) / Dates.Millisecond(time_range[2] - time_range[1])

    if isnothing(plot)
        plot = _empty_plot(backend)
    end

    # Get colors
    existing_series = plot.series_count
    seriescolor = set_seriescolor(
        get(kwargs, :seriescolor, get_palette_cairomakie(get(kwargs, :palette, PALETTE))),
        vcat(ones(existing_series), DataFrames.names(variable)),
    )[(existing_series + 1):end]

    if isempty(variable)
        @warn "Plot dataframe empty: skipping plot creation"
        return plot
    end

    data = Matrix(PA.no_datetime(variable))
    labels = DataFrames.names(PA.no_datetime(variable))

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
            # Stacked bar plot
            x_pos = 1
            cumulative = 0.0
            for (ix, label) in enumerate(reverse(labels))
                val = plot_data[end - ix + 1]
                color = seriescolor[end - ix + 1]
                CairoMakie.barplot!(
                    plot.axis,
                    [x_pos],
                    [val];
                    color = color,
                    offset = cumulative,
                    label = string(label),
                )
                cumulative += val
            end
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
            plot.axis.xticks = (x_positions, string.(labels))
        end
        plot.axis.xgridvisible = false
    else
        # Line plot
        if stack && !nofill
            # Stacked area plot
            cumulative = zeros(length(time_range))
            for ix in 1:length(labels)
                upper = cumulative .+ data[:, ix]
                color = seriescolor[ix]
                CairoMakie.band!(
                    plot.axis,
                    time_range,
                    cumulative,
                    upper;
                    color = (color, 0.5),
                    label = string(labels[ix]),
                )
                # Add line on top
                CairoMakie.lines!(
                    plot.axis,
                    time_range,
                    upper;
                    color = color,
                    linestyle = stair ? :steppost : :solid,
                )
                cumulative = upper
            end
        elseif stack && nofill
            # Stacked lines without fill
            cumulative = zeros(length(time_range))
            for ix in 1:length(labels)
                cumulative .+= data[:, ix]
                color = seriescolor[ix]
                if stair
                    CairoMakie.stairs!(
                        plot.axis,
                        time_range,
                        cumulative;
                        color = color,
                        label = string(labels[ix]),
                        step = :post,
                    )
                else
                    CairoMakie.lines!(
                        plot.axis,
                        time_range,
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
                plot_func(plot.axis, time_range, data[:, ix]; plot_kwargs...)
            end
        end

        # Set y-axis limits
        ylims_tuple = get(kwargs, :ylims, _get_ylims(plot, data))
        if !isnothing(ylims_tuple[1]) || !isnothing(ylims_tuple[2])
            CairoMakie.ylims!(plot.axis, ylims_tuple...)
        end

        # Set x-axis ticks
        plot.axis.xticks = [time_range[1], last(time_range)]
    end

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

function save_plot(plot::CairoMakiePlot, filename::String, backend::CairoMakieBackend; kwargs...)
    CairoMakie.save(filename, plot.figure)
    @info "saved plot" filename
    return filename
end
