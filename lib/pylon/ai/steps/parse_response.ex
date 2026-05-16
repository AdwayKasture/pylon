defmodule Pylon.AI.Steps.ParseResponse do
  @moduledoc """
  Step that parses JSON from the LLM response.

  Extracts text from the LLM response and parses it as JSON.
  Handles markdown code blocks containing JSON.
  Stores the parsed result in context.parsed_response.

  """

  @behaviour Pylon.AI.Agent.Step

  alias Pylon.AI.Agent.Context
  require Logger

  @impl true
  def call(ctx, _opts) do
    case ctx.llm_response do
      nil ->
        Context.put_result(ctx, {:error, "No LLM response to parse"})

      response ->
        text = ReqLLM.Response.text(response)
        Logger.info("ParseResponse: text = #{inspect(text)}")

        case parse_json(text) do
          {:ok, parsed} ->
            Logger.info("ParseResponse: parsed = #{inspect(parsed)}")
            # Add assistant's response to history so it can see its own tool requests
            assistant_message = %{role: :assistant, content: text}
            %{ctx | parsed_response: parsed, history: ctx.history ++ [assistant_message]}

          {:error, reason} ->
            Context.put_result(ctx, {:error, "Failed to parse LLM response: #{reason}"})
        end
    end
  end

  defp parse_json(text) when is_binary(text) do
    text
    |> String.trim_trailing("\n```")
    |> String.split("```json\n")
    |> case do
      [_, expected_json] -> expected_json
      [maybe_json] -> maybe_json
    end
    |> JSON.decode()
  end
end
