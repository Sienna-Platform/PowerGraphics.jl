# PowerGraphics: refactor onto PowerAnalytics' metrics API

Written 2026-08-17. Replaces `psy6-migration.md`, whose Phases 1–3 (PowerAnalytics wiring) are
done upstream and whose Phase 4 (PowerGraphics) no longer describes the work.

## 0. Why the old plan is void

The old plan's Phase 4 was three lines of PG work: fix `PA.PSI.get_system`, swap test deps,
check a PSB descriptor. That was written when PowerAnalytics still had its legacy data layer.

PowerAnalytics commit `1870a0c` **deleted that layer entirely** — `src/get_data.jl`,
`src/fuel_results.jl`, `src/definitions.jl`. Verified against PA's current `src/`: every symbol
PG's plotting code calls is gone, zero hits each.

| PG call site | PA symbol | In PA `src/` today |
|---|---|---|
| `call_plots.jl:487,492,498,553,559,591,598,628,636` | `PA.PowerData` | **gone** |
| `call_plots.jl:708` | `PA.get_generation_data` | **gone** |
| `call_plots.jl:199` | `PA.get_load_data` | **gone** |
| `call_plots.jl:716` | `PA.categorize_data` | **gone** |
| `call_plots.jl:715` | `PA.make_fuel_dictionary` | **gone** |
| `call_plots.jl:213,506,725` | `PA.combine_categories` | **gone** |
| `call_plots.jl:80,344,360,420,443,764` + both `ext/` recipes | `PA.no_datetime` | **gone** |
| `call_plots.jl:709` | `PA.PSI.get_system` | **gone** (PA has no `PSI` alias) |

PG does not currently load against psy6 PA. This is a refactor of PG's data layer onto PA's
metrics framework, not a symbol repoint.

## 1. Decision

**PG refactors onto PA's new API.** PA stays lean — the legacy layer is not resurrected in
either package. PG owns a thin adapter that turns an outputs container into the plot-ready
frames its backends already consume.

Consequences accepted:

- `PA.PowerData` does not come back. PG's `plot_powerdata` family takes a `DataFrame` +
  time vector, which is what `_plot_dataframe!` has always actually needed.
- PG's public plot signatures change. Breaking, which is fine under psy6's no-shims rule.
- The fuel-category *policy* (which prime mover and fuel map to which category) stays in PA's
  `deps/generator_mapping.yaml`, where it already lives. PG keeps only the *presentation*
  policy: palette ordering and color matching.

## 2. The replacement API — verified

PA's metrics framework already covers everything the legacy pipeline did. Verified by loading
psy6 PA: `Selectors.categorized_generators` resolves, and `Selectors.generator_categories`
carries exactly the 13 categories the deleted `make_fuel_dictionary` produced:

```
Biopower  CSP  Coal  Geothermal  Hydropower  NG-CC  NG-CT  NG-Steam
Nuclear   Other  Petroleum  PV  Wind
```

### 2.1 Mapping

| Legacy call | Replacement |
|---|---|
| `PA.get_generation_data(result)` → `PowerData` | `PA.compute(PA.Metrics.calc_active_power, outputs, PA.Selectors.categorized_generators)` |
| `PA.make_fuel_dictionary(sys)` + `PA.categorize_data(gen.data, cat)` | folded into the selector above — categorization is the selector's grouping |
| `PA.combine_categories(fuel; names, aggregate)` | the selector's `component_agg_fn` (default `sum`) already collapses within a group; column *order* is PG's job (§3.2) |
| `combine_categories = false` (per-component columns) | pass an ungrouped selector, e.g. `make_selector(PSY.Generator)` |
| `PA.get_load_data(result)` | `PA.compute(PA.Metrics.calc_load_forecast, outputs, PA.Selectors.all_loads)` |
| `PA.no_datetime(df)` | **`PA.get_data_df(df)`** — already exported; strictly better, it also excludes metadata columns |
| `powerdata.time` / `df.DateTime` | `PA.get_time_vec(df)` |
| `PA.PSI.get_system(result)` | `IS.get_source_data(outputs)` — IOM imports the generic from IS, so **no new PG dependency**. Returns `nothing` when unattached; PG must error with context, not propagate the sentinel |
| storage-charging columns (`endswith(k, " In")`) | `PA.Selectors.all_storage` with `calc_active_power_in`, or the `" In"` column names the injector selector still produces |

