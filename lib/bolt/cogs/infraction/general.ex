defmodule Bolt.Cogs.Infraction.General do
  alias Nostrum.Api
  alias Nostrum.Cache.UserCache
  alias Nostrum.Struct.User

  @type_emojis %{
    "note" => "📔",
    "tempmute" => "🔇⏲",
    "mute" => "🔇",
    "unmute" => "📢",
    "temprole" => "🎽⏲",
    "warning" => "⚠",
    "kick" => "👢",
    "softban" => "🔨☁",
    "tempban" => "🔨⏲",
    "ban" => "🔨",
    "unban" => "🤝"
  }

  @spec emoji_for_type(String.t()) :: String.t()
  def emoji_for_type(type) do
    Map.get(@type_emojis, type, "?")
  end

  @spec format_user(pos_integer()) :: {:ok, User.t()} | {:error, String.t()}
  def format_user(user_id) do
    case UserCache.get(user_id) do
      {:ok, user} ->
        "#{User.full_name(user)} (`#{user.id}`)"

      {:error, _reason} ->
        case Api.get_user(user_id) do
          {:ok, user} -> "#{User.full_name(user)} (`#{user.id}`)"
          {:error, _reason} -> "unknown user (`#{user_id}`)"
        end
    end
  end
end
