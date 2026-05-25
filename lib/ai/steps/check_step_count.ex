defmodule Pylon.AI.Steps.CheckStepCount do
  @moduledoc """
  Step that checks if the maximum step count has been reached.

  If step_count >= max_steps, halts the pipeline with an error.
  If no max_steps is set, passes through unchanged.

  """

  @behaviour Pylon.AI.Agent.Step

  alias Pylon.AI.Agent.Context
  require Logger

  @impl true
  def call(ctx, _opts) do
    case ctx.max_steps do
      nil ->
        # No limit set, continue
        ctx

      max when is_integer(max) and max > 0 ->
        if ctx.step_count >= max do
          Logger.warning("Agent #{ctx.name} reached max_steps limit (#{max})")

          ctx
          |> Map.put(:state, :max_steps_reached)
          |> Context.put_result(
            {:error, "Maximum step count (#{max}) reached without completion"}
          )
        else
          ctx
        end

      _invalid ->
        # Invalid max_steps, log warning but continue
        Logger.warning("Agent #{ctx.name}: Invalid max_steps value: #{inspect(ctx.max_steps)}")
        ctx
    end
  end
end
