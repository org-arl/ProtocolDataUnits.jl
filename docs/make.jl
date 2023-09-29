using Documenter

push!(LOAD_PATH,"../src/")
using PDUs

makedocs(
  sitename = "PDUs.jl",
  format = Documenter.HTML(prettyurls = false),
  linkcheck = !("skiplinks" in ARGS),
  pages = Any[
    "Home" => "index.md",
  ]
)

deploydocs(
  repo = "github.com/org-arl/PDUs.jl.git",
  branch = "gh-pages",
  devbranch = "master",
  devurl = "dev",
  versions = ["stable" => "v^", "v#.#", "dev" => "dev"]
)
