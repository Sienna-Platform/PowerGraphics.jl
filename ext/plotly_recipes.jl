# PlotlyLight backend implementation

function PowerGraphics._empty_plot(backend::PowerGraphics.PlotlyLightBackend)
    # Create an empty plot using PlotlyLight
    return PlotlyLight.Plot()
end

function PowerGraphics._dataframe_plots_internal(
    plot,
    variable::DataFrames.DataFrame,
    time_range::Array,
    backend::PowerGraphics.PlotlyLightBackend;
    kwargs...,
)
    save_fig = get(kwargs, :save, nothing)
    y_label = get(kwargs, :y_label, "")
    title = get(kwargs, :title, " ")
    stack = get(kwargs, :stack, false)
    bar = get(kwargs, :bar, false)
    nofill = get(kwargs, :nofill, !bar && !stack)
    label_fn = get(kwargs, :label_fn, s -> s)

    names = DataFrames.names(PowerGraphics.PA.no_datetime(variable))
    names = [label_fn(name) for name in names]
    plot_length = length(plot.data)
    seriescolor = permutedims(
        PowerGraphics.set_seriescolor(
            get(kwargs, :seriescolor, PowerGraphics.get_palette_plotly(get(kwargs, :palette, PowerGraphics.PALETTE))),
            vcat(ones(plot_length), names),
        )[(plot_length + 1):end],
    )

    time_interval =
        PowerGraphics.IS.convert_compound_period(length(time_range) * (time_range[2] - time_range[1]))
    interval =
        Dates.Millisecond(Dates.Hour(1)) / Dates.Millisecond(time_range[2] - time_range[1])

    isnothing(plot) && _empty_plot(backend)

    if isempty(variable)
        @warn "Plot dataframe empty: skipping plot creation"
        plot_data = Array{Float64}(undef, 0, 0)
    else
        plot_data = Matrix(PowerGraphics.PA.no_datetime(variable))
    end

    plot_type = bar ? "bar" : "scatter"
    line_shape = get(kwargs, :stair, false) ? "hv" : "linear"
    line_dash = get(kwargs, :line_dash, "solid")

    if bar
        plot_data = sum(plot_data; dims = 1) ./ interval
        if nofill
            # Line plot for bar with nofill
            plot_data = [plot_data; plot_data]
            x_data = [-0.5, 0.5]
            for ix in 1:length(names)
                y_data = plot_data[:, ix]
                sign_group = sum(y_data) >= 0 ? 0 : 10

                trace_config = PlotlyLight.Config(
                    type = "scatter",
                    x = x_data,
                    y = y_data,
                    mode = "lines",
                    name = names[ix],
                    line = PlotlyLight.Config(
                        color = seriescolor[ix],
                        dash = line_dash,
                        shape = line_shape,
                    ),
                    showlegend = true,
                )

                if stack
                    trace_config.stackgroup = string(plot_length + 1 + sign_group)
                    trace_config.fillcolor = "transparent"
                end

                plot(trace_config)
            end
        else
            # Regular bar plot
            for ix in 1:length(names)
                y_data = vec(plot_data[:, ix])
                sign_group = sum(y_data) >= 0 ? 0 : 10

                trace_config = PlotlyLight.Config(
                    type = "bar",
                    y = y_data,
                    marker = PlotlyLight.Config(color = seriescolor[ix]),
                    name = names[ix],
                    showlegend = true,
                )

                if stack
                    trace_config.stackgroup = string(plot_length + 1 + sign_group)
                    trace_config.fillcolor = seriescolor[ix]
                end

                plot(trace_config)
            end
        end
    else
        # Scatter plot
        for ix in 1:length(names)
            data_to_plot = plot_data[:, ix]
            sign_group = sum(data_to_plot) >= 0 ? 0 : 10

            trace_config = PlotlyLight.Config(
                type = "scatter",
                x = time_range,
                y = data_to_plot,
                mode = "lines",
                name = names[ix],
                line = PlotlyLight.Config(
                    color = seriescolor[ix],
                    dash = line_dash,
                    shape = line_shape,
                ),
                showlegend = true,
            )

            if stack
                trace_config.stackgroup = string(plot_length + 1 + sign_group)
                if nofill
                    trace_config.fillcolor = "transparent"
                else
                    trace_config.fill = "tonexty"
                    trace_config.fillcolor = seriescolor[ix]
                end
            elseif !nofill
                trace_config.stackgroup = string(ix + plot_length)
                trace_config.fill = "tonexty"
            end

            plot(trace_config)
        end
    end

    # Update layout
    plot.layout.yaxis.showticklabels = true
    plot.layout.yaxis.rangemode = "tozero"
    plot.layout.yaxis.title.text = y_label
    plot.layout.xaxis.showticklabels = !bar
    plot.layout.xaxis.title.text = string(time_interval)
    plot.layout.title.text = title
    plot.layout.barmode = stack ? "relative" : "group"

    get(kwargs, :set_display, true) && display(plot)
    if !isnothing(save_fig)
        title = title == " " ? "dataframe" : title
        format = get(kwargs, :format, "png")
        save_plot(plot, joinpath(save_fig, "$title.$format"), backend; kwargs...)
    end
    return plot
end

const SUPPORTED_PLOTLY_SAVE_KWARGS =
    [:autoplay, :post_script, :full_html, :animation_opts, :default_width, :default_height]

function PowerGraphics.save_plot(plot, filename::String, backend::PowerGraphics.PlotlyLightBackend; kwargs...)
    save_kwargs = Dict{Symbol, Any}((
        (k, v) for (k, v) in kwargs if k in SUPPORTED_PLOTLY_SAVE_KWARGS
    ))
    @info "saving plot" filename
    if last(splitext(filename)) == ".html"
        open(filename, "w") do io
            show(io, MIME("text/html"), plot; save_kwargs...)
        end
    else
        # PlotlyLight doesn't have built-in image export
        # Users need to save HTML and convert externally, or use PlotlyBase.jl
        @warn "PlotlyLight only supports HTML export. Saving as HTML instead." filename
        html_filename = replace(filename, r"\.[^.]+$" => ".html")
        open(html_filename, "w") do io
            show(io, MIME("text/html"), plot; save_kwargs...)
        end
        return html_filename
    end
    return filename
end