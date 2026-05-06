defmodule Pylon.AI.Agent do
  @moduledoc """
  Generic AI Agent that takes tools, goals, and args.
  Implements a synchronous ReAct pattern.

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

  """
  use GenServer, restart: :temporary
  alias Pylon.AI.Toolset
  alias Pylon.AI.LLMAdapter
  alias ReqLLM.Context
  require Logger

  defstruct name: nil,
            goal: nil,
            input: nil,
            available_tools: [],
            history: [],
            model: nil,
            step: 0,
            from: nil,
            on_complete: nil,
            caller: nil

  @type t :: %__MODULE__{
          name: String.t(),
          goal: String.t(),
          input: String.t(),
          available_tools: list(String.t()),
          history: list(),
          model: String.t(),
          step: non_neg_integer(),
          from: GenServer.from() | nil,
          on_complete: {pid(), atom()} | nil,
          caller: pid() | nil
        }

  @default_model "google:gemini-2.5-flash"

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
        on_complete: on_complete
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
        caller: caller
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
      from: nil,
      on_complete: opts.on_complete,
      caller: opts.caller
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
    case run_step(state) do
      {:continue, new_state} ->
        # Schedule next step
        send(self(), :run)
        {:noreply, new_state}

      {:complete, result, final_state} ->
        complete_agent(final_state, result)
        {:stop, :normal, final_state}

      {:error, reason, final_state} ->
        complete_agent(final_state, {:error, reason})
        {:stop, :error, final_state}
    end
  end

  # Private Functions

  defp run_step(state) do
    messages = build_messages(state)

    case LLMAdapter.generate_text(state.model, messages) do
      {:ok, resp} ->
        resp
        |> ReqLLM.Response.text()
        |> parse_response()
        |> handle_response(state)

      {:error, reason} ->
        {:error, "LLM API call failed: #{inspect(reason)}", state}
    end
  end

  defp build_messages(state) do
    base_prompt =
      if state.input do
        """
        The input to process is given below:
        #{state.input}
        """
      else
        ""
      end

    [
      Context.system(system_prompt(state.available_tools, state.goal))
    ] ++ state.history ++ [Context.user(base_prompt)]
  end

  defp system_prompt(tools, goal) do
    specs =
      tools
      |> Enum.map(&Toolset.get/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&Toolset.format_tool/1)
      |> Enum.join("\n")

    """
    #{goal}

    You can call one tool at a time.
    To call a tool you must give a JSON format such as mentioned below.
    DO NOT explain reasoning just return the structured output.

    ```json
    {"tool": "tool_name","args": {"tool_arg_a": "data_a","tool_arg_b": "data_b"...}}
    ```

    When you have completed your task, respond with a completion in JSON format:

    ```json
    {"completion": {"result": "your final result here", "details": "any additional details"}}
    ```

    You have access to the following tools:
    #{specs}
    """
  end

  defp parse_response(text) when is_binary(text) do
    text
    |> String.trim_trailing("\n```")
    |> String.split("```json\n")
    |> case do
      [_, expected_json] -> expected_json
      [maybe_json] -> maybe_json
    end
    |> JSON.decode()
  end

  defp handle_response({:ok, %{"completion" => completion}}, state) when is_map(completion) do
    Logger.info("Agent #{state.name} completed with result: #{inspect(completion)}")
    {:complete, {:ok, completion}, state}
  end

  defp handle_response({:ok, %{"tool" => tool_name, "args" => args}}, state)
       when is_binary(tool_name) and is_map(args) do
    case execute_tool(tool_name, args, state) do
      {:ok, result} ->
        message_content = "Tool '#{tool_name}' returned: #{inspect(result)}"
        history = state.history ++ [Context.user(message_content)]

        new_state = %{
          state
          | history: history,
            step: state.step + 1
        }

        {:continue, new_state}

      {:error, reason} ->
        error_msg = "Tool '#{tool_name}' failed: #{inspect(reason)}"
        history = state.history ++ [Context.user(error_msg)]

        new_state = %{state | history: history, step: state.step + 1}
        {:continue, new_state}
    end
  end

  defp handle_response({:ok, invalid}, state) do
    {:error, "Invalid AI response format: #{inspect(invalid)}", state}
  end

  defp handle_response({:error, reason}, state) do
    {:error, "Failed to parse AI response: #{inspect(reason)}", state}
  end

  defp execute_tool(tool_name, args, state) do
    case Toolset.get(tool_name) do
      nil ->
        {:error, "Tool '#{tool_name}' is not registered"}

      tool_module ->
        Logger.info(
          "Agent #{state.name} executing tool '#{tool_name}' with args: #{inspect(args)}"
        )

        try do
          tool_module.run(args)
        rescue
          e ->
            Logger.error("Tool '#{tool_name}' raised exception: #{inspect(e)}")
            {:error, "Tool execution failed: #{inspect(e)}"}
        end
    end
  end

  defp complete_agent(state, result) do
    # Notify callback if provided
    if state.on_complete do
      {pid, message} = state.on_complete
      send(pid, {message, state.name, result})
    end

    # Send result to the caller process (for run/1 blocking mode)
    if state.caller do
      send(state.caller, {:agent_result, state.name, result})
    end

    Logger.info("Agent #{state.name} completed")
  end
end
