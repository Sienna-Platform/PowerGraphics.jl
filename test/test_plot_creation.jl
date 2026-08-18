file_path = TEST_OUTPUTS

function test_plots(file_path::String; backend_pkg::String = "cairomakie")
    # Select plot functions based on backend
    if backend_pkg == "cairomakie"
        plot_dataframe_fn = plot_dataframe
        plot_dataframe_fn! = plot_dataframe!
        plot_demand_fn = plot_demand
        plot_fuel_fn = plot_fuel
    elseif backend_pkg == "plotlylight"
        plot_dataframe_fn = plot_dataframe_plotly
        plot_dataframe_fn! = plot_dataframe_plotly!
        plot_demand_fn = plot_demand_plotly
        plot_fuel_fn = plot_fuel_plotly
    else
        throw(error("$backend_pkg backend_pkg not supported"))
    end

    set_display = false
    cleanup = true
    @info("running tests with $backend_pkg with display $set_display and cleanup $cleanup")

    outputs = TEST_OUTPUTS_DATA
    gen_df = PA.compute(
        PA.Metrics.calc_active_power,
        outputs,
        PA.Selectors.categorized_generators,
    )
    gen_data = PA.get_data_df(gen_df)
    gen_time = PA.get_time_vec(gen_df)
    load_df =
        PA.compute(PA.Metrics.calc_load_forecast, outputs, PA.Selectors.all_loads)

    @testset "test $backend_pkg plot production" begin
        out_path = joinpath(file_path, backend_pkg * "_plots")
        !isdir(out_path) && mkdir(out_path)
        plot_dataframe_fn(
            gen_data,
            gen_time;
            set_display = set_display,
            title = "df_line",
            save = out_path,
        )
        plot_dataframe_fn(
            gen_data,
            gen_time;
            set_display = set_display,
            title = "df_stack",
            save = out_path,
            stack = true,
        )
        plot_dataframe_fn(
            gen_data,
            gen_time;
            set_display = set_display,
            title = "df_stair",
            save = out_path,
            stair = true,
        )
        plot_dataframe_fn(
            gen_data,
            gen_time;
            set_display = set_display,
            title = "df_bar",
            save = out_path,
            bar = true,
        )
        plot_dataframe_fn(
            gen_data,
            gen_time;
            set_display = set_display,
            title = "df_bar_stack",
            save = out_path,
            bar = true,
            stack = true,
        )
        plot_dataframe_fn!(
            plot_dataframe_fn(gen_data, gen_time; set_display = set_display, stack = true),
            PA.get_data_df(load_df) .* -1,
            gen_time;
            set_display = set_display,
            title = "df_gen_load",
            save = out_path,
        )

        list = readdir(out_path)
        # PlotlyLight only supports HTML export, CairoMakie supports PNG
        file_ext = backend_pkg == "plotlylight" ? ".html" : ".png"
        expected_files = [
            "df_line$file_ext",
            "df_stack$file_ext",
            "df_stair$file_ext",
            "df_bar$file_ext",
            "df_bar_stack$file_ext",
            "df_gen_load$file_ext",
        ]
        # expected results not created
        @test isempty(setdiff(expected_files, list))
        # extra results created
        @test isempty(setdiff(list, expected_files))

        @info("removing test files")
        cleanup && rm(out_path; recursive = true)
    end

    # `plot_powerdata`/`plot_powerdata_plotly` were deleted in the refactor onto PA's
    # metrics API -- `plot_dataframe`/`plot_dataframe_plotly` (tested above) took over
    # their role. See src/call_plots.jl and the PG refactor plan for the rationale.

    @testset "test $backend_pkg demand plot production" begin
        out_path = joinpath(file_path, backend_pkg * "_demand_plots")
        !isdir(out_path) && mkdir(out_path)
        plot_demand_fn(
            outputs;
            set_display = set_display,
            title = "demand",
            save = out_path,
            bar = false,
            stack = false,
            nofill = false,
            filter_func = x -> get_name(get_bus(x)) == "nodeB",
        )
        plot_demand_fn(
            outputs;
            set_display = set_display,
            title = "demand_stack",
            save = out_path,
            bar = false,
            stack = true,
            nofill = false,
        )
        plot_demand_fn(
            outputs;
            set_display = set_display,
            title = "demand_bar",
            save = out_path,
            bar = true,
            stack = false,
            nofill = false,
        )
        plot_demand_fn(
            outputs;
            set_display = set_display,
            title = "demand_bar_stack",
            save = out_path,
            bar = true,
            stack = true,
            nofill = false,
        )
        plot_demand_fn(
            outputs;
            set_display = set_display,
            title = "demand_nofill",
            save = out_path,
            bar = false,
            stack = false,
            nofill = true,
        )
        plot_demand_fn(
            outputs;
            set_display = set_display,
            title = "demand_nofill_stack",
            save = out_path,
            bar = false,
            stack = true,
            nofill = true,
        )
        plot_demand_fn(
            outputs;
            set_display = set_display,
            title = "demand_nofill_bar",
            save = out_path,
            bar = true,
            stack = false,
            nofill = true,
        )
        plot_demand_fn(
            outputs;
            set_display = set_display,
            title = "demand_nofill_bar_stack",
            save = out_path,
            bar = true,
            stack = true,
            nofill = true,
        )

        # The bare-`PSY.System` branch (`_system_demand_dataframe`) reads load forecasts
        # directly off the system's time series rather than through PA.compute.
        # `outputs`' attached system (`IS.get_source_data`) is the exact in-memory system
        # `_build_test_outputs` built and solved -- never round-tripped through
        # serialization -- so its load forecasts are intact; the old workaround here
        # (building a separate system because PSI didn't serialize load time series with
        # simulation results) no longer applies.
        sys = IS.get_source_data(outputs)
        p = plot_demand_fn(
            sys;
            set_display = set_display,
            title = "sysdemand",
            save = out_path,
            aggregate = "System",
        )
        plot_length = backend_pkg == "cairomakie" ? p.series_count : length(p.data)
        @test plot_length == 1

        p = plot_demand_fn(
            sys;
            set_display = set_display,
            title = "sysdemand_bus",
            save = out_path,
            aggregate = "Bus",
        )
        plot_length = backend_pkg == "cairomakie" ? p.series_count : length(p.data)
        @test plot_length == 3

        list = readdir(out_path)
        # PlotlyLight only supports HTML export, CairoMakie supports PNG
        file_ext = backend_pkg == "plotlylight" ? ".html" : ".png"
        expected_files = [
            "demand$file_ext",
            "demand_stack$file_ext",
            "demand_bar$file_ext",
            "demand_bar_stack$file_ext",
            "demand_nofill$file_ext",
            "demand_nofill_stack$file_ext",
            "demand_nofill_bar$file_ext",
            "demand_nofill_bar_stack$file_ext",
            "sysdemand$file_ext",
            "sysdemand_bus$file_ext",
        ]
        # expected results not created
        @test isempty(setdiff(expected_files, list))
        # extra results created
        @test isempty(setdiff(list, expected_files))

        @info("removing test files")
        cleanup && rm(out_path; recursive = true)
    end

    @testset "test $backend_pkg fuel plot production" begin
        out_path = joinpath(file_path, backend_pkg * "_fuel_plots")
        !isdir(out_path) && mkdir(out_path)

        # `plot_fuel`'s `filter_func` kwarg from the old API is gone -- it is stripped,
        # unused, before the generator-category selector runs (`# Accepted Key Words` in
        # src/call_plots.jl no longer documents it) -- so it is not exercised here.
        plot_fuel_fn(
            outputs;
            set_display = set_display,
            title = "fuel",
            save = out_path,
            bar = false,
            stack = false,
        )
        plot_fuel_fn(
            outputs;
            set_display = set_display,
            title = "fuel_stack",
            save = out_path,
            bar = false,
            stack = true,
        )
        plot_fuel_fn(
            outputs;
            set_display = set_display,
            title = "fuel_bar",
            save = out_path,
            bar = true,
            stack = false,
        )
        plot_fuel_fn(
            outputs;
            set_display = set_display,
            title = "fuel_bar_stack",
            save = out_path,
            bar = true,
            stack = true,
        )

        list = readdir(out_path)
        # PlotlyLight only supports HTML export, CairoMakie supports PNG
        file_ext = backend_pkg == "plotlylight" ? ".html" : ".png"
        expected_files = [
            "fuel$file_ext",
            "fuel_stack$file_ext",
            "fuel_bar$file_ext",
            "fuel_bar_stack$file_ext",
        ]
        # expected results not created
        @test isempty(setdiff(expected_files, list))
        # extra results created
        @test isempty(setdiff(list, expected_files))

        @info("removing test files")
        cleanup && rm(out_path; recursive = true)
    end

    @testset "test alternate mapping yamls" begin
        # Alternate color palette makes curtailment hot pink
        out_path = joinpath(file_path, backend_pkg * "_alternate_palette")
        !isdir(out_path) && mkdir(out_path)

        palette = PG.load_palette(joinpath(TEST_DIR, "test_yamls/color-palette.yaml"))

        plot_fuel_fn(
            outputs;
            set_display = set_display,
            title = "fuel",
            save = out_path,
            bar = true,
            generator_mapping_file = joinpath(
                TEST_DIR,
                "test_yamls/generator_mapping.yaml",
            ),
            palette = palette,
        )
        list = readdir(out_path)
        # PlotlyLight only supports HTML export, CairoMakie supports PNG
        file_ext = backend_pkg == "plotlylight" ? ".html" : ".png"
        expected_files = ["fuel$file_ext"]
        @test isempty(setdiff(expected_files, list))
        @test isempty(setdiff(list, expected_files))

        @info "removing alternate test fuel outputs"
        cleanup && rm(out_path; recursive = true)
    end

    # HTML saving only works with PlotlyLight backend
    if backend_pkg == "plotlylight"
        @testset "test html saving" begin
            plot_fuel_fn(
                outputs;
                set_display = false,
                save = TEST_RESULT_DIR,
                title = "fuel_html_output",
                format = "html",
            )
            @test isfile(joinpath(TEST_RESULT_DIR, "fuel_html_output.html"))
        end
    end
end
try
    test_plots(file_path; backend_pkg = "cairomakie")
    @info("done with CairoMakie, starting plotlylight")
    test_plots(file_path; backend_pkg = "plotlylight")
finally
    nothing
end
