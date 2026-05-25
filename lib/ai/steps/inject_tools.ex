defmodule Pylon.AI.Steps.InjectTools do
  @moduledoc """
  Step that injects available tool descriptions into the system prompt.

  Appends a system message to the context's messages list containing
  descriptions of all available tools formatted in XML.
  """

  @behaviour Pylon.AI.Agent.Step

  alias Pylon.AI.Toolset

  @impl true
  def call(ctx, _opts) do
    specs =
      ctx.available_tools
      |> Enum.map(&Toolset.get/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&Toolset.format_tool_xml/1)
      |> Enum.join("\n")

    tools_prompt = build_tools_prompt(specs)
    tools_message = %{role: :system, content: tools_prompt}

    %{ctx | messages: ctx.messages ++ [tools_message]}
  end

  defp build_tools_prompt(tool_specs) do
    """
    You have access to the following tools:

    <tools>
    #{tool_specs}
    </tools>
    """
  end
end
