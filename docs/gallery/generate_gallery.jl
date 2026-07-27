# Regenerates committed gallery PNGs for docs/src/assets/gallery/.
# Run from the PowerGraphics repo root:
#   julia --project=test docs/gallery/generate_gallery.jl
#
# Demand: PSCB PSITestSystems / test_RTS_GMLC_sys.
# Generation / fuel: short UC/ED from PowerAnalytics test helper (same stack
# used by PowerGraphics tests) so formulations stay maintainable.

using CairoMakie
using HiGHS
using HydroPowerSimulations
using PowerAnalytics
using PowerGraphics
using PowerSimulations
using PowerSystemCaseBuilder
using PowerSystems
using StorageSystemsSimulations

const PSB = PowerSystemCaseBuilder
const PSY = PowerSystems
const PSI = PowerSimulations
const PA = PowerAnalytics

include(joinpath(@__DIR__, "entries.jl"))

const OUT = joinpath(dirname(@__DIR__), "src", "assets", "gallery")
mkpath(OUT)

const PA_DIR = dirname(dirname(pathof(PowerAnalytics)))
include(joinpath(PA_DIR, "test", "test_data", "results_data.jl"))

const GALLERY_LEGEND_FONT = 18

function _style!(p)
    p.axis.xticklabelsize = 16
    p.axis.yticklabelsize = 16
    p.axis.xlabelsize = 18
    p.axis.ylabelsize = 18
    p.axis.titlesize = 20
    return p
end

function _save(p, name)
    _style!(p)
    path = joinpath(OUT, "$name.png")
    save_plot(p, path)
    @info "Wrote $path"
    return path
end

@info "Building RTS test system for demand"
sys = PSB.build_system(PSB.PSITestSystems, "test_RTS_GMLC_sys")
PSY.set_units_base_system!(sys, "SYSTEM_BASE")

@info "Demand stack (System aggregate)"
p = plot_demand(
    sys;
    aggregate = "System",
    stack = true,
    set_display = false,
    title = "demand_stack",
    legend_font_size = GALLERY_LEGEND_FONT,
)
_save(p, "demand_stack")

@info "Running short UC/ED for generation / fuel plots"
result_dir = mktempdir()
results_uc, _ = run_test_sim(result_dir, "gallery_sim")
gen = PA.get_generation_data(results_uc)

@info "Fuel"
_save(
    plot_fuel(
        results_uc;
        set_display = false,
        title = "fuel",
        legend_font_size = GALLERY_LEGEND_FONT,
    ),
    "fuel",
)

@info "PowerData line / stack / stair / bar / bar+stack"
_save(
    plot_powerdata(
        gen;
        set_display = false,
        title = "powerdata_line",
        label_fn = label_component,
        legend_font_size = GALLERY_LEGEND_FONT,
    ),
    "powerdata_line",
)
_save(
    plot_powerdata(
        gen;
        set_display = false,
        title = "powerdata_stack",
        stack = true,
        label_fn = label_component,
        legend_font_size = GALLERY_LEGEND_FONT,
    ),
    "powerdata_stack",
)
_save(
    plot_powerdata(
        gen;
        set_display = false,
        title = "powerdata_stair",
        stair = true,
        label_fn = label_component,
        legend_font_size = GALLERY_LEGEND_FONT,
    ),
    "powerdata_stair",
)
_save(
    plot_powerdata(
        gen;
        set_display = false,
        title = "powerdata_bar",
        bar = true,
        label_fn = label_component,
        legend_font_size = GALLERY_LEGEND_FONT,
    ),
    "powerdata_bar",
)
_save(
    plot_powerdata(
        gen;
        set_display = false,
        title = "powerdata_bar_stack",
        bar = true,
        stack = true,
        label_fn = label_component,
        legend_font_size = GALLERY_LEGEND_FONT,
    ),
    "powerdata_bar_stack",
)

@info "DataFrame"
df_key = first(keys(gen.data))
df = gen.data[df_key]
_save(
    plot_dataframe(
        df,
        gen.time;
        set_display = false,
        title = "dataframe",
        legend_font_size = GALLERY_LEGEND_FONT,
    ),
    "dataframe",
)

for e in GALLERY_ENTRIES
    path = joinpath(OUT, "$(e.image).png")
    isfile(path) || error("Missing gallery image for entry $(e.title): $path")
end

@info "Gallery images written to $OUT"
