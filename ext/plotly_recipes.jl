# PlotlyLight backend implementation

function PowerGraphics._empty_plot(backend::PowerGraphics.PlotlyLightBackend)
    return PlotlyLight.Plot()
end

function PowerGraphics._dataframe_plots_internal(
    plot::PlotlyLight.Plot,
    variable::DataFrames.DataFrame,
    time_range::Array,
    backend::PowerGraphics.PlotlyLightBackend,
    opts::PowerGraphics._PlotOptions;
    kwargs...,
)
    ndf = PowerGraphics.PA.no_datetime(variable)
    names = [opts.label_fn(name) for name in DataFrames.names(ndf)]
    plot_length = length(plot.data)
    seriescolor = permutedims(
        PowerGraphics.set_seriescolor(
            get(
                kwargs,
                :seriescolor,
                PowerGraphics.get_palette_seriescolor(
                    backend,
                    get(kwargs, :palette, PowerGraphics.PALETTE),
                ),
            ),
            vcat(ones(plot_length), names),
        )[(plot_length + 1):end],
    )

    time_interval = PowerGraphics.IS.convert_compound_period(
        length(time_range) * (time_range[2] - time_range[1]),
    )
    interval =
        Dates.Millisecond(Dates.Hour(1)) / Dates.Millisecond(time_range[2] - time_range[1])

    plot_data = Matrix(ndf)
    if opts.power_scale != 1.0
        plot_data = plot_data ./ opts.power_scale
    end

    line_shape = opts.stair ? "hv" : "linear"
    # Plotly spells the canonical `linestyle::Symbol` as a string.
    line_dash = string(opts.linestyle)

    if opts.bar
        plot_data = sum(plot_data; dims = 1) ./ interval
        if opts.nofill
            plot_data = [plot_data; plot_data]
            x_data = [-0.5, 0.5]
            for ix = 1:length(names)
                y_data = plot_data[:, ix]
                sign_group = sum(y_data) >= 0 ? 0 : 10

                trace_config = PlotlyLight.Config(;
                    type = "scatter",
                    x = x_data,
                    y = y_data,
                    mode = "lines",
                    name = names[ix],
                    line = PlotlyLight.Config(;
                        color = seriescolor[ix],
                        dash = line_dash,
                        width = opts.linewidth,
                        shape = line_shape,
                    ),
                    showlegend = true,
                )

                if opts.stack
                    trace_config.stackgroup = string(plot_length + 1 + sign_group)
                    trace_config.fillcolor = "transparent"
                end

                plot(trace_config)
            end
        else
            for ix = 1:length(names)
                y_data = vec(plot_data[:, ix])
                sign_group = sum(y_data) >= 0 ? 0 : 10

                trace_config = PlotlyLight.Config(;
                    type = "bar",
                    y = y_data,
                    marker = PlotlyLight.Config(; color = seriescolor[ix]),
                    name = names[ix],
                    showlegend = true,
                )

                if opts.stack
                    trace_config.stackgroup = string(plot_length + 1 + sign_group)
                    trace_config.fillcolor = seriescolor[ix]
                end

                plot(trace_config)
            end
        end
    else
        for ix in PowerGraphics._series_draw_order(plot_data)
            data_to_plot = plot_data[:, ix]
            sign_group = sum(data_to_plot) >= 0 ? 0 : 10

            trace_config = PlotlyLight.Config(;
                type = "scatter",
                x = time_range,
                y = data_to_plot,
                mode = "lines",
                name = names[ix],
                line = PlotlyLight.Config(;
                    color = seriescolor[ix],
                    dash = line_dash,
                    width = opts.linewidth,
                    shape = line_shape,
                ),
                showlegend = true,
            )

            if opts.stack
                trace_config.stackgroup = string(plot_length + 1 + sign_group)
                if opts.nofill
                    trace_config.fillcolor = "transparent"
                else
                    trace_config.fill = "tonexty"
                    trace_config.fillcolor = seriescolor[ix]
                end
            elseif !opts.nofill
                trace_config.stackgroup = string(ix + plot_length)
                trace_config.fill = "tonexty"
            end

            plot(trace_config)
        end
    end

    plot.layout.yaxis.showticklabels = true
    plot.layout.yaxis.rangemode = "tozero"
    plot.layout.yaxis.title.text = opts.y_label
    plot.layout.xaxis.showticklabels = !opts.bar
    plot.layout.xaxis.title.text = string(time_interval)
    if !isnothing(opts.title)
        plot.layout.title.text = opts.title
    end
    plot.layout.barmode = opts.stack ? "relative" : "group"

    if opts.legend_position == :bottom
        plot.layout.legend = PlotlyLight.Config(;
            orientation = "h",
            x = 0,
            y = -0.2,
            xanchor = "left",
            yanchor = "top",
        )
    end
    if !isnothing(opts.legend_font_size)
        plot.layout.legend.font = PlotlyLight.Config(; size = opts.legend_font_size)
    end

    opts.set_display && display(plot)
    if !isnothing(opts.save_file)
        save_plot(plot, opts.save_file, backend; kwargs...)
    end
    return plot
end

const SUPPORTED_PLOTLY_SAVE_KWARGS =
    [:autoplay, :post_script, :full_html, :animation_opts, :default_width, :default_height]

# Two-arg `save_plot` for PlotlyLight plots; inferred from the plot type so
# callers can write `save_plot(p, "out.html")` and hit the right backend.
function PowerGraphics.save_plot(plot::PlotlyLight.Plot, filename::String; kwargs...)
    return PowerGraphics.save_plot(
        plot,
        filename,
        PowerGraphics.PlotlyLightBackend();
        kwargs...,
    )
end

function PowerGraphics.save_plot(
    plot,
    filename::String,
    backend::PowerGraphics.PlotlyLightBackend;
    kwargs...,
)
    save_kwargs =
        Dict{Symbol, Any}(((k, v) for (k, v) in kwargs if k in SUPPORTED_PLOTLY_SAVE_KWARGS))
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
