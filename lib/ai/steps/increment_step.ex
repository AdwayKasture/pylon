defmodule Pylon.AI.Steps.IncrementStep do
  @moduledoc """
  Step that increments the step counter.

  This step is typically the last in the default pipeline.
  It prepares the context for the next iteration of the ReAct loop.

  Note: This step marks the context as ready for the next iteration
  by clearing iteration-specific fields. The GenServer will handle
  the actual loop continuation.

  """

  @behaviour Pylon.AI.Agent.Step

  @impl true
  def call(ctx, _opts) do
    # Mark this iteration as complete
    # The GenServer will call Context.next_iteration/1 before the next run
    ctx
  end
end
