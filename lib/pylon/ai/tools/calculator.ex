defmodule Pylon.AI.Tools.Calculator do
  @moduledoc """
  Tool for performing mathematical calculations.

  This module implements the Pylon.AI.Tool behaviour for synchronous execution.

  ## Registration

      Pylon.AI.Toolset.register_tool(Pylon.AI.Tools.Calculator)

  """
  @behaviour Pylon.AI.Tool

  require Logger

  @impl Pylon.AI.Tool
  def name(), do: "calculator"

  @impl Pylon.AI.Tool
  def description() do
    "Performs mathematical calculations. Supports basic arithmetic operations: add, subtract, multiply, divide."
  end

  @impl Pylon.AI.Tool
  def run(%{"op" => "add", "a" => a, "b" => b}) when is_number(a) and is_number(b) do
    {:ok, a + b}
  end

  def run(%{"op" => "subtract", "a" => a, "b" => b}) when is_number(a) and is_number(b) do
    {:ok, a - b}
  end

  def run(%{"op" => "multiply", "a" => a, "b" => b}) when is_number(a) and is_number(b) do
    {:ok, a * b}
  end

  def run(%{"op" => "divide", "a" => a, "b" => b}) when is_number(a) and is_number(b) do
    if b == 0 do
      {:error, "Division by zero"}
    else
      {:ok, a / b}
    end
  end

  def run(%{"op" => op}) when op not in ["add", "subtract", "multiply", "divide"] do
    {:error, "Unsupported operation: #{op}. Must be 'add', 'subtract', 'multiply', or 'divide'."}
  end

  def run(_) do
    {:error, "Invalid arguments. Requires 'op', 'a', and 'b' parameters."}
  end

  @impl Pylon.AI.Tool
  def input_schema() do
    [
      op: [
        type: :string,
        required: true,
        doc: "The operation to perform. One of: 'add', 'subtract', 'multiply', 'divide'."
      ],
      a: [
        type: :number,
        required: true,
        doc: "The first operand."
      ],
      b: [
        type: :number,
        required: true,
        doc: "The second operand."
      ]
    ]
  end

  @impl Pylon.AI.Tool
  def output_schema() do
    [type: :number, required: true]
  end
end
