defmodule Bolt.Cogs.ModLog.Unmute do
  @moduledoc false

  alias Bolt.ModLog
  alias Bolt.ModLog.Silencer
  alias Nostrum.Api

  def command(msg, []) do
    response =
      if Silencer.is_silenced?(msg.guild_id) do
        :ok = Silencer.remove(msg.guild_id)
        "👌 mod log is no longer silenced"
      else
        "🚫 the mod log is not silenced"
      end

    {:ok, _msg} = Api.create_message(msg.channel_id, response)
  end

  def command(msg, _args) do
    response = "🚫 this subcommand accepts no arguments"
    {:ok, _msg} = Api.create_message(msg.channel_id, response)
  end
end
