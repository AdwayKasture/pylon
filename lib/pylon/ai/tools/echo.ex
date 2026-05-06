defmodule Pylon.AI.Tools.Echo do
  @moduledoc """
  Tool for echoing messages or values back.

  This module implements the Pylon.AI.Tool behaviour for synchronous execution.

  ## Registration

      Pylon.AI.Toolset.register_tool(Pylon.AI.Tools.Echo)

  """
  @behaviour Pylon.AI.Tool

  require Logger

  @impl Pylon.AI.Tool
  def name(), do: "echo"

  @impl Pylon.AI.Tool
  def description() do
    "Echoes back the provided message or value. Useful for displaying results or debugging."
  end

  @impl Pylon.AI.Tool
  def run(%{"message" => message}) do
    {:ok, message}
  end

  def run(_) do
    {:error, "Invalid arguments. Requires 'message' parameter."}
  end

  @impl Pylon.AI.Tool
  def input_schema() do
    [
      message: [
        type: :string,
        required: true,
        doc: "The message or value to echo back."
      ]
    ]
  end

  @impl Pylon.AI.Tool
  def output_schema() do
    [type: :string, required: true]
  end
end
