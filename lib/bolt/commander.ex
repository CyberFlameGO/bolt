defmodule Bolt.Commander do
  @moduledoc """
  The brain of bolt. This checks whether a message is a valid command,
  and if so, applies predicates and then invokes the defined callback
  for the given command.

  Commands can be defined in `Bolt.Commander.Server` in a mapping of in the form
    command_name -> module | map
  If the command name is mapped to a module, the commander will invoke that command
  (which must implement the `Bolt.Command` behaviour directly.
  Otherwise, if the command name is mapped to a map, the commander will assume it
  is a command group and perform the same procedure as above, however, supporting
  an optional `:default` map key pointing to a module (implementing `Bolt.Command`)
  that will be invoked if no subcommand was found.
  """

  alias Nostrum.Api
  alias Nostrum.Struct.{Embed, Message}

  @prefix Application.fetch_env!(:bolt, :prefix)

  @spec find_failing_predicate(
          Message.t(),
          (Message.t() ->
             {:ok, Message.t()} | {:error, Embed.t()})
        ) :: nil | {:error, Embed.t()}
  def find_failing_predicate(msg, predicates) do
    predicates
    |> Enum.map(& &1.(msg))
    |> Enum.find(&match?({:error, _embed}, &1))
  end

  @spec row_to_command([{String.t(), Module.t() | Map.t() | {:alias, Module.t() | Map.t()}}]) ::
          nil | Module.t() | Map.t() | {:alias, Module.t() | Map.t()}
  defp row_to_command([]), do: nil
  defp row_to_command([{_name, command}]), do: command

  @spec maybe_load_alias(nil | {:alias, Module.t() | Map.t()}) :: nil | Module.t() | Map.t()
  defp maybe_load_alias({:alias, command}) do
    :ets.lookup(:commands, command)
    |> row_to_command()
  end

  defp maybe_load_alias(maybe_command), do: maybe_command

  @spec lookup_command(String.t()) :: nil | Map.t() | Module.t()
  def lookup_command(name) do
    :ets.lookup(:commands, name)
    |> row_to_command()
    |> maybe_load_alias()
  end

  @spec parse_args(Module.t(), [String.t()]) :: [String.t()] | any()
  defp parse_args(command_module, args) do
    if function_exported?(command_module, :parse_args, 1) do
      command_module.parse_args(args)
    else
      args
    end
  end

  @spec invoke(Module.t(), Message.t(), [String.t()]) :: any()
  defp invoke(command_module, msg, args) do
    case find_failing_predicate(msg, command_module.predicates()) do
      nil ->
        command_module.command(msg, parse_args(command_module, args))

      {:error, reason} ->
        # a predicate failed. show the response generated by it
        {:ok, _msg} = Api.create_message(msg.channel_id, reason)
    end
  end

  @spec handle_command(Map.t() | Module.t(), Message.t(), [String.t()]) ::
          :ignored | {:ok, Message.t()} | any()
  defp handle_command(command_map, msg, original_args) when is_map(command_map) do
    maybe_subcommand = List.first(original_args)

    case Map.fetch(command_map, maybe_subcommand) do
      {:ok, subcommand_module} ->
        # If we have at least one subcommand, that means `original_args`
        # needs to at least contain one element, so `args` is either empty
        # or the rest of the arguments excluding the subcommand name.
        [_subcommand | args] = original_args
        invoke(subcommand_module, msg, args)

      :error ->
        # Does the command group have a default command to invoke?
        if Map.has_key?(command_map, :default) do
          # If yes, invoke it with all arguments.
          invoke(command_map.default, msg, original_args)
        else
          # Otherwise, respond with all known subcommands in the command group.
          subcommand_string =
            command_map |> Map.keys() |> Stream.map(&"`#{&1}`") |> Enum.join(", ")

          response = "🚫 unknown subcommand, known subcommands: #{subcommand_string}"
          {:ok, _msg} = Api.create_message(msg.channel_id, response)
        end
    end
  end

  defp handle_command(command_module, msg, args) do
    invoke(command_module, msg, args)
  end

  @spec try_split(String.t()) :: [String.t()]
  def try_split(content) do
    OptionParser.split(content)
  rescue
    _ in RuntimeError -> String.split(content)
  end

  @doc """
  Handle a message sent over the gateway.
  If the message starts with the prefix and
  contains a valid command, the arguments
  are parsed accordingly and passed to
  the command along with the message.
  Otherwise, the message is ignored.
  """
  @spec handle_message(Message.t()) :: :ignored | {:ok, Message.t()} | any()
  def handle_message(msg) do
    with [@prefix <> command_name | args] <- try_split(msg.content),
         cmd_module_or_map when cmd_module_or_map != nil <- lookup_command(command_name) do
      handle_command(cmd_module_or_map, msg, args)
    else
      _err -> :ignored
    end
  end
end
