defmodule Pylon.AI.Agent.Pipeline do
  @moduledoc """
  Pipeline execution engine for agent steps.

  Executes a list of steps in sequence, passing the context through each.
  Stops early if a step marks the context as halted.

  ## Usage

      steps = [
        Pylon.AI.Steps.BuildSystemPrompt,
        Pylon.AI.Steps.CallLLM,
        Pylon.AI.Steps.ParseResponse
      ]

      context = Pipeline.run(context, steps)

  """

  alias Pylon.AI.Agent.Context

  @doc """
  Runs a pipeline of steps with the given initial context.

  Each step receives the context and returns an updated context.
  Execution stops when `ctx.halted` becomes true.

  ## Parameters

    * `context` - Initial `Pylon.AI.Agent.Context` struct
    * `steps` - List of step modules or {module, opts} tuples

  ## Returns

  The final `Pylon.AI.Agent.Context` struct after all steps have run
  or the pipeline was halted.

  """
  @spec run(Context.t(), list(module() | {module(), keyword()})) :: Context.t()
  def run(context, steps) when is_list(steps) do
    Enum.reduce_while(steps, context, fn step_spec, ctx ->
      {module, opts} = normalize_step(step_spec)

      if ctx.halted do
        {:halt, ctx}
      else
        new_ctx = module.call(ctx, opts)
        {:cont, new_ctx}
      end
    end)
  end

  @doc """
  Normalizes a step specification to a {module, opts} tuple.

  ## Examples

      iex> Pipeline.normalize_step(MyStep)
      {MyStep, []}

      iex> Pipeline.normalize_step({MyStep, [debug: true]})
      {MyStep, [debug: true]}

  """
  @spec normalize_step(module() | {module(), keyword()}) :: {module(), keyword()}
  def normalize_step(module) when is_atom(module), do: {module, []}
  def normalize_step({module, opts}) when is_atom(module) and is_list(opts), do: {module, opts}
end
