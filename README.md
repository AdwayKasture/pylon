# Pylon

An Elixir framework for building AI agents using the ReAct (Reasoning + Acting) pattern. Pylon provides a composable, step-based pipeline for orchestrating LLM-driven agents with tool use, wrapped in a robust GenServer architecture.

## Features

- **ReAct Pattern** — Synchronous reasoning and action loops with LLM-driven decision making
- **Composable Steps** — Pipeline-based agent execution inspired by Absinthe middleware; customize or extend any part of the loop
- **Tool System** — Behaviour-driven tools with O(1) lookup via `PersistentTerm`, plus automatic XML formatting for LLM prompts
- **Async & Sync Modes** — Run agents asynchronously with callbacks, or block synchronously until completion
- **Supervised Agents** — Each agent runs under a `DynamicSupervisor` with Registry-based discovery
- **LLM Agnostic** — Uses `req_llm` for LLM interactions; easily mockable for testing via Mox
- **Extensible Context** — Agent state managed through a Resolution-like context with assigns, metadata, and error accumulation

## Installation

Add `pylon` to your list of dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:pylon, path: "../pylon"}
    # or from git:
    # {:pylon, git: "https://github.com/your-org/pylon.git"}
  ]
end
```

Then register tools in your application startup:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    Pylon.AI.Toolset.register_tools([
      Pylon.AI.Tools.Calculator,
      Pylon.AI.Tools.Echo,
      MyApp.Tools.CustomSearch
    ])

    children = [
      {Registry, keys: :unique, name: Pylon.AgentRegistry},
      Pylon.AI.AgentSupervisor
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

## Quick Start

### Synchronous (Blocking) Mode

```elixir
{:ok, result} = Pylon.AI.Agent.run(
  name: "calculator-agent",
  goal: "Calculate (5 + 3) * 2",
  tools: ["calculator"],
  timeout: 30_000
)
```

### Asynchronous (Cast) Mode

```elixir
{:ok, _pid} = Pylon.AI.Agent.start(
  name: "calculator-agent",
  goal: "Calculate (5 + 3) * 2",
  tools: ["calculator"],
  on_complete: {self(), :agent_done}
)

receive do
  {:agent_done, "calculator-agent", result} ->
    IO.inspect(result)
end
```

## Architecture

### Agent

`Pylon.AI.Agent` is a GenServer that runs the ReAct loop. Each iteration:

1. Builds a context from current state
2. Runs the pipeline of steps
3. Checks if halted (completion, error, or max steps reached)
4. Either stops or continues with updated history

### Context

`Pylon.AI.Agent.Context` holds all state for a single loop iteration. It includes:

- **Config**: `name`, `goal`, `input`, `model`, `available_tools`
- **Execution state**: `history`, `step_count`, `max_steps`
- **Iteration data**: `messages`, `llm_response`, `parsed_response`, `tool_result`
- **Control flow**: `result`, `errors`, `state` (`:cont`, `:halt`, `:error`, `:max_steps_reached`), `halted`
- **Extensibility**: `assigns`, `metadata`

Context provides helpers inspired by `Absinthe.Resolution`:

```elixir
Context.put_result(ctx, {:ok, "Done"})   # Halt with success
Context.put_result(ctx, {:error, "Oops"}) # Halt with error
Context.halt(ctx)                         # Halt without result
Context.add_error(ctx, "Warning")         # Accumulate non-fatal error
Context.assign(ctx, :key, value)          # Store custom data
Context.get_assign(ctx, :key)             # Retrieve custom data
Context.put_metadata(ctx, :latency, 245)  # Store timing data
```

### Pipeline

`Pylon.AI.Agent.Pipeline` executes steps sequentially, passing the context through each. Execution stops when `ctx.halted` becomes true.

```elixir
steps = [
  Pylon.AI.Steps.BuildGoalPrompt,
  Pylon.AI.Steps.InjectTools,
  Pylon.AI.Steps.CallLLM,
  Pylon.AI.Steps.ParseResponse
]

context = Pipeline.run(context, steps)
```

Steps can be bare modules or `{module, opts}` tuples for configuration.

### Steps

`Pylon.AI.Agent.Step` is a behaviour for composable pipeline steps:

```elixir
defmodule MyApp.Steps.LoggingStep do
  @behaviour Pylon.AI.Agent.Step
  require Logger

  @impl true
  def call(ctx, _opts) do
    Logger.info("Step #{ctx.step_count} for #{ctx.name}")
    ctx
  end
