defmodule Pylon.AI.Steps.CallLLM do
  @moduledoc """
  Step that calls the LLM with the built messages.

  Takes messages from context (system + history + input), calls the LLM,
  and stores the response in context.llm_response.

  """

  @behaviour Pylon.AI.Agent.Step

  alias Pylon.AI.Agent.Context
  alias Pylon.AI.LLMAdapter

  @impl true
  def call(ctx, _opts) do
    messages = build_full_messages(ctx)

    start_time = System.monotonic_time(:millisecond)

    result = LLMAdapter.generate_text(ctx.model, messages)

    end_time = System.monotonic_time(:millisecond)
    latency = end_time - start_time

    case result do
      {:ok, response} ->
        ctx
        |> Context.put_metadata(:llm_latency_ms, latency)
        |> Context.put_metadata(:llm_tokens, estimate_tokens(response))
        |> Map.put(:llm_response, response)

      {:error, reason} ->
        Context.put_result(ctx, {:error, "LLM API call failed: #{inspect(reason)}"})
    end
  end

  defp build_full_messages(ctx) do
    base_messages = ctx.messages ++ ctx.history

    # Only add user message on first iteration (step_count == 0)
    # After that, conversation continues via history
    if ctx.step_count == 0 do
      user_content = ctx.input || "Start working on this task."
      base_messages ++ [%{role: :user, content: user_content}]
    else
      base_messages
    end
  end

  defp estimate_tokens(response) do
    # Simplified token estimation
    # In production, this should use the actual token count from the API
    text = inspect(response)
    div(String.length(text), 4)
  end
end
