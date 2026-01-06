file_path = TEST_OUTPUTS

function test_plots(file_path::String; backend_pkg::String = "cairomakie")
    # Select plot functions based on backend
    if backend_pkg == "cairomakie"
        plot_dataframe_fn = plot_dataframe
        plot_dataframe_fn! = plot_dataframe!
        plot_demand_fn = plot_demand
        plot_powerdata_fn = PG.plot_powerdata
        plot_fuel_fn = plot_fuel
    elseif backend_pkg == "plotlyjs"
        plot_dataframe_fn = plot_dataframe_plotly
        plot_dataframe_fn! = plot_dataframe_plotly!
        plot_demand_fn = plot_demand_plotly
        plot_powerdata_fn = PG.plot_powerdata_plotly
        plot_fuel_fn = plot_fuel_plotly
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
        expected_files = [
            "df_line.png",
            "df_stack.png",
            "df_stair.png",
            "df_bar.png",
            "df_bar_stack.png",
            "df_gen_load.png",
        ]
        # expected results not created
        @test isempty(setdiff(expected_files, list))
        # extra results created
        @test isempty(setdiff(list, expected_files))

        @info("removing test files")
        cleanup && rm(out_path; recursive = true)
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
        expected_files =
            ["pg_data.png", "pg_data_stack.png", "pg_data_bar.png", "pg_data_bar_stack.png"]
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

        p = plot_demand_fn(
            results_uc.system;
            set_display = set_display,
            title = "sysdemand",
            save = out_path,
            aggregation = System,
        )
        plot_length = backend_pkg == "cairomakie" ? p.series_count : length(p.data)
        @test plot_length == 1

        p = plot_demand_fn(
            results_uc.system;
            set_display = set_display,
            title = "sysdemand_bus",
            save = out_path,
            aggregation = ACBus,
        )
        plot_length = backend_pkg == "cairomakie" ? p.series_count : length(p.data)
        @test plot_length == 3

        list = readdir(out_path)
        expected_files = [
            "demand.png",
            "demand_stack.png",
            "demand_bar.png",
            "demand_bar_stack.png",
            "demand_nofill.png",
            "demand_nofill_stack.png",
            "demand_nofill_bar.png",
            "demand_nofill_bar_stack.png",
            "sysdemand.png",
            "sysdemand_bus.png",
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
        expected_files =
            ["fuel.png", "fuel_stack.png", "fuel_bar.png", "fuel_bar_stack.png"]
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
        expected_files = ["fuel.png"]
        @test isempty(setdiff(expected_files, list))
        @test isempty(setdiff(list, expected_files))

        @info "removing alternate test fuel outputs"
        cleanup && rm(out_path; recursive = true)
    end

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
try
    test_plots(file_path; backend_pkg = "cairomakie")
    @info("done with CairoMakie, starting plotlyjs")
    test_plots(file_path; backend_pkg = "plotlyjs")
finally
    nothing
end
