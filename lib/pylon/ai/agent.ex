defmodule Pylon.AI.Agent do
  @moduledoc """
  Generic AI Agent that takes tools, goals, and args.
  Implements a synchronous ReAct pattern with composable steps.

  ## Usage

  ### Cast mode (async with callback):

      {:ok, _pid} = Pylon.AI.Agent.start(
        name: "agent-1",
        goal: "Calculate (5 + 3) * 2",
        tools: ["calculator"],
        on_complete: {self(), :agent_done}
      )

      # Receive result:
      receive do
        {:agent_done, "agent-1", result} -> ...
      end

  ### Call mode (blocking):

      {:ok, result} = Pylon.AI.Agent.run(
        name: "agent-1",
        goal: "Calculate (5 + 3) * 2",
        tools: ["calculator"],
        timeout: 30_000
      )

  ### Custom steps:

      {:ok, result} = Pylon.AI.Agent.run(
        name: "agent-1",
        goal: "Calculate (5 + 3) * 2",
        tools: ["calculator"],
        steps: [
          Pylon.AI.Steps.BuildSystemPrompt,
          MyApp.Steps.CustomLogging,
          Pylon.AI.Steps.CallLLM,
          Pylon.AI.Steps.ParseResponse,
          Pylon.AI.Steps.CheckCompletion,
          Pylon.AI.Steps.HandleToolCall,
          Pylon.AI.Steps.CheckStepCount,
          Pylon.AI.Steps.IncrementStep
        ]
      )

  """
  use GenServer, restart: :temporary

  alias Pylon.AI.Agent.Context
  alias Pylon.AI.Agent.Pipeline

  require Logger

  defstruct name: nil,
            goal: nil,
            input: nil,
            available_tools: [],
            history: [],
            model: nil,
            step: 0,
            max_steps: nil,
            from: nil,
            on_complete: nil,
            caller: nil,
            steps: []

  @type t :: %__MODULE__{
          name: String.t(),
          goal: String.t(),
          input: String.t() | nil,
          available_tools: list(String.t()),
          history: list(),
          model: String.t(),
          step: non_neg_integer(),
          max_steps: non_neg_integer() | nil,
          from: GenServer.from() | nil,
          on_complete: {pid(), atom()} | nil,
          caller: pid() | nil,
          steps: list(module() | {module(), keyword()})
        }

  @default_model "google:gemini-2.5-flash"

  @default_steps [
    Pylon.AI.Steps.BuildSystemPrompt,
    Pylon.AI.Steps.CallLLM,
    Pylon.AI.Steps.ParseResponse,
    Pylon.AI.Steps.CheckCompletion,
    Pylon.AI.Steps.HandleToolCall,
    Pylon.AI.Steps.CheckStepCount,
    Pylon.AI.Steps.IncrementStep
  ]

  # Public API

  @doc """
  Starts an agent asynchronously (cast mode).
  The agent will send a message to the callback when complete.

  ## Options

  * `:name` - Required. Unique name for the agent (registered in Registry).
  * `:goal` - Required. The goal for the agent to achieve.
  * `:tools` - Required. List of tool names the agent can use.
  * `:input` - Optional. Additional input context for the agent.
  * `:model` - Optional. LLM model to use (defaults to "google:gemini-2.5-flash").
  * `:on_complete` - Required for cast mode. {pid, message} to send result to.
  * `:max_steps` - Optional. Maximum number of iterations before forcing halt.
  * `:steps` - Optional. Custom list of step modules to use instead of defaults.

  """
  def start(opts) do
    name = opts[:name] || raise "name is required"
    goal = opts[:goal] || raise "goal is required"
    tools = opts[:tools] || raise "tools is required"
    on_complete = opts[:on_complete] || raise "on_complete is required for start/1"

    spec = {
      __MODULE__,
      %{
        name: name,
        goal: goal,
        input: opts[:input],
        tools: tools,
        model: opts[:model] || @default_model,
        on_complete: on_complete,
        max_steps: opts[:max_steps],
        steps: opts[:steps] || @default_steps
      }
    }

    DynamicSupervisor.start_child(Pylon.AI.AgentSupervisor, spec)
  end

  @doc """
  Runs an agent synchronously and blocks until completion.

  ## Options

  * `:name` - Required. Unique name for the agent.
  * `:goal` - Required. The goal for the agent to achieve.
  * `:tools` - Required. List of tool names the agent can use.
  * `:input` - Optional. Additional input context for the agent.
  * `:model` - Optional. LLM model to use.
  * `:timeout` - Optional. Timeout in milliseconds (default: :infinity).
  * `:max_steps` - Optional. Maximum number of iterations before forcing halt.
  * `:steps` - Optional. Custom list of step modules to use instead of defaults.

  """
  def run(opts) do
    name = opts[:name] || raise "name is required"
    goal = opts[:goal] || raise "goal is required"
    tools = opts[:tools] || raise "tools is required"
    timeout = opts[:timeout] || :infinity
    caller = self()

    spec = {
      __MODULE__,
      %{
        name: name,
        goal: goal,
        input: opts[:input],
        tools: tools,
        model: opts[:model] || @default_model,
        on_complete: nil,
        caller: caller,
        max_steps: opts[:max_steps],
        steps: opts[:steps] || @default_steps
      }
    }

    case DynamicSupervisor.start_child(Pylon.AI.AgentSupervisor, spec) do
      {:ok, pid} ->
        # Wait for result from the agent
        ref = Process.monitor(pid)

        receive do
          {:agent_result, ^name, result} ->
            Process.demonitor(ref, [:flush])
            result

          {:DOWN, ^ref, :process, ^pid, reason} ->
            {:error, "Agent terminated unexpectedly: #{inspect(reason)}"}
        after
          timeout ->
            Process.exit(pid, :kill)
            {:error, :timeout}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the current state of a running agent.
  """
  def get_state(name) do
    case Registry.lookup(Pylon.AgentRegistry, name) do
      [{pid, _}] ->
        try do
          GenServer.call(pid, :get_state)
        catch
          :exit, _ -> {:error, :agent_not_running}
        end

      [] ->
        {:error, :agent_not_found}
    end
  end

  # GenServer Callbacks

  def child_spec(opts) do
    %{
      id: {__MODULE__, opts.name},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  def start_link(opts) do
    name = opts.name
    GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {Pylon.AgentRegistry, name}})
  end

  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      name: opts.name,
      goal: opts.goal,
      input: opts.input,
      available_tools: opts.tools,
      model: opts.model,
      history: [],
      step: 0,
      max_steps: opts.max_steps,
      from: nil,
      on_complete: opts.on_complete,
      caller: opts.caller,
      steps: opts.steps
    }

    # Start the agent loop immediately
    send(self(), :run)

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  def handle_info(:run, state) do
    # Build context from current state
    context =
      Context.new(
        name: state.name,
        goal: state.goal,
        input: state.input,
        model: state.model,
        tools: state.available_tools,
        max_steps: state.max_steps
      )
      |> Map.put(:history, state.history)
      |> Map.put(:step_count, state.step)

    # Run one iteration of the pipeline
    result_context = Pipeline.run(context, state.steps)
    
    Logger.warning("Agent loop: halted=#{result_context.halted}, result=#{inspect(result_context.result)}, step_count=#{result_context.step_count}")

    cond do
      result_context.halted ->
        # Pipeline halted (completion, error, or max_steps reached)
        Logger.warning("Agent completing with result: #{inspect(result_context.result)}")
        complete_agent(state, result_context.result)
        {:stop, :normal, state}

      true ->
        # Continue to next iteration
        new_state = %{
          state
          | history: result_context.history,
            step: result_context.step_count + 1
        }

        send(self(), :run)
        {:noreply, new_state}
    end
  end

  # Private Functions

  defp complete_agent(state, result) do
    # Ensure result is in {:ok, _} or {:error, _} format
    normalized_result =
      case result do
        {:ok, _} -> result
        {:error, _} -> result
        other -> {:ok, other}
      end

    # Notify callback if provided
    if state.on_complete do
      {pid, message} = state.on_complete
      send(pid, {message, state.name, normalized_result})
    end

    # Send result to the caller process (for run/1 blocking mode)
    if state.caller do
      send(state.caller, {:agent_result, state.name, normalized_result})
    end

    case normalized_result do
      {:ok, _} -> Logger.info("Agent #{state.name} completed successfully")
      {:error, reason} -> Logger.error("Agent #{state.name} failed: #{inspect(reason)}")
    end
  end
end
