defmodule Pylon.AI.Agent.Context do
  @moduledoc """
  Context struct for agent step execution, inspired by Absinthe.Resolution.

  The context holds all state for a single iteration of the ReAct loop.
  Steps can read from and write to the context, and use helper functions
  to control pipeline flow.

  ## Fields

    * `name` - Agent name
    * `goal` - The goal the agent is trying to achieve
    * `input` - Optional additional input context
    * `model` - LLM model identifier (e.g., "google:gemini-2.5-flash")
    * `available_tools` - List of tool names the agent can use
    * `history` - Accumulated message history for the conversation
    * `step_count` - Current iteration number (0-indexed)
    * `max_steps` - Maximum allowed iterations before forced halt
    * `messages` - Messages built for the current LLM call
    * `llm_response` - Raw response from the LLM
    * `parsed_response` - Parsed JSON from LLM response
    * `tool_result` - Result of the last tool execution
    * `value` - Final result value when successfully completed
    * `errors` - List of accumulated errors (like Absinthe.Resolution.errors)
    * `state` - Current state: `:cont`, `:halt`, `:error`, or `:max_steps_reached`
    * `halted` - Boolean indicating if pipeline should stop
    * `assigns` - User-defined data storage (map)
    * `metadata` - Additional metadata (timings, tokens, etc.)

  """

  defstruct [
    # Agent configuration
    :name,
    :goal,
    :input,
    :model,
    :available_tools,

    # Execution state
    :history,
    :step_count,
    :max_steps,

    # Current iteration data
    :messages,
    :llm_response,
    :parsed_response,
    :tool_result,

    # Result and control flow (Absinthe-style)
    :result,
    errors: [],
    state: :cont,
    halted: false,

    # Extensibility
    assigns: %{},
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          goal: String.t(),
          input: String.t() | nil,
          model: String.t(),
          available_tools: list(String.t()),
          history: list(),
          step_count: non_neg_integer(),
          max_steps: non_neg_integer() | nil,
          messages: list(),
          llm_response: ReqLLM.Response.t() | nil,
          parsed_response: map() | nil,
          tool_result: any(),
          result: any(),
          errors: list(),
          state: :cont | :halt | :error | :max_steps_reached,
          halted: boolean(),
          assigns: map(),
          metadata: map()
        }

  @doc """
  Sets the result to a success value and halts the pipeline.

  Like `Absinthe.Resolution.put_result({:ok, value})`.

  ## Examples

      Context.put_result(ctx, {:ok, %{result: "Calculation complete"}})
      # => %{ctx | result: %{result: "Calculation complete"}, state: :halt, halted: true}

  """
  @spec put_result(t(), {:ok, any()} | {:error, any()}) :: t()
  def put_result(ctx, {:ok, result}) do
    %{ctx | result: result, state: :halt, halted: true}
  end

  def put_result(ctx, {:error, error}) do
    %{ctx | result: {:error, error}, errors: [error | ctx.errors], state: :error, halted: true}
  end

  @doc """
  Halts the pipeline without setting a result.

  Use when stopping early for non-error reasons.

  ## Examples

      Context.halt(ctx)
      # => %{ctx | state: :halt, halted: true}

  """
  @spec halt(t()) :: t()
  def halt(ctx) do
    %{ctx | state: :halt, halted: true}
  end

  @doc """
  Adds an error to the errors list without halting.

  Use for non-fatal errors that shouldn't stop execution.
  The pipeline continues, but the error is recorded.

  ## Examples

      Context.add_error(ctx, "Warning: tool took longer than expected")
      # => %{ctx | errors: ["Warning: tool took longer than expected" | ctx.errors]}

  """
  @spec add_error(t(), any()) :: t()
  def add_error(ctx, error) do
    %{ctx | errors: [error | ctx.errors]}
  end

  @doc """
  Assigns a value to the context's assigns map.

  Useful for storing custom data between steps.

  ## Examples

      Context.assign(ctx, :token_count, 150)
      # => %{ctx | assigns: %{token_count: 150}}

  """
  @spec assign(t(), atom(), any()) :: t()
  def assign(ctx, key, value) do
    %{ctx | assigns: Map.put(ctx.assigns, key, value)}
  end

  @doc """
  Retrieves a value from the context's assigns map.

  ## Examples

      Context.get_assign(ctx, :token_count)
      # => 150

      Context.get_assign(ctx, :unknown_key, :default)
      # => :default

  """
  @spec get_assign(t(), atom(), any()) :: any()
  def get_assign(ctx, key, default \\ nil) do
    Map.get(ctx.assigns, key, default)
  end

  @doc """
  Updates metadata with the given key-value pair.

  ## Examples

      Context.put_metadata(ctx, :llm_latency_ms, 245)
      # => %{ctx | metadata: %{llm_latency_ms: 245}}

  """
  @spec put_metadata(t(), atom(), any()) :: t()
  def put_metadata(ctx, key, value) do
    %{ctx | metadata: Map.put(ctx.metadata, key, value)}
  end

  @doc """
  Creates a new context from agent initialization options.

  ## Examples

      Context.new(
        name: "agent-1",
        goal: "Calculate 2+2",
        tools: ["calculator"],
        model: "google:gemini-2.5-flash"
      )

  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      name: opts[:name],
      goal: opts[:goal],
      input: opts[:input],
      model: opts[:model],
      available_tools: opts[:tools] || [],
      history: [],
      step_count: 0,
      max_steps: opts[:max_steps],
      messages: [],
      llm_response: nil,
      parsed_response: nil,
      tool_result: nil,
      result: nil,
      errors: [],
      state: :cont,
      halted: false,
      assigns: %{},
      metadata: %{}
    }
  end

  @doc """
  Updates the context for the next iteration of the ReAct loop.

  Clears iteration-specific fields and increments step_count.

  """
  @spec next_iteration(t()) :: t()
  def next_iteration(ctx) do
    %{
      ctx
      | step_count: ctx.step_count + 1,
        messages: [],
        llm_response: nil,
        parsed_response: nil,
        tool_result: nil,
        state: :cont,
        halted: false
    }
  end
end
