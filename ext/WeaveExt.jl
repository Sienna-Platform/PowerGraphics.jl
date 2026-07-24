module WeaveExt

using PowerGraphics
using Weave

function PowerGraphics.report(
    res::PowerGraphics.IS.Results,
    out_path::String,
    design_template::String;
    kwargs...,
)
    doctype = get(kwargs, :doctype, "md2pdf")
    plot_backend = get(kwargs, :backend, PowerGraphics.CairoMakieBackend())

    !isfile(design_template) &&
        throw(ArgumentError("The provided template file is invalid"))
    args = Dict("results" => res, "backend" => plot_backend)
    Weave.weave(
        design_template;
        out_path = out_path,
        latex_cmd = ["xelatex"],
        doctype = doctype,
        args = args,
    )
end

end
