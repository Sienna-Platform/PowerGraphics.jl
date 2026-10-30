file_path = TEST_OUTPUTS

function test_plots(file_path::String, investment; backend_pkg::String = "cairomakie")
    # Select plot functions based on backend
    if backend_pkg == "cairomakie"
        plot_dataframe_fn = plot_dataframe
        plot_dataframe_fn! = plot_dataframe!
        plot_demand_fn = plot_demand
        plot_powerdata_fn = PG.plot_powerdata
        plot_fuel_fn = plot_fuel
        plot_capacity_additions_fn = plot_capacity_additions
        plot_installed_capacity_fn = plot_installed_capacity
    elseif backend_pkg == "plotlylight"
        plot_dataframe_fn = plot_dataframe_plotly
        plot_dataframe_fn! = plot_dataframe_plotly!
        plot_demand_fn = plot_demand_plotly
        plot_powerdata_fn = PG.plot_powerdata_plotly
        plot_fuel_fn = plot_fuel_plotly
        plot_capacity_additions_fn = plot_capacity_additions_plotly
        plot_installed_capacity_fn = plot_installed_capacity_plotly
    else
        throw(error("$backend_pkg backend_pkg not supported"))
    end

    set_display = false
    cleanup = true
    @info("running tests with $backend_pkg with display $set_display and cleanup $cleanup")

    (results_uc, results_ed) = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)
    problem_results = run_test_prob()
    gen_uc = get_generation_data(results_uc)
    gen_ed = get_generation_data(results_ed)
    gen_pb = get_generation_data(problem_results)
    load_uc = get_load_data(results_uc)
    load_ed = get_load_data(results_ed)
    load_pb = get_load_data(problem_results)
    svc_uc = get_service_data(results_uc)
    svc_ed = get_service_data(results_ed)
    svc_pb = get_service_data(problem_results)

    @testset "test $backend_pkg plot production" begin
        out_path = joinpath(file_path, backend_pkg * "_plots")
        !isdir(out_path) && mkdir(out_path)
        plot_dataframe_fn(
            gen_uc.data[:ActivePowerVariable__RenewableDispatch],
            gen_uc.time;
            set_display = set_display,
            title = "df_line",
            save = out_path,
        )
        plot_dataframe_fn(
            gen_uc.data[:ActivePowerVariable__ThermalStandard],
            gen_uc.time;
            set_display = set_display,
            title = "df_stack",
            save = out_path,
            stack = true,
        )
        plot_dataframe_fn(
            gen_uc.data[:ActivePowerVariable__ThermalStandard],
            gen_uc.time;
            set_display = set_display,
            title = "df_stair",
            save = out_path,
            stair = true,
        )
        plot_dataframe_fn(
            gen_uc.data[:ActivePowerVariable__ThermalStandard],
            gen_uc.time;
            set_display = set_display,
            title = "df_bar",
            save = out_path,
            bar = true,
        )
        plot_dataframe_fn(
            gen_uc.data[:ActivePowerVariable__ThermalStandard],
            gen_uc.time;
            set_display = set_display,
            title = "df_bar_stack",
            save = out_path,
            bar = true,
            stack = true,
        )
        plot_dataframe_fn!(
            plot_dataframe_fn(
                gen_uc.data[:ActivePowerVariable__ThermalStandard],
                gen_uc.time;
                set_display = set_display,
                stack = true,
            ),
            no_datetime(load_uc.data[:Load]) .* -1,
            gen_uc.time;
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

    @testset "test $backend_pkg period bar plots" begin
        table = DataFrame(;
            DateTime = DateTime.([2030, 2035, 2045]),
            Storage = [25, 0, 10],
            Wind = [100.0, 20.0, 0.0],
        )
        allowmissing!(table, [:Storage, :Wind])
        original = copy(table)
        for stack in (true, false)
            plot = plot_dataframe_fn(
                table;
                bar = true,
                bar_mode = :period,
                stack = stack,
                power_scale = 10.0,
                y_label = "MW",
                legend_position = stack ? :right : :bottom,
                set_display = false,
            )
            expected = Matrix(select(table, :Storage, :Wind)) ./ 10.0
            if backend_pkg == "cairomakie"
                bars = only(plot.axis.scene.plots)
                @test getindex.(bars[1][], 1) == repeat([1, 2, 3]; outer = 2)
                @test getindex.(bars[1][], 2) == vec(expected)
                @test (stack ? bars.stack[] : bars.dodge[]) == repeat([1, 2]; inner = 3)
                @test plot.axis.xticks[] == ([1, 2, 3], ["2030", "2035", "2045"])
                @test plot.axis.ylabel[] == "MW"
            else
                @test [trace.name for trace in plot.data] == ["Storage", "Wind"]
                @test all(trace.x == ["2030", "2035", "2045"] for trace in plot.data)
                @test hcat([trace.y for trace in plot.data]...) == expected
                @test plot.layout.barmode == (stack ? "relative" : "group")
                @test plot.layout.xaxis.type == "category"
                @test plot.layout.yaxis.title.text == "MW"
            end
        end
        @test table == original
        @test eltype(table.Wind) == Union{Missing, Float64}
        single = plot_dataframe_fn(
            table[1:1, :];
            bar = true,
            bar_mode = :period,
            stack = true,
            set_display = false,
        )
        if backend_pkg == "cairomakie"
            @test getindex.(only(single.axis.scene.plots)[1][], 2) == [25.0, 100.0]
            @test single.axis.xticks[] == ([1], ["2030"])
        else
            @test [only(trace.y) for trace in single.data] == [25.0, 100.0]
            @test all(trace.x == ["2030"] for trace in single.data)
        end
        @test_throws ArgumentError plot_dataframe_fn!(
            single,
            table[1:1, :];
            bar = true,
            bar_mode = :period,
            set_display = false,
        )
        invalid = copy(table)
        invalid.Wind[1] = NaN
        @test_throws ArgumentError plot_dataframe_fn(
            invalid;
            bar = true,
            bar_mode = :period,
            set_display = false,
        )
    end

    @testset "test $backend_pkg energy bar aggregation" begin
        table = DataFrame(;
            DateTime = [DateTime(2030), DateTime(2030) + Minute(30)],
            Wind = [10.0, 20.0],
        )
        plot = plot_dataframe_fn(table; bar = true, stack = true, set_display = false)
        if backend_pkg == "cairomakie"
            @test getindex.(only(plot.axis.scene.plots)[1][], 2) == [15.0]
        else
            @test only(plot.data).y == [15.0]
        end
    end

    if backend_pkg == "plotlylight"
        @testset "test period bar inputs" begin
            valid = DataFrame(;
                DateTime = [DateTime(2030), DateTime(2035)],
                Wind = [1.0, 2.0],
            )
            for invalid in (
                valid[1:0, :],
                select(valid, :DateTime),
                reverse(valid),
                DataFrame(; DateTime = [DateTime(2030), DateTime(2030)], Wind = [1.0, 2.0]),
                DataFrame(; DateTime = [2030, 2035], Wind = [1.0, 2.0]),
                DataFrame(; DateTime = valid.DateTime, Wind = [missing, 2.0]),
            )
                @test_throws ArgumentError plot_dataframe_fn(
                    invalid;
                    bar = true,
                    bar_mode = :period,
                    set_display = false,
                )
            end
            @test_throws ArgumentError plot_dataframe_fn(
                valid;
                bar_mode = :period,
                set_display = false,
            )
            for option in (:nofill, :stair)
                @test_throws ArgumentError plot_dataframe_fn(
                    valid;
                    bar = true,
                    bar_mode = :period,
                    set_display = false,
                    option => true,
                )
            end
            @test PG._period_bar_labels([Date(2030, 1, 1), Date(2030, 7, 1)]) ==
                  ["2030-01-01", "2030-07-01"]
            @test PG._period_bar_labels([DateTime(2030), DateTime(2030) + Hour(1)]) ==
                  ["2030-01-01T00:00:00", "2030-01-01T01:00:00"]
        end
    end

    @testset "test $backend_pkg powerdata plot production" begin
        out_path = joinpath(file_path, backend_pkg * "_powerdata_plots")
        !isdir(out_path) && mkdir(out_path)

        plot_powerdata_fn(
            gen_uc;
            set_display = set_display,
            title = "pg_data",
            save = out_path,
            bar = false,
            stack = false,
        )
        plot_powerdata_fn(
            gen_uc;
            set_display = set_display,
            title = "pg_data_stack",
            save = out_path,
            bar = false,
            stack = true,
        )
        plot_powerdata_fn(
            gen_uc;
            set_display = set_display,
            title = "pg_data_bar",
            save = out_path,
            bar = true,
            stack = false,
        )
        plot_powerdata_fn(
            gen_uc;
            set_display = set_display,
            title = "pg_data_bar_stack",
            save = out_path,
            bar = true,
            stack = true,
        )

        list = readdir(out_path)
        # PlotlyLight only supports HTML export, CairoMakie supports PNG
        file_ext = backend_pkg == "plotlylight" ? ".html" : ".png"
        expected_files = [
            "pg_data$file_ext",
            "pg_data_stack$file_ext",
            "pg_data_bar$file_ext",
            "pg_data_bar_stack$file_ext",
        ]
        # expected results not created
        @test isempty(setdiff(expected_files, list))
        # extra results created
        @test isempty(setdiff(list, expected_files))

        @info("removing test files")
        cleanup && rm(out_path; recursive = true)
    end

    @testset "test $backend_pkg demand plot production" begin
        out_path = joinpath(file_path, backend_pkg * "_demand_plots")
        !isdir(out_path) && mkdir(out_path)
        plot_demand_fn(
            results_uc;
            set_display = set_display,
            title = "demand",
            save = out_path,
            bar = false,
            stack = false,
            nofill = false,
            filter_func = x -> get_name(get_bus(x)) == "bus2",
        )
        plot_demand_fn(
            results_uc;
            set_display = set_display,
            title = "demand_stack",
            save = out_path,
            bar = false,
            stack = true,
            nofill = false,
        )
        plot_demand_fn(
            results_uc;
            set_display = set_display,
            title = "demand_bar",
            save = out_path,
            bar = true,
            stack = false,
            nofill = false,
        )
        plot_demand_fn(
            results_uc;
            set_display = set_display,
            title = "demand_bar_stack",
            save = out_path,
            bar = true,
            stack = true,
            nofill = false,
        )
        plot_demand_fn(
            results_uc;
            set_display = set_display,
            title = "demand_nofill",
            save = out_path,
            bar = false,
            stack = false,
            nofill = true,
        )
        plot_demand_fn(
            results_uc;
            set_display = set_display,
            title = "demand_nofill_stack",
            save = out_path,
            bar = false,
            stack = true,
            nofill = true,
        )
        plot_demand_fn(
            results_uc;
            set_display = set_display,
            title = "demand_nofill_bar",
            save = out_path,
            bar = true,
            stack = false,
            nofill = true,
        )
        plot_demand_fn(
            results_uc;
            set_display = set_display,
            title = "demand_nofill_bar_stack",
            save = out_path,
            bar = true,
            stack = true,
            nofill = true,
        )

        # Use a freshly-built system rather than results_uc.system: PSI no longer
        # serializes load time series with simulation results, so the system
        # attached to simulation results lacks the forecasts that get_load_data needs.
        sys_with_ts = PSB.build_system(PSB.PSISystems, "5_bus_hydro_uc_sys")
        p = plot_demand_fn(
            sys_with_ts;
            set_display = set_display,
            title = "sysdemand",
            save = out_path,
            aggregate = "System",
        )
        plot_length = backend_pkg == "cairomakie" ? p.series_count : length(p.data)
        @test plot_length == 1

        p = plot_demand_fn(
            sys_with_ts;
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

        plot_fuel_fn(
            results_uc;
            set_display = set_display,
            title = "fuel",
            save = out_path,
            bar = false,
            stack = false,
            filter_func = x -> get_name(get_area(get_bus(x))) == "1",
        )
        plot_fuel_fn(
            results_uc;
            set_display = set_display,
            title = "fuel_stack",
            save = out_path,
            bar = false,
            stack = true,
        )
        plot_fuel_fn(
            results_uc;
            set_display = set_display,
            title = "fuel_bar",
            save = out_path,
            bar = true,
            stack = false,
        )
        plot_fuel_fn(
            results_uc;
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

    @testset "test $backend_pkg capacity plot production" begin
        out_path = joinpath(file_path, backend_pkg * "_capacity_plots")
        !isdir(out_path) && mkdir(out_path)
        mapping = PA.get_generator_mapping()
        selector = PA.make_selector(
            PSIP.ResourceTechnology;
            groupby = technology -> PA.get_generator_category(technology, mapping),
        )
        backend = if backend_pkg == "cairomakie"
            PG.CairoMakieBackend()
        else
            PG.PlotlyLightBackend()
        end
        for (plot_fn, metric, title) in (
            (
                plot_capacity_additions_fn,
                PA.Metrics.calc_capacity_additions,
                "capacity_additions",
            ),
            (
                plot_installed_capacity_fn,
                PA.Metrics.calc_installed_capacity,
                "installed_capacity",
            ),
        )
            expected = select(metric(selector, investment), "NG-CT", "Storage")
            colors = PG.match_fuel_colors(expected, backend)
            plot = plot_fn(
                investment;
                set_display = set_display,
                title = title,
                save = out_path,
            )
            if backend_pkg == "cairomakie"
                bars = only(plot.axis.scene.plots)
                @test getindex.(bars[1][], 2) ≈ vec(Matrix(expected))
                @test bars.color[] == repeat(colors; inner = 2)
                @test plot.axis.xticks[] == ([1, 2], ["2030", "2035"])
                @test plot.axis.ylabel[] == "MW"
            else
                @test [trace.name for trace in plot.data] == ["NG-CT", "Storage"]
                @test hcat([trace.y for trace in plot.data]...) ≈ Matrix(expected)
                @test [trace.marker.color for trace in plot.data] == colors
                @test all(trace.x == ["2030", "2035"] for trace in plot.data)
                @test plot.layout.yaxis.title.text == "MW"
            end
        end
        filtered = plot_capacity_additions_fn(
            investment;
            filter_func = technology -> PSIP.get_name(technology) == "battery",
            set_display = false,
        )
        expected_storage = PA.Metrics.calc_capacity_additions(selector, investment).Storage
        if backend_pkg == "cairomakie"
            @test getindex.(only(filtered.axis.scene.plots)[1][], 2) ≈ expected_storage
        else
            @test only(filtered.data).name == "Storage"
            @test only(filtered.data).y ≈ expected_storage
        end

        list = readdir(out_path)
        file_ext = backend_pkg == "plotlylight" ? ".html" : ".png"
        expected_files = ["capacity_additions$file_ext", "installed_capacity$file_ext"]
        @test isempty(setdiff(expected_files, list))
        @test isempty(setdiff(list, expected_files))

        @info("removing test files")
        cleanup && rm(out_path; recursive = true)
    end

    @testset "test $backend_pkg capacity plot colors" begin
        mapping = PA.get_generator_mapping()
        selector = PA.make_selector(
            PSIP.ResourceTechnology;
            groupby = technology -> PA.get_generator_category(technology, mapping),
        )
        expected = Matrix(
            select(
                PA.Metrics.calc_capacity_additions(selector, investment),
                "Storage",
                "NG-CT",
            ),
        )
        palette = [
            PG.PaletteColor("Other", "rgba(0, 0, 255, 1)", 2),
            PG.PaletteColor("Storage", "rgba(255, 0, 0, 1)", 3),
        ]
        colors = if backend_pkg == "cairomakie"
            getfield.(palette, :color)
        else
            getfield.(palette, :RGB)
        end
        for (options, expected_colors) in (
            ((;), colors[[2, 1]]),
            ((; seriescolor = colors), colors),
        )
            plot = plot_capacity_additions_fn(
                investment;
                palette = palette,
                set_display = false,
                options...,
            )
            if backend_pkg == "cairomakie"
                bars = only(plot.axis.scene.plots)
                @test getindex.(bars[1][], 2) ≈ vec(expected)
                @test bars.color[] == repeat(expected_colors; inner = 2)
            else
                @test [trace.name for trace in plot.data] == ["Storage", "NG-CT"]
                @test hcat([trace.y for trace in plot.data]...) ≈ expected
                @test [trace.marker.color for trace in plot.data] == expected_colors
            end
        end
    end

    @testset "test alternate mapping yamls" begin
        # Alternate color palette makes curtailment hot pink
        out_path = joinpath(file_path, backend_pkg * "_alternate_palette")
        !isdir(out_path) && mkdir(out_path)

        palette = PG.load_palette(joinpath(TEST_DIR, "test_yamls/color-palette.yaml"))

        plot_fuel_fn(
            results_uc;
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
                results_ed;
                set_display = false,
                save = TEST_RESULT_DIR,
                title = "fuel_html_output",
                format = "html",
            )
            @test isfile(joinpath(TEST_RESULT_DIR, "fuel_html_output.html"))
        end
    end
end
let investment = PA.investment_results(run_test_investment_prob().results)
    try
        test_plots(file_path, investment; backend_pkg = "cairomakie")
        @info("done with CairoMakie, starting plotlylight")
        test_plots(file_path, investment; backend_pkg = "plotlylight")
    finally
        nothing
    end
end
