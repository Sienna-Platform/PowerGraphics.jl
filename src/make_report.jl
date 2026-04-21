"""
    report(res::IS.Results, out_path::String, design_template::String)

This function uses [`Weave.jl`](https://weavejl.mpastell.com/stable/) to either generate a LaTeX or HTML
file based on the `report_design.jmd` (Julia markdown) file
that it reads. 

An example template is available
[here](https://github.com/Sienna-Platform/PowerGraphics.jl/blob/main/report_templates/generic_report_template.jmd)

# Arguments
- `results::IS.Results`: The results to be plotted
- `out_path::String`: folder path to the location the report should be generated
- `design_template::String = "file_path"`: directs the function to the julia markdown report design, the default

# Example
```julia
results = solve_op_problem!(OpModel)
out_path = "/Users/downloads"
report(results, out_path, template)
```

# Accepted Key Words
- `doctype::String = "md2html"`: create an HTML, default is PDF via latex
- `backend::Plots.AbstractBackend = Plots.gr()`: sets the `Plots.jl` [backend](@extref Plots backends)
"""
function report(res::IS.Results, out_path::String, design_template::String; kwargs...)
    doctype = get(kwargs, :doctype, "md2pdf")
    backend = get(kwargs, :backend, Plots.gr())
    initial_time = get(kwargs, :initial_time, nothing)
    len = get(kwargs, :horizon, nothing)

    !isfile(design_template) &&
        throw(ArgumentError("The provided template file is invalid"))
    args = Dict("results" => res, "backend" => backend)
    Weave.weave(
        design_template;
        out_path = out_path,
        latex_cmd = ["xelatex"],
        doctype = doctype,
        args = args,
    )
end
