# psy6 migration: PowerAnalytics.jl → PowerGraphics.jl

PowerGraphics is downstream of PowerAnalytics, which is still PSI-based. PA moves first.

Both repos are on branch `psy6`, currently identical to `main`.

> **Status: partially superseded — brainstorming in progress, not yet a final plan.**
> The verified symbol map below still holds. Phases 1–3 do **not**: PowerAnalytics is owned by a
> separate agent, and this repo no longer plans to touch it. The target agreed since writing this
> is that **PG and PA depend on IS only — no IOM, no POM**. For PG that is reachable now:
> its runtime surface is PSY + IS + PA, so POM/IOM appear only in `test/Project.toml`.
> Superseding design decisions are recorded under "Agreed since" below.

## Decisions taken

- Simulation-results support is **kept, stubbed** — not deleted. psy6 has no orchestration layer.
- No version bumps, no compat bumps (psy6 policy holds until release).
- No shims elsewhere: PSI symbols are repointed at their real IOM/POM homes, not aliased.

## Agreed since (supersedes Phases 1–4 where they conflict)

- **PG stays out of `../PowerAnalytics.jl`** — a separate agent owns that migration and is
  commenting out the Simulation tests to focus on the DecisionModel path.
- **Target: PG and PA depend on IS only.** PG reaches this in the current work; PA needs an
  upstream restructure (push the domain-neutral key machinery and `OptimizationProblemOutputs`
  from IOM down into `IS.Optimization`, then name power-specific entry types through a POM
  package extension). That restructure is a separate design, not this plan.
- **System accessor:** `IOM.get_system` takes a *model*, not outputs. Use `IS.get_source_data`.
  IOM imports that generic from IS (`InfrastructureOptimizationModels.jl:72`), so IOM's
  `OptimizationProblemOutputs` method dispatches with **zero new deps on PG**. Note it returns
  `nothing` when no system is attached — PG must error with context, not propagate the sentinel.
- **Test fixture:** keep including PA's `test/test_data/results_data.jl` for helpers, but define
  PG's own results builder locally. One `DecisionModel` result used everywhere; the
  `results_uc`/`results_ed` split collapses to a single object.
- **Test deps collapse:** `PowerSimulations` + `StorageSystemsSimulations` +
  `HydroPowerSimulations` → POM + IOM. Hydro and storage formulations
  (`HydroTurbine`, `HydroReservoir`, `HydroTurbineEnergyDispatch`, `HydroEnergyModelReservoir`,
  `FixedOutput`, `StorageDispatchWithReserves`) are all in POM. There is **no**
  `template_unit_commitment` in POM — templates are built explicitly.
- **Acceptance gate:** migration complete and `using PowerGraphics` loads clean. Test failures
  traceable to PA are documented, not fixed.

## Verified symbol map

`PSI.x` → psy6 home. Checked against the psy6 checkouts, not from memory.

| PSI symbol | psy6 home | Note |
|---|---|---|
| `OptimizationContainerKey`, `VariableKey`, `ParameterKey`, `ExpressionKey`, `AuxVarKey` | IOM | `src/core/optimization_container_keys.jl` |
| `VariableType`, `ParameterType`, `ExpressionType`, `AuxVariableType`, `ConstraintType`, `InitialConditionType` | IOM | re-exported from `IS.Optimization` |
| `ActivePowerVariable`, `ActivePowerInVariable`, `ActivePowerOutVariable`, `StartVariable`, `StopVariable` | IOM | `core/standard_variables_expressions.jl` |
| `ActivePowerTimeSeriesParameter`, `ActivePowerInTimeSeriesParameter`, `ActivePowerOutTimeSeriesParameter`, `RequirementTimeSeriesParameter` | IOM | `core/time_series_parameter_types.jl` |
| `ProductionCostExpression` | IOM | |
| `get_component_type`, `get_entry_type`, `encode_key_as_string`, `encode_keys_as_strings` | IOM | |
| `list_variable_keys`, `list_parameter_keys`, `list_aux_variable_keys` | IOM | on `OptimizationProblemOutputs` |
| `get_timestamps`, `get_realized_timestamps`, `read_optimizer_stats`, `get_system` | IOM | |
| **`read_results_with_keys`** | IOM **`read_outputs_with_keys`** | renamed |
| **`ICKey`** | IOM **`InitialConditionKey`** | renamed |
| `FlowActivePowerVariable`, `FlowActivePowerToFromVariable`, `FlowActivePowerFromToVariable` | POM | |
| `PowerFlowBranchActivePowerToFrom`, `PowerFlowBranchActivePowerFromTo` | POM | |
| `SystemBalanceSlackUp`, `SystemBalanceSlackDown`, `EnergyVariable`, `PowerOutput`, `ActivePowerReserveVariable` | POM | |
| `SimulationResults`, `SimulationProblemResults`, `DecisionModelSimulationResults`, `get_decision_problem_results`, `load_results!` | **absent** | stub — orchestration not ported |

