defmodule Pylon.AI.Steps.BuildGoalPrompt do
  @moduledoc """
  Step that builds the system prompt with the agent's goal
  and XML response format instructions.

  Appends a system message to the context's messages list containing:
  - The agent's goal
  - Instructions on tool calling format (XML)
  - Instructions on completion format (XML)
  """

  @behaviour Pylon.AI.Agent.Step

  @impl true
  def call(ctx, _opts) do
    system_prompt = build_prompt(ctx.goal)
    system_message = %{role: :system, content: system_prompt}

    %{ctx | messages: [system_message]}
  end

  defp build_prompt(goal) do
    """
    #{goal}

    You can call one tool at a time.
    To call a tool you must give an XML format such as mentioned below.
    DO NOT explain reasoning just return the structured output.

    ```xml
    <tool_call>
      <name>tool_name</name>
      <args>
        <tool_arg_a>data_a</tool_arg_a>
        <tool_arg_b>data_b</tool_arg_b>
      </args>
    </tool_call>
    ```

    When you have completed your task, respond with a completion in XML format:

    ```xml
    <completion>
      <result>your final result here</result>
      <details>any additional details</details>
    </completion>
    ```
    """
  end
end
