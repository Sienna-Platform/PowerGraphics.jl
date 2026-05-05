using Documenter
import DataStructures: OrderedDict
using PowerGraphics
using DocumenterInterLinks
using Literate


links = InterLinks(
    "Plots" => "https://docs.juliaplots.org/stable/",
    "PowerSystems" => "https://sienna-platform.github.io/PowerSystems.jl/stable/",
    "PowerSimulations" => "https://sienna-platform.github.io/PowerSimulations.jl/stable/",
    "InfrastructureSystems" => "https://sienna-platform.github.io/InfrastructureSystems.jl/stable/",
    "DataFrames" => "https://dataframes.juliadata.org/stable/",
)

include(joinpath(@__DIR__, "make_tutorials.jl"))
make_tutorials()

if haskey(ENV, "GITHUB_ACTIONS")
    ENV["JULIA_DEBUG"] = "Documenter"
end

pages = OrderedDict(
    "Welcome" => "index.md",
    ## TODO add additional pages here in the future and remove stubs
    "Tutorials" => Any["Examples" => "tutorials/examples.md"], # TODO: make examples page
    "How to..." => Any["Change Backends" => "how_to_guides/backends.md"],
    # "Explanation" => Any["stub" => "explanation/stub.md"],
    "Reference" => Any[ 
        "Public API" => "reference/public.md",
        "Developers" => ["Developer Guidelines" => "reference/developer_guidelines.md",
        "Internals" => "reference/internal.md"],
    ],
)

makedocs(;
    modules = [PowerGraphics],
    format = Documenter.HTML(
        prettyurls = haskey(ENV, "GITHUB_ACTIONS"),),
    sitename = "PowerGraphics.jl",
    authors = "Clayton Barrows",
    pages = Any[p for p in pages],
    draft = false,
    plugins = [links],
)

Documenter.deploydocs(;
    repo = "github.com/Sienna-Platform/PowerGraphics.jl.git",
    target = "build",
    branch = "gh-pages",
    devbranch = "main",
    devurl = "dev",
    push_preview = true,
    versions = ["stable" => "v^", "v#.#"],
)
