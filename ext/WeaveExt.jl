# RETIRED. Weave.jl is unmaintained — no new release in years — and it pins JSON 0.21,
# while the psy6 stack requires JSON ^1.5. It therefore cannot be installed alongside
# PowerSystems/InfrastructureSystems at all, so this extension can never load.
#
# The code is kept commented out rather than deleted so a replacement report generator
# has the original Weave.weave() invocation and template contract to work from.
# `report_templates/generic_report_template.jmd` is likewise kept on disk.
#
# To revive: restore Weave to [weakdeps]/[extensions]/[compat] in Project.toml and
# `function report end` plus `export report` in src/PowerGraphics.jl.

# module WeaveExt
#
# using PowerGraphics
# using Weave
#
# """
#     report(res::IS.Outputs, out_path::String, design_template::String)
#
# This function uses [`Weave.jl`](https://weavejl.mpastell.com/stable/) to either generate a LaTeX or HTML
# file based on the `report_design.jmd` (Julia markdown) file
# that it reads.
#
# An example template is available
# [here](https://github.com/Sienna-Platform/PowerGraphics.jl/blob/main/report_templates/generic_report_template.jmd)
#
# # Arguments
# - `results::IS.Outputs`: The results to be plotted
# - `out_path::String`: folder path to the location the report should be generated
# - `design_template::String = "file_path"`: directs the function to the julia markdown report design, the default
#
# # Example
# ```julia
# results = solve_op_problem!(OpModel)
# out_path = "/Users/downloads"
# report(results, out_path, template)
# ```
#
# # Accepted Key Words
# - `doctype::String = "md2html"`: create an HTML, default is PDF via latex
# - `backend::PlottingBackend = CairoMakieBackend()`: sets the plotting backend (CairoMakieBackend or PlotlyLightBackend)
# """
# function PowerGraphics.report(
#     res::PowerGraphics.IS.Outputs,
#     out_path::String,
#     design_template::String;
#     kwargs...,
# )
#     doctype = get(kwargs, :doctype, "md2pdf")
#     plot_backend = get(kwargs, :backend, PowerGraphics.CairoMakieBackend())
#
#     !isfile(design_template) &&
#         throw(ArgumentError("The provided template file is invalid"))
#     args = Dict("results" => res, "backend" => plot_backend)
#     Weave.weave(
#         design_template;
#         out_path = out_path,
#         latex_cmd = ["xelatex"],
#         doctype = doctype,
#         args = args,
#     )
# end
#
# end
