# Pylon

A Phoenix-based platform for building AI agents with a modular, composable architecture.

## Overview

Pylon provides a robust framework for creating AI agents that can use tools to accomplish tasks. It implements a synchronous ReAct pattern with a composable pipeline architecture, allowing you to build agents that can reason, act, and iterate toward completing goals.

## Features

- **Modular Agent Architecture**: Composable pipeline steps for building custom agent behaviors
- **Tool System**: Easy-to-implement tool behavior for extending agent capabilities
- **Multiple Execution Modes**: Support for both async (cast) and synchronous (call) agent execution
- **LLM Integration**: Built on top of `req_llm` for flexible LLM provider support
- **Live Dashboard**: Phoenix LiveDashboard for monitoring and debugging
- **Production Ready**: Built on Phoenix 1.8 with proper supervision and error handling

## Architecture

### AI Agent System

The core of Pylon is the AI Agent system, which implements a ReAct pattern:

```
┌─────────────────────────────────────────────────────────────┐
│                       Pylon.AI.Agent                        │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Pipeline Steps (Composable & Customizable)         │   │
│  │                                                     │   │
│  │  1. BuildSystemPrompt  → Format system message      │   │
│  │  2. CallLLM           → Send request to LLM         │   │
│  │  3. ParseResponse     → Parse LLM response          │   │
│  │  4. CheckCompletion   → Check if goal achieved      │   │
│  │  5. HandleToolCall    → Execute tool if requested   │   │
│  │  6. CheckStepCount    → Check max steps limit       │   │
│  │  7. IncrementStep     → Advance iteration counter   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              ↓
                    ┌──────────────────┐
                    │   Pylon.AI.Tool  │
                    │   Behaviour      │
                    └──────────────────┘
```

### Key Components

- **`Pylon.AI.Agent`**: GenServer-based agent that executes a goal using available tools
- **`Pylon.AI.Agent.Context`**: Manages agent state and execution context
- **`Pylon.AI.Agent.Pipeline`**: Orchestrates the execution of pipeline steps
- **`Pylon.AI.Agent.Step`**: Behavior for defining custom pipeline steps
- **`Pylon.AI.Tool`**: Behavior for creating tools that agents can use
- **`Pylon.AI.Toolset`**: Registry for tools with O(1) lookups via PersistentTerm

## Getting Started

### Prerequisites

- Elixir 1.15+
- PostgreSQL 14+
- Node.js (for asset building)

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd pylon
```

2. Install dependencies and setup the database:
```bash
mix setup
```

3. Start the Phoenix server:
```bash
mix phx.server
```

Or inside IEx:
```bash
iex -S mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000) from your browser.

## Usage

### Running an Agent (Blocking Mode)

The simplest way to run an agent is synchronously:

```elixir
{:ok, result} = Pylon.AI.Agent.run(
  name: "calculator-agent",
  goal: "Calculate (5 + 3) * 2",
  tools: ["calculator"],
  timeout: 30_000
)
```

### Running an Agent (Async Mode)

For non-blocking execution with a callback:

```elixir
{:ok, _pid} = Pylon.AI.Agent.start(
  name: "calculator-agent",
  goal: "Calculate (5 + 3) * 2",
  tools: ["calculator"],
  on_complete: {self(), :agent_done}
)

# Receive result:
receive do
  {:agent_done, "calculator-agent", result} -> 
    IO.inspect(result)
end
```

### Custom Pipeline Steps

You can customize the agent's behavior by providing custom steps:

```elixir
{:ok, result} = Pylon.AI.Agent.run(
  name: "custom-agent",
  goal: "Calculate (5 + 3) * 2",
  tools: ["calculator"],
  steps: [
    Pylon.AI.Steps.BuildSystemPrompt,
    MyApp.Steps.CustomLogging,  # Your custom step
    Pylon.AI.Steps.CallLLM,
    Pylon.AI.Steps.ParseResponse,
    Pylon.AI.Steps.CheckCompletion,
    Pylon.AI.Steps.HandleToolCall,
    Pylon.AI.Steps.CheckStepCount,
    Pylon.AI.Steps.IncrementStep
  ]
)
```

