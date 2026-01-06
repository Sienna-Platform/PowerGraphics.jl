# PlotlyJS backend implementation
# Note: PlotlyJS must be loaded before using this backend (using PlotlyJS)

function _get_plotlyjs()
    if !isdefined(Main, :PlotlyJS)
        error("PlotlyJS must be loaded to use PlotlyJSBackend. Run: using PlotlyJS")
    end
    return Main.PlotlyJS
end

function _empty_plot(backend::PlotlyJSBackend)
    PJS = _get_plotlyjs()
    return PJS.Plot()
end

function _dataframe_plots_internal(
    plot,
    variable::DataFrames.DataFrame,
    time_range::Array,
    backend::PlotlyJSBackend;
    kwargs...,
)
    PJS = _get_plotlyjs()

    names = DataFrames.names(PA.no_datetime(variable))
    traces = plot.data
    plot_length = length(traces)
    seriescolor = permutedims(
        set_seriescolor(
            get(kwargs, :seriescolor, get_palette_plotly(get(kwargs, :palette, PALETTE))),
            vcat(ones(plot_length), names),
        )[(plot_length + 1):end],
    )

    save_fig = get(kwargs, :save, nothing)
    y_label = get(kwargs, :y_label, "")
    title = get(kwargs, :title, " ")
    stack = get(kwargs, :stack, false)
    bar = get(kwargs, :bar, false)
    nofill = get(kwargs, :nofill, !bar && !stack)

    time_interval =
        IS.convert_compound_period(length(time_range) * (time_range[2] - time_range[1]))
    interval =
        Dates.Millisecond(Dates.Hour(1)) / Dates.Millisecond(time_range[2] - time_range[1])

    isnothing(plot) && _empty_plot(backend)

    if isempty(variable)
        @warn "Plot dataframe empty: skipping plot creation"
        plot_data = Array{Float64}(undef, 0, 0)
    else
        plot_data = Matrix(PA.no_datetime(variable))
    end

    plot_kwargs = Dict()
    if bar
        plot_data = sum(plot_data; dims = 1) ./ interval
        showtxicklabels = false
        if nofill
            plot_kwargs[:type] = "scatter"
            plot_data = [plot_data; plot_data]
            plot_kwargs[:x] = [-0.5, 0.5]
        else
            plot_kwargs[:type] = "bar"
            plot_kwargs[:fill] = "tonexty"
        end
    else
        if !nofill && stack
            plot_kwargs[:fill] = "tonexty"
        end
        plot_kwargs[:plot_type] = "scatter"
        plot_kwargs[:x] = time_range
    end

    plot_kwargs[:line_shape] = get(kwargs, :stair, false) ? "hv" : "linear"
    plot_kwargs[:mode] = "lines"
    plot_kwargs[:line_dash] = get(kwargs, :line_dash, "solid")
    plot_kwargs[:showlegend] = true

    for ix in 1:length(names)
        if bar
            plot_kwargs[:marker_color] = seriescolor[ix]
        end
        data_to_plot = plot_data[:, ix]
        if sum(data_to_plot) >= 0
            sign_group = 0
        else
            sign_group = 10
        end

        if stack
            plot_kwargs[:stackgroup] = string(plot_length + 1 + sign_group)
            if nofill
                plot_kwargs[:fillcolor] = "transparent"
            else
                plot_kwargs[:fillcolor] = seriescolor[ix]
            end
        elseif !nofill
            plot_kwargs[:stackgroup] = string(ix + plot_length)
        end
        plot_kwargs[:line_color] = seriescolor[ix]
        plot_kwargs[:name] = names[ix]
        trace = PJS.scatter(; y = plot_data[:, ix], plot_kwargs...)
        push!(traces, trace)
    end
    layout_kwargs = Dict{Symbol, Any}()
    layout_kwargs[:yaxis] =
        PJS.attr(; showticklabels = true, rangemode = "tozero", title = y_label)
    layout_kwargs[:xaxis] =
        PJS.attr(; showticklabels = !bar, title = "$time_interval")
    layout_kwargs[:title] = "$title"
    layout_kwargs[:barmode] = stack ? "relative" : "group"
    merge!(layout_kwargs, kwargs)
    PJS.relayout!(plot, PJS.Layout(; layout_kwargs...))

    get(kwargs, :set_display, true) && display(PJS.plot(plot))
    if !isnothing(save_fig)
        title = title == " " ? "dataframe" : title
        format = get(kwargs, :format, "png")
        save_plot(plot, joinpath(save_fig, "$title.$format"), backend; kwargs...)
    end
    return plot
end

function save_plot(plot, filename::String, backend::PlotlyJSBackend; kwargs...)
    PJS = _get_plotlyjs()

    save_kwargs = Dict{Symbol, Any}((
        (k, v) for (k, v) in kwargs if k in SUPPORTED_PLOTLY_SAVE_KWARGS
    ))
    @info "saving plot" filename
    if last(splitext(filename)) == ".html"
        open(filename, "w") do io
            show(io, MIME("text/html"), plot; save_kwargs...)
        end
    else
        PJS.savefig(plot, filename; save_kwargs...)
    end
    return filename
end
