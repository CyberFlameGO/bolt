defmodule Bolt.Consumer.GuildCreate do
  @moduledoc "Handles the `GUILD_CREATE` event."

  alias Bolt.BotLog
  alias Nostrum.Struct.{Guild, Message}

  @spec handle(Guild.t()) :: {:ok, Message.t()} | :noop
  def handle(guild) do
    BotLog.emit(
      "📥 joined guild `#{guild.name}` (`#{guild.id}`), seeing #{guild.member_count} members"
    )
  end
end