`compute` returns one wide `DataFrame` — `DateTime` plus one column per selector group — which
is the shape `_plot_dataframe!` wants. The old `Dict{String, DataFrame}` intermediate
disappears; `keys(fuel)` becomes `PA.get_data_cols(df)`.

### 2.2 What PG must keep owning

- **Palette ordering.** `call_plots.jl:722-725` orders categories by
  `get_palette_category(palette)`, appending unmatched ones sorted. That is presentation, not
  analysis — it stays in PG, now operating on `get_data_cols(df)` instead of `keys(fuel)`.
- **`match_fuel_colors`** and the whole `definitions.jl` palette layer. Unchanged.
- **Sign conventions and the net-load line.** `_plot_fuel!`'s net-load computation
  (`call_plots.jl:755-770`) — demand + storage charging + source input — is PG logic.

## 3. Steps

Every phase ends with the formatter
(`julia --project=scripts/formatter -e 'include("scripts/formatter/formatter_code.jl")'`).

### Phase 0 — unblock PowerAnalytics

PG cannot build until PA does. PA needs `deps/generator_mapping.yaml` fixed (two retired
`ThermalFuels` names) and its `test/Project.toml` given OpenAPI/PTDP source pins. Both are §2 of
`../PowerAnalytics.jl/.claude/plans/2026-08-17-pa-part-b-self-contained-outputs.md`; the YAML
fix is already applied in PA's working tree.

**Gate:** `using PowerAnalytics` in PG's test env.

### Phase 1 — environment

1. `Project.toml`: `[sources]` path pins for PSY, IS, PA. No version bump (PG stays `0.22.1`),
   no compat bump (PSY `^5.10`, IS `3`, PA `^1.1`).
2. `test/Project.toml`: drop `PowerSimulations`, `StorageSystemsSimulations`,
   `HydroPowerSimulations`; add `InfrastructureOptimizationModels` and
   `PowerOperationsModels`. Add the same OpenAPI + `PowerTableDataParser` `[deps]`/`[sources]`
   pins PA needs — PG's test env has the same unregistered-transitive-dep problem, and it
   resolves registered PSI otherwise.

**Gate:** `Pkg.instantiate()` in both envs.

### Phase 2 — the trivial substitutions

3. `PA.no_datetime` → `PA.get_data_df` at all 8 sites: `src/call_plots.jl:80,344,360,420,443,764`,
   `ext/plot_recipes.jl:46`, `ext/plotly_recipes.jl:26`.
4. `PA.PSI.get_system(result)` → `IS.get_source_data(outputs)` at `src/call_plots.jl:709`,
   keeping the existing `ArgumentError` when it comes back empty.

**Gate:** these two alone remove 9 of the 25 broken call sites.

### Phase 3 — `plot_powerdata` becomes `plot_dataframe`-shaped

5. Delete the `PA.PowerData` methods (`call_plots.jl:487-636`). The `plot_powerdata` family
   already reduces to `_plot_dataframe!(p, data, time, backend; ...)`; make that the signature.
   The `combine_categories` / `names` / `aggregate` kwargs move to the caller's choice of
   selector.
6. Decide whether `plot_powerdata` survives as a deprecated alias of `plot_dataframe` or is
   deleted outright. Under no-shims: **delete it**, and say so in the docs.

### Phase 4 — `plot_demand`

7. `_plot_demand!` (`call_plots.jl:199,213`): replace `get_load_data` + `combine_categories`
   with one `compute` over `Selectors.all_loads`. `_translate_demand_aggregate` — which existed
   to convert a `String` kwarg into PA's typed `aggregation` — becomes a `time_agg_fn` /
   `component_agg_fn` choice. The `extra_load` splice and the `"No load data found"` error stay.

### Phase 5 — `plot_fuel`, the deep one

8. `_plot_fuel!` (`call_plots.jl:700-790`) collapses from four PA calls to one:

```julia
fuel = PA.compute(PA.Metrics.calc_active_power, outputs,
                  PA.Selectors.categorized_generators)
cats = PA.get_data_cols(fuel)
matched   = intersect(get_palette_category(palette), cats)
unmatched = setdiff(cats, get_palette_category(palette))
fuel_agg  = fuel[!, vcat(PA.DATETIME_COL, matched, sort(unmatched))]
```

