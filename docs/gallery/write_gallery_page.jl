# Writes docs/src/gallery/index.md from entries.jl.
# Called from docs/make.jl before makedocs.

include(joinpath(@__DIR__, "entries.jl"))

function write_gallery_page()
    out = joinpath(dirname(@__DIR__), "src", "gallery", "index.md")
    io = IOBuffer()
    println(io, "# [Gallery](@id gallery)")
    println(io)
    println(io, "```@meta")
    println(io, "CurrentModule = PowerGraphics")
    println(io, "```")
    println(io)
    println(io, "```@raw html")
    println(io, "<div class=\"pg-gallery\">")
    println(io, "```")
    println(io)

    for e in GALLERY_ENTRIES
        println(io, "```@raw html")
        println(io, "<div class=\"pg-gallery-card\">")
        println(io, "```")
        println(io)
        println(
            io,
            "[![$(e.title)](../assets/gallery/$(e.image).png)](@ref $(e.ref))",
        )
        println(io)
        println(io, e.title)
        println(io, "`$(e.code)`")
        println(io)
        println(io, "```@raw html")
        println(io, "</div>")
        println(io, "```")
        println(io)
    end

    println(io, "```@raw html")
    println(io, "</div>")
    print(io, "```\n")

    write(out, String(take!(io)))
    @info "Wrote $out"
    return out
end
