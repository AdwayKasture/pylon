# Pipeline & Step Architecture

## High-Level Overview

### `Pylon.AI.Agent.Step` (Behaviour)

Defines a single transform:

```
call(context, opts) -> context
```

Steps read from and write to a `Context` struct. They can halt the pipeline by setting `ctx.halted = true` (typically via `Context.put_result/2` or `Context.halt/1`).

### `Pylon.AI.Agent.Pipeline`

A thin `Enum.reduce_while` wrapper that runs steps sequentially, skipping remaining steps once `ctx.halted` becomes `true`.

```elixir
Pipeline.run(context, steps)
```

Steps can be bare modules or `{module, opts}` tuples.

---

## Known Issues

### 1. `CheckStepCount` Runs Too Late

**Current default step order:**

```
BuildGoalPrompt → InjectTools → CallLLM → ParseResponse → CheckCompletion → HandleToolCall → CheckStepCount → IncrementStep
```

`CheckStepCount` is the **second-to-last** step. On the iteration that exceeds `max_steps`, the agent still:

- Calls the LLM (wastes API tokens).
- Parses the response.
- Potentially executes a tool call.
- **Then** checks the limit and halts.

**Proposed fix:** Move `CheckStepCount` to the **first** position in the pipeline, or validate the count in the GenServer before starting the pipeline.

---

### 2. `IncrementStep` Is a No-Op

```elixir
defmodule Pylon.AI.Steps.IncrementStep do
  @behaviour Pylon.AI.Agent.Step

  @impl true
  def call(ctx, _opts) do
    ctx  # literally does nothing
  end
end
```

The step count is actually incremented by the **GenServer** after the pipeline finishes:

```elixir
step: result_context.step_count + 1
```

`Context.next_iteration/1` (which clears iteration-specific fields and increments the counter) is **never called** by the agent loop. The GenServer manually does a subset of that work instead.

**Proposed fix:** Either make `IncrementStep` call `Context.next_iteration/1` and have the GenServer trust the context, or remove the step entirely and handle it all in the GenServer.

---

### 3. Off-by-One `max_steps` Semantics with Wasted Work

`CheckStepCount` checks `ctx.step_count >= max_steps`. Since `step_count` starts at `0`:

- `max_steps = 3` allows iterations `0`, `1`, `2` (3 iterations of work).
- On iteration `3` (`step_count = 3`), `3 >= 3` is `true` → halt.
- **But the LLM was already called on iteration 3 before the check ran.**

So you get **4 LLM calls** for `max_steps = 3`.

**Clarification needed:** Should `max_steps` be interpreted as:

- "Max iterations including this one" (so `max_steps = 3` means iterations `0` → `2`, 3 total)?
- Or a 1-based count (so `max_steps = 3` means stop after the 3rd iteration)?

---

### 4. History Duplication Every Iteration

Each iteration rebuilds `messages` from scratch:

```elixir
[system_prompt, tools_prompt]
```

And concatenates the full `history`. This means the system prompt and tool descriptions are sent on **every single LLM call**. For long conversations this gets expensive in tokens and latency.

**Proposed fix:** Cache the system/tool messages and only append new turns to `history`.

---

## Proposed Default Pipeline

Reorganize so the safety gate runs first, and make `IncrementStep` actually do its job:

```elixir
@default_steps [
  # 1. Safety gate first
  Pylon.AI.Steps.CheckStepCount,
  # 2. Build the prompt
  Pylon.AI.Steps.BuildGoalPrompt,
  Pylon.AI.Steps.InjectTools,
  # 3. Talk to the LLM
  Pylon.AI.Steps.CallLLM,
  Pylon.AI.Steps.ParseResponse,
  # 4. Handle outcome
  Pylon.AI.Steps.CheckCompletion,
  Pylon.AI.Steps.HandleToolCall,
  # 5. Prepare for next iteration
  Pylon.AI.Steps.IncrementStep
]
```

---

## Step Reference

| Step | Responsibility |
|------|----------------|
| `BuildGoalPrompt` | Builds the system prompt with the agent's goal and XML response instructions. |
| `InjectTools` | Injects available tools (formatted as XML) into the system prompt. |
| `CallLLM` | Calls the LLM via `LLMAdapter` and stores latency/token metadata. |
| `ParseResponse` | Parses the LLM's XML response into structured data (`tool_call` or `completion`). |
| `CheckCompletion` | Checks if the response contains a `<completion>` block; if so, halts with success. |
| `HandleToolCall` | Executes requested tools and updates conversation history with results. |
| `CheckStepCount` | Enforces `max_steps` limit to prevent infinite loops. |
| `IncrementStep` | *(Currently a no-op)* Should prepare the context for the next iteration. |