9. The storage-charging branch (`call_plots.jl:758-766`) reads `" In"` columns out of the same
   frame instead of a dict of frames.
10. `curtailment` and `slacks` kwargs: `categorize_data` handled both. Curtailment is now
    `PA.Metrics.calc_curtailment`; slack is `PA.Metrics.calc_system_slack_up`, which **requires
    a selector** — there is deliberately no default, because `ACBus` would silently return the
    wrong answer under `AreaBalanceNetworkModel`. PG must pass one or drop the kwarg.

**This is where coverage can silently change.** Compare a rendered `plot_fuel` before and after
against the same outputs directory, not just "it runs".

### Phase 6 — tests

11. `test/runtests.jl:12-25`: drop the PSI/Storage/Hydro imports and `const PSI`.
12. `test/runtests.jl:44` includes PA's `test/test_data/results_data.jl` directly. PA's fixture
    is itself still PSI-based and is being rebuilt (PA plan §4). **Define PG's own outputs
    builder locally** rather than re-coupling to PA's test internals — the old plan already
    agreed this, and PA's rewrite makes it necessary. One `DecisionModel` outputs object used
    everywhere; the `results_uc` / `results_ed` split collapses.
13. `test/test_plot_creation.jl:249` uses `PSB.build_system(PSB.PSISystems, "5_bus_hydro_uc_sys")`
    — verify the descriptor still builds under psy6 PSB (`psy6` branch, clean).
14. Hydro/storage formulations (`HydroTurbine`, `HydroReservoir`,
    `HydroTurbineEnergyDispatch`, `HydroEnergyModelReservoir`, `FixedOutput`,
    `StorageDispatchWithReserves`) all live in POM now. There is **no** `template_unit_commitment`
    — build templates explicitly.

**Gate:** `julia --project=test test/runtests.jl`. Note the IS `MultiLogger` fails the run on any
Error-level log event.

### Phase 7 — docs

15. `docs/make.jl`, `docs/src/index.md`, `docs/src/tutorials/examples.md` all reference
    PowerSimulations. Retarget InterLinks to IOM/POM.
16. `src/call_plots.jl` docstrings at `:145,:151,:265,:323,:324,:649,:807` cite
    `PowerSimulations.SimulationProblemResults`, `read_variables_with_keys`,
    `get_realized_timestamps`. Retarget to `IOM.OptimizationProblemOutputs` and
    `IOM.read_outputs_with_keys`.
17. `IS.Outputs` is **not exported** by IS — any `@extref InfrastructureSystems.Results` link
    needs retargeting or Documenter fails.

**Already done** in the tree: `IS.Results` → `IS.Outputs` (18 sites, `src/call_plots.jl` +
`ext/WeaveExt.jl`), `PSY.Bus` → `PSY.ACBus` in the `plot_demand` docstring — commit `86c3d89`.

## 4. Constraints carried over

- **Mirror both backends.** Any plotting-behavior change lands in *both* `ext/plot_recipes.jl`
  and `ext/plotly_recipes.jl`. Phase 2's `get_data_df` swap touches both.
- **Backends stay weak deps.** Nothing here adds a package to `[deps]`.
- **PG's runtime surface is PSY + IS + PA.** IOM and POM appear only in `test/Project.toml`.
  Phase 2's `IS.get_source_data` keeps it that way — the generic comes from IS, and IOM's
  method on `OptimizationProblemOutputs` dispatches without PG linking IOM.
- No version bumps, no compat bumps, no shims.

## 5. Risks

- **Phase 5 is where visual regressions hide.** The category set matches (§2, verified 13
  categories), but `categorize_data`'s handling of curtailment and slack was bespoke and its
  replacement is three separate metrics. Diff rendered figures, not just exit codes.
- **PA's test fixture is a moving target.** Phase 6 step 12 decouples from it deliberately; do
  that before PA's fixture rewrite lands, not after.
- **IOM is on `jd/network-sources` and POM on `jd/network_matrix_consolidation`** — neither is a
  line branch. Their APIs can move mid-refactor. They are test-only for PG, which limits the
  blast radius to Phase 6.
