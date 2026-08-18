# PowerGraphics.jl Examples

Build and solve a `DecisionModel` with PowerOperationsModels, wrap its outputs, and plot:

```julia
using PowerSystems
using PowerSystemCaseBuilder
using PowerOperationsModels
using InfrastructureOptimizationModels
using CairoMakie
using PowerGraphics
using HiGHS

sys = build_system(PSITestSystems, "c_sys5_uc_re")

template = PowerOperationsProblemTemplate(CopperPlateNetworkModel)
set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template, PowerLoad, StaticPowerLoad)
set_device_model!(template, InterruptiblePowerLoad, StaticPowerLoad)

model = DecisionModel(template, sys; optimizer = HiGHS.Optimizer)
build!(model; output_dir = mktempdir())
solve!(model)

res = OptimizationProblemOutputs(model)
plot_fuel(res)
plot_demand(res)
```
