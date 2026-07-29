# Regression tests for how `plot_fuel` recovers a generator-mapping rule's
# specificity and uses it to put each component in exactly one fuel category.
#
# The thing under test is fragile by nature: PowerAnalytics hands back one
# `ComponentSelector` per category, and PowerGraphics has to know which YAML rule
# produced each of its sub-selectors in order to replay the old first-match-wins
# ladder. Getting that wrong does not throw -- it silently files components under
# the wrong fuel. So the assertions below are written to fail if the ranking
# degrades, not merely if it errors.

const SPECIFICITY_MAPPING =
    joinpath(TEST_DIR, "test_yamls", "generator_mapping_specificity.yaml")

# Reuses the serialized store written by the other fuel tests.
(fuelcat_results_uc, _) = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)
const FUELCAT_SYS = PSI.get_system(fuelcat_results_uc)

@testset "rule specificity is recovered from the mapping, not from selector names" begin
    categories = PA.parse_injector_categories(SPECIFICITY_MAPPING)

    # Order the categories with the broad rule FIRST and hand that order to
    # `_assign_fuel_categories` directly. Ranking is strict (`rank < best_rank`),
    # so if specificity ever collapses -- every rule looking equally broad -- the
    # first-seen category wins and these assertions fail deterministically rather
    # than depending on `Dict` iteration order.
    ordered = [
        name => categories[name] for
        name in
        ["BroadThermal", "NGCombustionTurbine", "CoalOnly", "Hydropower", "PV", "Wind"]
    ]
    thermal = collect(get_components(ThermalStandard, FUELCAT_SYS))
    @test !isempty(thermal)

    assignments, unmatched = PG._assign_fuel_categories(
        fuelcat_results_uc,
        ordered,
        SPECIFICITY_MAPPING,
        thermal,
        nothing,
    )
    @test isempty(unmatched)
    assigned = Dict(
        get_name(c) => category for (category, comps) in assignments for c in comps
    )

    # Prime-mover + fuel specific beats the type-only rule over the same gentype.
    @test assigned["Solitude"] == "NGCombustionTurbine"
    @test assigned["Alta"] == "NGCombustionTurbine"
    # Fuel specificity ALONE beats the type-only rule: both rules are prime-mover
    # wildcards, so this fails the moment the fuel axis stops being recovered.
    @test assigned["Brighton"] == "CoalOnly"
    # Nothing narrower matches these, so the broad rule is genuinely correct.
    @test assigned["Park City"] == "BroadThermal"
    @test assigned["Sundance"] == "BroadThermal"

    # Every component ends up in exactly one category -- the whole point of the
    # ladder, since overlapping rules would otherwise double-count energy.
    @test sum(length, values(assignments)) == length(thermal)
end

@testset "mapping rules dropped by PowerAnalytics are dropped at the same position" begin
    # "Hydropower" lists three rules, the first of which (`gentype: ACBus`)
    # cannot intersect the `StaticInjection` root type and is discarded by
    # `make_fuel_component_selector`. If PowerGraphics did not replay that drop,
    # its rules would be paired with the wrong sub-selectors and the
    # correspondence check would throw.
    categories = PA.parse_injector_categories(SPECIFICITY_MAPPING)
    groups = collect(PSY.get_groups(categories["Hydropower"], fuelcat_results_uc))
    specs = PG._mapping_rule_specs(PG.YAML.load_file(SPECIFICITY_MAPPING), "Hydropower")
    @test length(specs) == length(groups) == 2
    @test first.(specs) == [PSY.HydroGen, PSY.StaticInjection]

    # And the hydro components really do land in "Hydropower" end to end.
    hydro = collect(get_components(HydroGen, FUELCAT_SYS))
    @test !isempty(hydro)
    assignments, unmatched = PG._assign_fuel_categories(
        fuelcat_results_uc,
        categories,
        SPECIFICITY_MAPPING,
        hydro,
        nothing,
    )
    @test isempty(unmatched)
    @test sort(get_name.(assignments["Hydropower"])) == sort(get_name.(hydro))
end

@testset "broken group/rule correspondence fails loudly" begin
    # A silently wrong fuel plot is the failure mode this check exists to
    # prevent, so a mismatch must throw and must name the category and file.
    err = try
        PG._validate_rule_correspondence(
            "MyCategory",
            SPECIFICITY_MAPPING,
            (),
            Tuple{Type, Bool, Bool}[(ThermalStandard, true, true)],
        )
        nothing
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("MyCategory", err.msg)
    @test occursin(SPECIFICITY_MAPPING, err.msg)

    # A sub-selector that is not the `FilterComponentSelector` PowerAnalytics
    # builds carries no rule type, so it can never be matched to a rule.
    @test PG._selector_component_type(make_selector(ThermalStandard)) === Union{}
    @test_throws ErrorException PG._validate_rule_correspondence(
        "MyCategory",
        SPECIFICITY_MAPPING,
        [make_selector(ThermalStandard)],
        Tuple{Type, Bool, Bool}[(ThermalStandard, true, true)],
    )
end

module FuelCatModA
abstract type Thermal end
struct Gen <: Thermal end
end

module FuelCatModB
abstract type Thermal end
end

@testset "type distance separates same-named types in different modules" begin
    # PowerAnalytics' `lookup_gentype` accepts `Module.TypeName`, so two rules
    # can legitimately name different types that share a `nameof`. Matching on
    # the name alone ranked them identically.
    @test PG._type_distance(FuelCatModA.Gen, FuelCatModA.Thermal) == 1
    @test PG._type_distance(FuelCatModA.Gen, FuelCatModB.Thermal) == typemax(Int)

    # Bare `gentype` names still work, because PowerAnalytics resolves them
    # against PowerSystems before PowerGraphics ever sees a type.
    @test PG._type_distance(ThermalStandard, ThermalStandard) == 0
    @test PG._type_distance(ThermalStandard, StaticInjection) <
          PG._type_distance(ThermalStandard, Any)
    @test PG._type_distance(ThermalStandard, HydroGen) == typemax(Int)

    # More specific rule types must outrank less specific ones for the ladder in
    # `_rule_rank` to mean anything.
    @test PG._type_distance(ThermalStandard, ThermalGen) <
          PG._type_distance(ThermalStandard, StaticInjection)
end

@testset "specificity mapping drives plot_fuel end to end" begin
    for (backend_pkg, backend) in
        (("cairomakie", CairoMakieBackend()), ("plotlylight", PlotlyLightBackend()))
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
        # No component may be filed under "Other": the mapping covers the whole
        # generator pool, so anything landing there means a rule stopped matching.
        @test !("Other" in labels)

        # The narrow categories must carry real energy -- an empty category would
        # be dropped as an all-zero column, so its mere presence is already a
        # signal, but pin the sign too.
        @test sum(series_values(p, "NGCombustionTurbine")) > 0
        @test sum(series_values(p, "CoalOnly")) > 0
    end
end
