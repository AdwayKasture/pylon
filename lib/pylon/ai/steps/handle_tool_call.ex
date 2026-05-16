defmodule Pylon.AI.Steps.HandleToolCall do
  @moduledoc """
  Step that handles tool execution when the LLM requests a tool call.

  Checks if the parsed response contains a tool call request,
  executes the tool, and updates the conversation history.

  If no tool call is present, passes through unchanged.

  """

  @behaviour Pylon.AI.Agent.Step

  alias Pylon.AI.Toolset
  require Logger

  @impl true
  def call(ctx, _opts) do
    Logger.info("HandleToolCall: parsed_response = #{inspect(ctx.parsed_response)}")
    
    case ctx.parsed_response do
      %{"tool" => tool_name, "args" => args} when is_binary(tool_name) and is_map(args) ->
        Logger.info("HandleToolCall: executing tool '#{tool_name}'")
        execute_tool(ctx, tool_name, args)

      _ ->
        # Not a tool call response, pass through unchanged
        Logger.info("HandleToolCall: no tool call found")
        ctx
    end
  end

  defp execute_tool(ctx, tool_name, args) do
    case Toolset.get(tool_name) do
      nil ->
        Logger.error("Agent #{ctx.name}: Unknown tool '#{tool_name}'")
        error_msg = "Tool '#{tool_name}' is not registered"
        update_history_with_error(ctx, error_msg)

      tool_module ->
        Logger.info("Agent #{ctx.name} executing tool '#{tool_name}' with args: #{inspect(args)}")

        try do
          case tool_module.run(args) do
            {:ok, result} ->
              Logger.info("Agent #{ctx.name}: Tool '#{tool_name}' succeeded")
              update_history_with_success(ctx, tool_name, result)

            {:error, reason} ->
              Logger.warning("Agent #{ctx.name}: Tool '#{tool_name}' failed: #{inspect(reason)}")
              update_history_with_failure(ctx, tool_name, reason)
          end
        rescue
          e ->
            Logger.error("Agent #{ctx.name}: Tool '#{tool_name}' raised exception: #{inspect(e)}")
            update_history_with_failure(ctx, tool_name, "Exception: #{inspect(e)}")
        end
    end
  end

  defp update_history_with_success(ctx, tool_name, result) do
    message = %{role: :user, content: "Tool '#{tool_name}' returned: #{inspect(result)}"}

    %{
      ctx
      | tool_result: result,
        history: ctx.history ++ [message]
    }
  end

  defp update_history_with_failure(ctx, tool_name, reason) do
    message = %{role: :user, content: "Tool '#{tool_name}' failed: #{inspect(reason)}"}

    %{
      ctx
      | tool_result: {:error, reason},
        history: ctx.history ++ [message]
    }
  end

  defp update_history_with_error(ctx, error) do
    message = %{role: :user, content: error}
    %{ctx | history: ctx.history ++ [message]}
  end
end
