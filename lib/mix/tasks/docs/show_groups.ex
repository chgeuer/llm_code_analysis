defmodule Mix.Tasks.Docs.ShowGroups do
  use Mix.Task

  @moduledoc """
  Shows the computed ExDoc module groups based on category_mappings().

  ## Usage

      mix docs.show_groups

  This displays how modules are categorized for both the LLM API reference
  and the ExDoc HTML documentation. Both use the same category_mappings()
  function, ensuring consistency.
  """

  @shortdoc "Shows computed ExDoc module groups"

  @impl Mix.Task
  def run(_args) do
    # Get the docs config
    config = Mix.Project.config()
    docs = config[:docs]
    groups = docs[:groups_for_modules]

    IO.puts("\n=== Module Groups (Computed from category_mappings) ===\n")

    Enum.each(groups, fn {category, modules} ->
      IO.puts("## #{category}")
      IO.puts("   #{length(modules)} module(s)\n")

      modules
      |> Enum.each(fn mod ->
        IO.puts("   - #{inspect(mod)}")
      end)

      IO.puts("")
    end)

    total_modules = Enum.sum(Enum.map(groups, fn {_, mods} -> length(mods) end))
    IO.puts("=== Total: #{length(groups)} categories, #{total_modules} modules ===\n")
  end
end
