file_path = TEST_OUTPUTS

function test_reports(file_path::String; backend_pkg::String = "cairomakie")
    # Select backend based on backend_pkg
    if backend_pkg == "cairomakie"
        backend = PG.CairoMakieBackend()
    elseif backend_pkg == "plotlylight"
        backend = PG.PlotlyLightBackend()
    else
        throw(error("$backend_pkg backend_pkg not supported"))
    end
    cleanup = true

    @testset "testing $backend_pkg report production" begin
        out_path = joinpath(file_path, backend_pkg * "_reports")
        !isdir(out_path) && mkpath(out_path)
        report_out_path = joinpath(out_path, "test_report.html")
        (results_uc, results_ed) = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)

        PG.report(
            results_uc,
            report_out_path,
            generic_template;
            doctype = "md2html",
            backend = backend,
        )
        @test isfile(report_out_path)

        @info("removing test files")
        cleanup && rm(out_path; recursive = true)
    end
end

try
    test_reports(file_path; backend_pkg = "cairomakie")
    test_reports(file_path; backend_pkg = "plotlylight")
finally
    nothing
end