### Creating Custom Tools

Implement the `Pylon.AI.Tool` behavior to create new tools:

```elixir
defmodule MyApp.Tools.Weather do
  @behaviour Pylon.AI.Tool

  @impl Pylon.AI.Tool
  def name(), do: "weather"

  @impl Pylon.AI.Tool
  def description() do
    "Gets current weather information for a location"
  end

  @impl Pylon.AI.Tool
  def run(%{"location" => location}) do
    # Your weather API call here
    {:ok, %{temperature: 72, condition: "sunny"}}
  end

  @impl Pylon.AI.Tool
  def input_schema() do
    [
      location: [type: :string, required: true]
    ]
  end

  @impl Pylon.AI.Tool
  def output_schema() do
    [type: :map, required: true]
  end
end
```

### Registering Tools

Register your tools during application startup:

```elixir
# In lib/my_app/application.ex
def start(_type, _args) do
  # Register tools before starting supervisors
  Pylon.AI.Toolset.register_tools([
    Pylon.AI.Tools.Calculator,
    MyApp.Tools.Weather
  ])

  children = [
    # ... other children
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

## Default Tools

Pylon comes with a few built-in tools:

- **`calculator`**: Basic arithmetic operations (add, subtract, multiply, divide)
- **`echo`**: Simple echo tool for testing

## Configuration

### LLM Provider

Configure your LLM provider in `config/runtime.exs`:

```elixir
config :pylon, :llm,
  provider: :google,
  api_key: System.get_env("GOOGLE_API_KEY"),
  default_model: "google:gemini-2.5-flash"
```

### Environment Variables

```bash
# Required
export GOOGLE_API_KEY=your_api_key_here

# Optional
export DATABASE_URL=postgres://user:pass@localhost/pylon_dev
export SECRET_KEY_BASE=your_secret_key
```

## Testing

Run the test suite:

```bash
mix test
```

Run with coverage:

```bash
mix test --cover
```

## Development

### Code Quality

The project includes a pre-commit hook that runs:
- Compilation with warnings as errors
- Unused dependency check
- Code formatting
- Test suite

Run manually:

```bash
mix precommit
```

### Live Reload

Changes to Elixir files trigger automatic recompilation during development.

## Deployment

For production deployment, please refer to the [Phoenix deployment guides](https://hexdocs.pm/phoenix/deployment.html).

Key considerations:
- Set proper `SECRET_KEY_BASE` and `DATABASE_URL` environment variables
- Run migrations: `mix ecto.migrate`
- Build production assets: `mix assets.deploy`

## Project Structure

```
lib/
├── pylon/
│   ├── ai/
│   │   ├── agent.ex              # Main agent GenServer
│   │   ├── agent/
│   │   │   ├── context.ex        # Agent state/context
│   │   │   ├── pipeline.ex       # Step orchestration
│   │   │   └── step.ex           # Step behavior
│   │   ├── agent_supervisor.ex   # Dynamic supervisor
│   │   ├── llm_adapter.ex        # LLM integration
│   │   ├── steps/                # Built-in pipeline steps
│   │   ├── tool.ex               # Tool behavior
│   │   ├── toolset.ex            # Tool registry
│   │   └── tools/                # Built-in tools
│   ├── application.ex
│   ├── mailer.ex
│   └── repo.ex
└── pylon_web/
    ├── components/
    ├── controllers/
    └── live/                     # LiveView modules (if any)
```

## Learn More

- **Phoenix Framework**: https://www.phoenixframework.org/
- **Phoenix Guides**: https://hexdocs.pm/phoenix/overview.html
- **Elixir Forum**: https://elixirforum.com/c/phoenix-forum
- **ReAct Pattern**: Reasoning + Acting pattern for LLM agents

## License

This project is licensed under the MIT License.
