# Reserve-provision stacks by fuel (`plot_fuel(...; service = ...)`) on both
# backends, checked against the raw `ActivePowerReserveVariable` results.

(service_results_uc, service_results_ed) = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)
service_sys = PSI.get_system(service_results_uc)
reg1 = get_component(VariableReserve{ReserveUp}, service_sys, "REG1")

# One column per contributing device.
reg1_raw = only(
    values(
        PSI.read_results_with_keys(
            service_results_uc,
            [
                PSI.VariableKey(
                    ActivePowerReserveVariable,
                    VariableReserve{ReserveUp},
                    "REG1",
                ),
            ];
            table_format = IS.TableFormat.WIDE,
        ),
    ),
)

service_plot(backend; kwargs...) = plot_fuel(
    service_results_uc;
    backend = backend,
    set_display = false,
    stack = true,
    auto_units = false,
    kwargs...,
)

@testset "$backend_pkg service stack matches the reserve results" for (
    backend_pkg,
    backend,
) in TEST_BACKENDS
    p = service_plot(backend; service = "REG1")
    @test get_plot_title(p) == "REG1"
    @test !("Load" in series_labels(p))
    # The service object and its name select the same stack, including a
    # service taken from another copy of the system.
    @test series_map(service_plot(backend; service = reg1)) == series_map(p)
    reg1_copy = get_component(VariableReserve{ReserveUp}, deepcopy(service_sys), "REG1")
    @test series_map(service_plot(backend; service = reg1_copy)) == series_map(p)

    # Categories partition the product's total provision.
    total = vec(sum(Matrix(PA.no_datetime(reg1_raw)); dims = 2))
    @test sum(series_ydata(p)) ≈ total

    # Each category holds the devices the energy stack puts in it, in its color.
    p_energy = plot_fuel(
        service_results_uc;
        backend = backend,
        set_display = false,
        stack = true,
        auto_units = false,
    )
    energy_colors = Dict(zip(series_labels(p_energy), series_colors(p_energy)))
    contributing = Set(get_contributing_devices(service_sys, reg1))
    categories = PA.Selectors.injector_categories
    for (label, values) in series_map(p)
        @test haskey(energy_colors, label)
        members =
            get_name.(
                filter(
                    in(contributing),
                    collect(get_components(categories[label], service_sys)),
                ),
            )
        @test !isempty(members)
        @test values ≈ vec(sum(Matrix(reg1_raw[!, members]); dims = 2))
    end
    @test Dict(zip(series_labels(p), series_colors(p))) ==
          Dict(label => energy_colors[label] for label in series_labels(p))

    # A window starting at the first step of the second simulation run.
    steps_per_run = nrow(reg1_raw) ÷ length(PSI.get_timestamps(service_results_uc))
    window = (steps_per_run + 1):(steps_per_run + 4)
    p_win = service_plot(
        backend;
        service = "REG1",
        initial_time = reg1_raw[first(window), "DateTime"],
        horizon = length(window),
    )
    @test sort(series_labels(p_win)) == sort(series_labels(p))
    for (label, values) in series_map(p_win)
        @test values ≈ series_values(p, label)[window]
    end

    @test_throws "No reserve results for service \"REG2\"; reserve products in the results: REG1" service_plot(
        backend;
        service = "REG2",
    )
    @test_throws "reserve products in the results: none" plot_fuel(
        service_results_ed;
        backend = backend,
        set_display = false,
        service = reg1,
    )
end

@testset "service lookup matches by type and name" begin
    up = VariableReserve{ReserveUp}(nothing)
    down = VariableReserve{ReserveDown}(nothing)
    same_name = [up, down]
    @test PG._select_service(same_name, down) === down
    @test_throws "Several reserve products are named \"init\"" PG._select_service(
        same_name,
        "init",
    )
end

@testset "service stack is identical across backends" begin
    plots = Dict(
        pkg => service_plot(backend; service = reg1) for (pkg, backend) in TEST_BACKENDS
    )
    cm = plots["cairomakie"]
    pl = plots["plotlylight"]

    @test series_labels(cm) == series_labels(pl)
    @test series_colors(cm) == series_colors(pl)
    for (a, b) in zip(series_ydata(cm), series_ydata(pl))
        @test a ≈ b
    end
end
