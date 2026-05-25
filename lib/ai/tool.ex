defmodule Pylon.AI.Tool do
  @moduledoc """
  A behaviour for tools that can be used by AI agents.

  All tools in Pylon must implement this behaviour.
  Tools execute synchronously within the agent process.

  ## Example

      defmodule Pylon.AI.Tools.Calculator do
        @behaviour Pylon.AI.Tool

        @impl Pylon.AI.Tool
        def name(), do: "calculator"

        @impl Pylon.AI.Tool
        def description() do
          "Performs basic arithmetic operations"
        end

        @impl Pylon.AI.Tool
        def run(%{"op" => "add", "a" => a, "b" => b}) do
          {:ok, a + b}
        end

        @impl Pylon.AI.Tool
        def input_schema() do
          [
            op: [type: :string, required: true],
            a: [type: :number, required: true],
            b: [type: :number, required: true]
          ]
        end

        @impl Pylon.AI.Tool
        def output_schema() do
          [type: :number, required: true]
        end
      end

  """

  @doc """
  Returns the unique name of the tool as a string.
  This is used to identify the tool in agent interactions.
  """
  @callback name() :: String.t()

  @doc """
  Returns a description of what the tool does.
  This helps the AI understand when and how to use the tool.
  """
  @callback description() :: String.t()

  @doc """
  Execute the tool with the given arguments.
  Returns {:ok, result} on success or {:error, reason} on failure.

  This function is called synchronously by the agent.
  """
  @callback run(map()) :: {:ok, any()} | {:error, any()}

  @doc """
  Returns the input schema for the tool as a keyword list.
  Defines what parameters the tool expects.
  """
  @callback input_schema() :: keyword()

  @doc """
  Returns the output schema for the tool as a keyword list.
  Defines what the tool returns.
  """
  @callback output_schema() :: keyword()

  @optional_callbacks [
    description: 0
  ]
end
