defmodule Pylon.AI.Toolset do
  @moduledoc """
  Registry for AI agent tools using PersistentTerm for O(1) lookups.

  Tools are registered at compile-time or application startup and stored in
  PersistentTerm for efficient runtime access.

  ## Usage

  Register tools during application startup:

      Pylon.AI.Toolset.register_tools([
        Pylon.AI.Tools.Calculator,
        Pylon.AI.Tools.Web,
        MyApp.Tools.CustomTool
      ])

  Then retrieve tools by name:

      Pylon.AI.Toolset.get("calculator")
      # => Pylon.AI.Tools.Calculator

  """

  @persistent_term_key :pylon_tool_registry

  @doc """
  Registers multiple tools at once. Should be called during application startup.

  ## Examples

      Pylon.AI.Toolset.register_tools([
        Pylon.AI.Tools.Calculator,
        MyApp.Tools.CustomSearch
      ])
  """
  @spec register_tools(list(module())) :: :ok
  def register_tools(modules) when is_list(modules) do
    registry =
      modules
      |> Enum.map(fn mod ->
        # Defer validation - just try to call name/0
        # This allows registration during test setup before modules are fully loaded
        name =
          try do
            mod.name()
          rescue
            _ -> raise ArgumentError, "Module #{inspect(mod)} must implement name/0"
          end

        {name, mod}
      end)
      |> Enum.into(%{})

    :persistent_term.put(@persistent_term_key, registry)
    :ok
  end

  @doc """
  Registers a single tool. Can be called multiple times to add tools incrementally.

  ## Examples

      Pylon.AI.Toolset.register_tool(MyApp.Tools.CustomSearch)
  """
  @spec register_tool(module()) :: :ok
  def register_tool(module) do
    name =
      try do
        module.name()
      rescue
        _ -> raise ArgumentError, "Module #{inspect(module)} must implement name/0"
      end

    updated_registry = get_registry()
      |> Map.put(name,module)

    :persistent_term.put(@persistent_term_key, updated_registry)
    :ok
  end

  @doc """
  Returns the worker module for a given tool name.

  ## Examples

      Pylon.AI.Toolset.get("calculator")
      # => Pylon.AI.Tools.Calculator

      Pylon.AI.Toolset.get("unknown")
      # => nil
  """
  @spec get(String.t()) :: module() | nil
  def get(name) when is_binary(name) do
    registry = get_registry()
    Map.get(registry, name)
  end

  @doc """
  Returns all registered tool names.

  ## Examples

      Pylon.AI.Toolset.all_names()
      # => ["calculator", "web"]
  """
  @spec all_names() :: list(String.t())
  def all_names() do
    registry = get_registry()
    Map.keys(registry)
  end

  @doc """
  Returns all registered tool modules.

  ## Examples

      Pylon.AI.Toolset.all_tools()
      # => [Pylon.AI.Tools.Calculator, Pylon.AI.Tools.Web]
  """
  @spec all_tools() :: list(module())
  def all_tools() do
    registry = get_registry()
    Map.values(registry)
  end

  @doc """
  Checks if a tool with the given name is registered.

  ## Examples

      Pylon.AI.Toolset.registered?("calculator")
      # => true

      Pylon.AI.Toolset.registered?("unknown")
      # => false
  """
  @spec registered?(String.t()) :: boolean()
  def registered?(name) when is_binary(name) do
    registry = get_registry()
    Map.has_key?(registry, name)
  end

  @doc """
  Clears all registered tools. Useful for testing.
  """
  @spec clear() :: :ok
  def clear() do
    :persistent_term.put(@persistent_term_key, %{})
    :ok
  end

  @doc """
  Formats a tool module for inclusion in LLM system prompts (XML format).
  """
  @spec format_tool_xml(module()) :: String.t()
  def format_tool_xml(module) do
    schema = module.input_schema()

    description =
      if function_exported?(module, :description, 0) do
        module.description()
      else
        "No description available"
      end

    params_xml = schema_to_xml(schema)

    """
    <tool>
      <name>#{escape_xml(module.name())}</name>
      <description>#{escape_xml(description)}</description>
      <parameters>
    #{params_xml}
      </parameters>
    </tool>
    """
  end

  defp schema_to_xml(schema) when is_list(schema) do
    schema
    |> Enum.map(fn {key, opts} ->
      name = to_string(key)
      type = nimble_type_to_xml_type(opts[:type] || :string)
      required = if opts[:required], do: "true", else: "false"
      doc = opts[:doc] || ""

      "    <parameter name=\"#{escape_xml(name)}\" type=\"#{type}\" required=\"#{required}\">#{escape_xml(doc)}</parameter>"
    end)
    |> Enum.join("\n")
  end

  defp nimble_type_to_xml_type(:string), do: "string"
  defp nimble_type_to_xml_type(:integer), do: "integer"
  defp nimble_type_to_xml_type(:pos_integer), do: "integer"
  defp nimble_type_to_xml_type(:float), do: "number"
  defp nimble_type_to_xml_type(:number), do: "number"
  defp nimble_type_to_xml_type(:boolean), do: "boolean"
  defp nimble_type_to_xml_type({:list, _}), do: "array"
  defp nimble_type_to_xml_type(:map), do: "object"
  defp nimble_type_to_xml_type(:keyword_list), do: "object"
  defp nimble_type_to_xml_type(:atom), do: "string"
  defp nimble_type_to_xml_type({:in, _}), do: "string"
  defp nimble_type_to_xml_type(_), do: "string"

  defp escape_xml(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp escape_xml(_), do: ""

  # Private functions

  defp get_registry() do
    case :persistent_term.get(@persistent_term_key, nil) do
      nil ->
        # Initialize empty registry on first access
        :persistent_term.put(@persistent_term_key, %{})
        %{}

      registry ->
        registry
    end
  end
end
