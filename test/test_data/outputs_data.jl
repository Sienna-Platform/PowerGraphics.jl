# psy6-native outputs fixture for the plot tests. Replaces the parked PowerAnalytics
# `test/test_data/results_data.jl`, which built a multi-stage PSI `Simulation` --
# psy6 has no `Simulation` type, so there is no equivalent to port. This builds and
# solves a single `DecisionModel` through PowerOperationsModels instead and hands the
# tests its `IOM.OptimizationProblemOutputs`.

# c_sys5_uc_re: thermal (Coal, unit commitment) + RenewableDispatch (Wind) + PowerLoad
# + InterruptiblePowerLoad across 3 load buses. Chosen over plain `c_sys5_uc` (all-Coal,
# a single fuel category) because `plot_fuel` needs generators spanning more than one
# fuel category and `plot_demand` needs load to aggregate by bus; still small enough to
# solve well under a second.
function _build_test_outputs()
    sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_uc_re")

    template = POM.PowerOperationsProblemTemplate(POM.CopperPlateNetworkModel)
    POM.set_device_model!(template, PSY.ThermalStandard, POM.ThermalStandardUnitCommitment)
    POM.set_device_model!(template, PSY.RenewableDispatch, POM.RenewableFullDispatch)
    POM.set_device_model!(template, PSY.PowerLoad, POM.StaticPowerLoad)
    POM.set_device_model!(template, PSY.InterruptiblePowerLoad, POM.StaticPowerLoad)

    model = POM.DecisionModel(template, sys; optimizer = HiGHS.Optimizer)
    build_status = build!(model; output_dir = mktempdir(; cleanup = true))
    build_status == IOM.ModelBuildStatus.BUILT ||
        error("Test fixture failed to build: $build_status")

    run_status = solve!(model)
    run_status == IOM.RunStatus.SUCCESSFULLY_FINALIZED ||
        error("Test fixture failed to solve: $run_status")

    return IOM.OptimizationProblemOutputs(model)
end

# Solved once per suite run; every plot test (both backends) reuses this.
const TEST_OUTPUTS_DATA = _build_test_outputs()
