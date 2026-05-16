defmodule Pylon.AI.Agent.Step do
  @moduledoc """
  Behaviour for composable agent steps, inspired by Absinthe.Middleware.

  Each step receives a Context and options, transforms the context,
  and returns it. Steps can halt the pipeline by calling
  `Context.put_result/2` or `Context.halt/1`.

  ## Example

      defmodule MyApp.Steps.LogStep do
        @behaviour Pylon.AI.Agent.Step
        require Logger

        @impl true
        def call(ctx, _opts) do
          Logger.info("Processing step \#{ctx.step_count} for \#{ctx.name}")
          ctx  # Return unchanged to continue
        end
      end

  """

  alias Pylon.AI.Agent.Context

  @doc """
  Executes the step with the given context and options.

  Returns an updated Context. Use `Context.put_result/2` to set the final
  result and halt the pipeline, or `Context.halt/1` to stop without a result.
  Use `Context.add_error/2` to accumulate non-fatal errors.

  ## Parameters

    * `context` - The current `Pylon.AI.Agent.Context` struct
    * `opts` - Keyword list of options passed when the step was configured

  ## Returns

  An updated `Pylon.AI.Agent.Context` struct.
  """
  @callback call(context :: Context.t(), opts :: keyword()) :: Context.t()
end
