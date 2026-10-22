# Single-category assignment of components in `plot_fuel`.

const SPECIFICITY_MAPPING =
    joinpath(TEST_DIR, "test_yamls", "generator_mapping_specificity.yaml")

# Reuses the serialized store written by the other fuel tests.
(fuelcat_results_uc, _) = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)
const FUELCAT_SYS = PSI.get_system(fuelcat_results_uc)

@testset "the most specific mapping rule decides the fuel category" begin
    categories = PA.parse_injector_categories(SPECIFICITY_MAPPING)
    thermal = collect(get_components(ThermalStandard, FUELCAT_SYS))
    @test !isempty(thermal)

    # "BroadThermal" sorts first, so it would win if the narrower rules stopped
    # excluding a component.
    @test first(sort!(collect(keys(categories)))) == "BroadThermal"
    assignments, unmatched = PG._assign_fuel_categories(
        fuelcat_results_uc,
        categories,
        Vector{StaticInjection}(thermal),
    )
    @test isempty(unmatched)
    assigned =
        Dict(get_name(c) => category for (category, comps) in assignments for c in comps)

    # Prime-mover + fuel specific beats the type-only rule over the same gentype.
    @test assigned["Solitude"] == "NGCombustionTurbine"
    @test assigned["Alta"] == "NGCombustionTurbine"
    # Fuel specificity alone beats the type-only rule.
    @test assigned["Brighton"] == "CoalOnly"
    # Nothing narrower matches these, so the broad rule is genuinely correct.
    @test assigned["Park City"] == "BroadThermal"
    @test assigned["Sundance"] == "BroadThermal"

    # Every component lands in exactly one category.
    @test sum(length, values(assignments)) == length(thermal)
    for (category, selector) in categories, comp in thermal
        selected = comp in collect(get_components(selector, fuelcat_results_uc))
        @test selected == (assigned[get_name(comp)] == category)
    end
end

@testset "mapping rules outside the root type are dropped" begin
    # The `ACBus` rule under "Hydropower" selects nothing.
    categories = PA.parse_injector_categories(SPECIFICITY_MAPPING)
    hydro = collect(get_components(HydroGen, FUELCAT_SYS))
    @test !isempty(hydro)
    assignments, unmatched = PG._assign_fuel_categories(
        fuelcat_results_uc,
        categories,
        Vector{StaticInjection}(hydro),
    )
    @test isempty(unmatched)
    @test sort(get_name.(assignments["Hydropower"])) == sort(get_name.(hydro))
end

@testset "specificity mapping drives plot_fuel end to end" begin
    for (backend_pkg, backend) in TEST_BACKENDS
        p = plot_fuel(
            fuelcat_results_uc;
            backend = backend,
            set_display = false,
            stack = true,
            auto_units = false,
            storage = false,
            sources = false,
            slacks = false,
            generator_mapping_file = SPECIFICITY_MAPPING,
        )
        labels = series_labels(p)
        @test "NGCombustionTurbine" in labels
        @test "CoalOnly" in labels
        # The mapping covers the whole pool, so nothing lands in "Other".
        @test !("Other" in labels)

        # Each narrow category equals the sum of its (hardcoded) members'
        # generation. Most of these units are uncommitted, so no sign check.
        for (category, members) in
            (("NGCombustionTurbine", ["Alta", "Solitude"]), ("CoalOnly", ["Brighton"]))
            expected = sum(
                PA.get_data_vec(
                    PA.compute(
                        PA.Metrics.calc_active_power,
                        fuelcat_results_uc,
                        get_component(ThermalStandard, FUELCAT_SYS, name),
                    ),
                ) for name in members
            )
            # Absolute MW tolerance: CairoMakie band values carry stack-wide rounding.
            @test isapprox(series_values(p, category), expected; atol = 1e-8)
        end
    end
end

@testset "mapping files with `ext_category` keys warn" begin
    mapping = joinpath(mktempdir(), "ext_category_mapping.yaml")
    write(
        mapping,
        "Thermal:\n  - {gentype: ThermalStandard, primemover: null, fuel: null, ext_category: CHP}\n",
    )
    categories = @test_logs (:warn, r"ext_category") PG._fuel_categories(mapping)
    @test haskey(categories, "Thermal")
end