end
```

Built-in steps:

| Step | Description |
|------|-------------|
| `BuildGoalPrompt` | Builds the system prompt with goal and XML response instructions |
| `InjectTools` | Injects available tools (formatted as XML) into the prompt |
| `CallLLM` | Calls the LLM via `LLMAdapter` and stores latency metadata |
| `ParseResponse` | Parses the LLM's XML response into structured data |
| `CheckCompletion` | Checks if the response contains a `<completion>` block |
| `HandleToolCall` | Executes requested tools and updates conversation history |
| `CheckStepCount` | Enforces `max_steps` limit to prevent infinite loops |
| `IncrementStep` | Prepares the context for the next iteration |

### Tools

`Pylon.AI.Tool` is a behaviour for agent tools:

```elixir
defmodule MyApp.Tools.Weather do
  @behaviour Pylon.AI.Tool

  @impl true
  def name(), do: "weather"

  @impl true
  def description(), do: "Gets current weather for a city"

  @impl true
  def run(%{"city" => city}) do
    {:ok, fetch_weather(city)}
  end

  @impl true
  def input_schema() do
    [
      city: [type: :string, required: true, doc: "City name"]
    ]
  end

  @impl true
  def output_schema() do
    [type: :map, required: true]
  end
end
```

Register tools before use:

```elixir
Pylon.AI.Toolset.register_tool(MyApp.Tools.Weather)

# Or register multiple at once:
Pylon.AI.Toolset.register_tools([
  Pylon.AI.Tools.Calculator,
  MyApp.Tools.Weather
])
```

Built-in tools:

- **calculator** — Performs `add`, `subtract`, `multiply`, `divide`
- **echo** — Echoes back a message (useful for debugging)

### Toolset

`Pylon.AI.Toolset` uses `:persistent_term` for O(1) tool lookups and automatically formats tools as XML for LLM system prompts.

```elixir
Pylon.AI.Toolset.get("calculator")
# => Pylon.AI.Tools.Calculator

Pylon.AI.Toolset.all_names()
# => ["calculator", "echo"]

Pylon.AI.Toolset.registered?("calculator")
# => true
```

### LLM Adapter

`Pylon.AI.LLMAdapter` provides a mockable interface for LLM interactions via `req_llm`. Configure a different implementation in tests:

```elixir
# config/test.exs
config :pylon, :llm_adapter, MyApp.MockLLM
```

The adapter expects a module implementing:

```elixir
@callback generate_text(String.t(), list()) :: {:ok, ReqLLM.Response.t()} | {:error, term()}
@callback user_message(String.t()) :: ReqLLM.Context.t()
@callback system_message(String.t()) :: ReqLLM.Context.t()
```

Default model: `google:gemini-2.5-flash`

## Customizing the Pipeline

You can replace or extend the default step pipeline per agent:

```elixir
{:ok, result} = Pylon.AI.Agent.run(
  name: "custom-agent",
  goal: "Analyze this data",
  tools: ["calculator"],
  steps: [
    Pylon.AI.Steps.BuildGoalPrompt,
    Pylon.AI.Steps.InjectTools,
    MyApp.Steps.CustomLogging,
    Pylon.AI.Steps.CallLLM,
    Pylon.AI.Steps.ParseResponse,
    Pylon.AI.Steps.CheckCompletion,
    Pylon.AI.Steps.HandleToolCall,
    Pylon.AI.Steps.CheckStepCount,
    Pylon.AI.Steps.IncrementStep
  ]
)
```

## Configuration

| Option | Description | Default |
|--------|-------------|---------|
| `:name` | Unique agent name (registered in Registry) | Required |
| `:goal` | The task description for the agent | Required |
| `:tools` | List of tool names the agent can use | Required |
| `:input` | Additional context / user input | `nil` |
| `:model` | LLM model identifier | `"google:gemini-2.5-flash"` |
| `:max_steps` | Maximum iterations before forced halt | `nil` (unlimited) |
| `:timeout` | Timeout for synchronous runs | `:infinity` |
| `:steps` | Custom pipeline steps | Default 8-step pipeline |
| `:on_complete` | `{pid, message}` for async completion | Required for `start/1` |

## Running Tests

```bash
mix test
```

## Requirements

- Elixir ~> 1.18
- `req_llm` ~> 1.10

## License

MIT