Also stack-wide: `IS.Results` → `IS.Outputs` (`InfrastructureSystems/src/outputs.jl`);
`IOM.OptimizationProblemOutputs <: IS.Outputs`.

## Steps

### Phase 1 — PowerAnalytics wiring

1. `Project.toml`: drop `PowerSimulations`; add `InfrastructureOptimizationModels`
   (`bed98974-b02a-5e2f-9ee0-a103f5c45069`) and `PowerOperationsModels`
   (`bed98974-b02a-5e2f-9ee0-a103f5c450dd`). Add `[sources]` pins matching POM's:
   IS `IS4`, PSY `psy6`, IOM `jd/network-sources`, PNM `psy6`. No version/compat bump.
2. `src/PowerAnalytics.jl`: replace the `PowerSimulations` import block; `const IOM`, `const POM`;
   remove `const PSI`. Keep `get_system` imported (now from IOM).

### Phase 2 — PowerAnalytics source (173 `PSI.` refs across 4 files)

3. `src/definitions.jl` (14) — key-type constants, per map.
4. `src/get_data.jl` (114) — largest. `read_results_with_keys` → `read_outputs_with_keys`,
   `IS.Results` → `IS.Outputs`, variable/parameter types split IOM vs POM.
5. `src/input_utils.jl` (34) — results-dict layer. Move the `SimulationProblemResults` methods
   into `src/simulation_outputs_stub.jl`, **not** included from the module, with a header naming
   the missing upstream API. No placeholder types — keeping the code without faking the API.
6. `src/builtin_metrics.jl` (11).
7. Compile gate after each file: `julia --project=test -e 'using PowerAnalytics'`.

### Phase 3 — PowerAnalytics tests

8. `test/Project.toml`: PSI → IOM/POM.
9. `test/test_data/results_data.jl`: the multi-stage `Simulation`/`SimulationSequence` fixture has
   no psy6 equivalent. Rebuild the fixture on a single `DecisionModel` +
   `OptimizationProblemOutputs`; park the simulation builder alongside the stub.
10. `test/setuptests.jl`, `test_input.jl`, `test_metrics.jl`, `test_builtin_metrics.jl`,
    `test_result_sorting.jl` (31 refs total).

### Phase 4 — PowerGraphics

11. `Project.toml`: `[sources]` pins for PSY/IS/PA. PSY compat stays `^5.10` (no bumps).
12. `src/call_plots.jl:709`: `PA.PSI.get_system` → `PA.IOM.get_system`.
13. `test/Project.toml`: drop `PowerSimulations`, `StorageSystemsSimulations`,
    `HydroPowerSimulations`; add IOM/POM.
14. `test/runtests.jl`: import block and `const PSI`.
15. `test/test_plot_creation.jl:249` uses `PSB.build_system(PSB.PSISystems, "5_bus_hydro_uc_sys")` —
    verify that descriptor still builds under psy6 PSB.

**Already done** (PA-independent, in the working tree):
`IS.Results` → `IS.Outputs` (18 sites, `src/call_plots.jl` + `ext/WeaveExt.jl`);
`PSY.Bus` → `PSY.ACBus` in the `plot_demand` docstring.

### Phase 5 — verify

16. `julia --project=test test/runtests.jl` in PA, then in PG.
17. Formatter in both: `julia --project=scripts/formatter -e 'include("scripts/formatter/formatter_code.jl")'`.
18. Docs build in both. Note `IS.Outputs` is **not exported** by IS — the `@extref`
    `InfrastructureSystems.Results` links in `call_plots.jl` need retargeting or Documenter fails.

## Open risks

- **Phase 3 step 9 is the deep one.** PG's tests include PA's fixture file directly, so a
  DecisionModel-based fixture changes what both suites can assert. Fuel/generation plots that
  depend on multi-stage realized timestamps may lose coverage.
- IOM is on `jd/network-sources` and POM on `jd/network_matrix_consolidation` — neither is a
  stable branch. Their APIs can move under us mid-migration.
- PSB is on `jd/remove_pscb_code`; the `PSISystems` fixtures PG's tests need may have shifted.
