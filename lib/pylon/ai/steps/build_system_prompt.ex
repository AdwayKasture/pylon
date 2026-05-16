defmodule Pylon.AI.Steps.BuildSystemPrompt do
  @moduledoc """
  Step that builds the system prompt with available tool descriptions.

  Adds a system message to the context's messages list containing:
  - The agent's goal
  - Instructions on tool calling format
  - Instructions on completion format
  - Descriptions of all available tools

  """

  @behaviour Pylon.AI.Agent.Step

  alias Pylon.AI.Toolset

  @impl true
  def call(ctx, _opts) do
    specs =
      ctx.available_tools
      |> Enum.map(&Toolset.get/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&Toolset.format_tool/1)
      |> Enum.join("\n")

    system_prompt = build_prompt(ctx.goal, specs)
    system_message = %{role: :system, content: system_prompt}

    %{ctx | messages: [system_message]}
  end

  defp build_prompt(goal, tool_specs) do
    """
    #{goal}

    You can call one tool at a time.
    To call a tool you must give a JSON format such as mentioned below.
    DO NOT explain reasoning just return the structured output.

    ```json
    {"tool": "tool_name","args": {"tool_arg_a": "data_a","tool_arg_b": "data_b"}}
    ```

    When you have completed your task, respond with a completion in JSON format:

    ```json
    {"completion": {"result": "your final result here", "details": "any additional details"}}
    ```

    You have access to the following tools:
    #{tool_specs}
    """
  end
end
