defmodule Pylon.AI.Steps.CheckCompletion do
  @moduledoc """
  Step that checks if the agent has completed its task.

  Looks for a `{"completion": {...}}` in the parsed response.
  If found, halts the pipeline with the completion result.

  """

  @behaviour Pylon.AI.Agent.Step

  alias Pylon.AI.Agent.Context
  require Logger

  @impl true
  def call(ctx, _opts) do
    Logger.info("CheckCompletion: parsed_response = #{inspect(ctx.parsed_response)}")

    case ctx.parsed_response do
      %{"completion" => completion} when is_map(completion) ->
        Logger.info("Agent #{ctx.name} completed with result: #{inspect(completion)}")
        Context.put_result(ctx, {:ok, completion})

      %{"completion" => completion} ->
        Logger.info("Agent #{ctx.name} completed with non-map result: #{inspect(completion)}")
        Context.put_result(ctx, {:ok, %{"result" => completion}})

      _ ->
        # Not a completion response, continue to next step
        Logger.info("CheckCompletion: no completion found, continuing...")
        ctx
    end
  end
end
