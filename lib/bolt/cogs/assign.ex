defmodule Bolt.Cogs.Assign do
  @moduledoc false

  alias Bolt.{Converters, Helpers, ModLog, Repo}
  alias Bolt.Schema.SelfAssignableRoles
  alias Nostrum.Api
  alias Nostrum.Struct.User

  @spec command(Nostrum.Struct.Message.t(), String.t()) :: {:ok, Nostrum.Struct.Message.t()}
  def command(msg, "") do
    response = "🚫 expected the role name to assign, got nothing"
    {:ok, _msg} = Api.create_message(msg.channel_id, response)
  end

  def command(msg, role_name) do
    response =
      with roles_row when roles_row != nil <- Repo.get(SelfAssignableRoles, msg.guild_id),
           {:ok, role} <- Converters.to_role(msg.guild_id, role_name, true),
           true <- role.id in roles_row.roles,
           {:ok} <- Api.add_guild_member_role(msg.guild_id, msg.author.id, role.id) do
        ModLog.emit(
          msg.guild_id,
          "AUTOMOD",
          "gave #{User.full_name(msg.author)} (`#{msg.author.id}`)" <>
            " the self-assignable role `#{role.name}`"
        )

        "👌 gave you the `#{Helpers.clean_content(role.name)}` role"
      else
        nil ->
          "🚫 this guild has no self-assignable roles configured"

        false ->
          "🚫 that role is not self-assignable"

        {:error, %{status_code: status, message: %{"message" => reason}}} ->
          "🚫 API error: #{reason} (status code #{status})"

        {:error, reason} ->
          "🚫 #{Helpers.clean_content(reason)}"
      end

    {:ok, _msg} = Api.create_message(msg.channel_id, response)
  end
end
