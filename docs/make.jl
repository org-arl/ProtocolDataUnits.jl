using Documenter

push!(LOAD_PATH,"../src/")
using ProtocolDataUnits

makedocs(
  sitename = "ProtocolDataUnits.jl",
  format = Documenter.HTML(prettyurls = false)
)

deploydocs(
  repo = "github.com/org-arl/ProtocolDataUnits.jl.git",
  branch = "gh-pages",
  devbranch = "master",
  devurl = "dev",
  versions = ["stable" => "v^", "v#.#", "dev" => "dev"]
)
