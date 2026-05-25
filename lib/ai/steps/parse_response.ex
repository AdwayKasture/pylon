defmodule Pylon.AI.Steps.ParseResponse do
  @moduledoc """
  Step that parses XML from the LLM response.

  Extracts text from the LLM response and parses it as XML.
  Handles markdown code blocks containing XML.
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

        case parse_xml(text) do
          {:ok, parsed} ->
            Logger.info("ParseResponse: parsed = #{inspect(parsed)}")

            assistant_message = %{role: :assistant, content: text}
            %{ctx | parsed_response: parsed, history: ctx.history ++ [assistant_message]}

          {:error, reason} ->
            Context.put_result(ctx, {:error, "Failed to parse LLM response: #{reason}"})
        end
    end
  end

  defp parse_xml(text) when is_binary(text) do
    text
    |> String.trim_trailing("\n```")
    |> String.split("```xml\n")
    |> case do
      [_, expected_xml] -> expected_xml
      [maybe_xml] -> maybe_xml
    end
    |> String.trim()
    |> extract_xml_payload()
  end

  defp extract_xml_payload(xml) do
    cond do
      String.starts_with?(xml, "<tool_call>") ->
        parse_tool_call(xml)

      String.starts_with?(xml, "<completion>") ->
        parse_completion(xml)

      true ->
        {:error, "Unknown XML format"}
    end
  end

  defp parse_tool_call(xml) do
    with {:ok, name} <- extract_tag(xml, "name"),
         {:ok, args_content} <- extract_inner_xml(xml, "args") do
      args = parse_args_xml(args_content)
      {:ok, %{"tool" => name, "args" => args}}
    else
      :error -> {:error, "Invalid tool_call XML"}
    end
  end

  defp parse_completion(xml) do
    with {:ok, result} <- extract_tag(xml, "result"),
         {:ok, details} <- extract_tag(xml, "details", "") do
      {:ok, %{"completion" => %{"result" => result, "details" => details}}}
    else
      :error -> {:error, "Invalid completion XML"}
    end
  end

  defp extract_tag(xml, tag, default \\ nil) do
    pattern = "<#{tag}>(.*?)</#{tag}>"

    case Regex.run(~r/#{pattern}/s, xml) do
      [_, content] -> {:ok, String.trim(content)}
      nil -> if default != nil, do: {:ok, default}, else: :error
    end
  end

  defp extract_inner_xml(xml, tag) do
    pattern = "<#{tag}>(.*?)</#{tag}>"

    case Regex.run(~r/#{pattern}/s, xml) do
      [_, content] -> {:ok, content}
      nil -> :error
    end
  end

  defp parse_args_xml(content) do
    Regex.scan(~r/<(\w+)>([^<]+)<\/\1>/, content)
    |> Enum.map(fn [_, key, val] ->
      {key, maybe_convert_type(String.trim(val))}
    end)
    |> Enum.into(%{})
  end

  defp maybe_convert_type("true"), do: true
  defp maybe_convert_type("false"), do: false

  defp maybe_convert_type(val) do
    case Integer.parse(val) do
      {int, ""} ->
        int

      _ ->
        case Float.parse(val) do
          {float, ""} -> float
          _ -> val
        end
    end
  end
end
