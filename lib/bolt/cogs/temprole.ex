defmodule Bolt.Cogs.Temprole do
  alias Bolt.Converters
  alias Bolt.Helpers
  alias Bolt.Parsers
  alias Bolt.Repo
  alias Bolt.Events.Handler
  alias Bolt.Schema.Infraction
  alias Nostrum.Api
  alias Nostrum.Struct.User

  def command(msg, [user, role, duration | reason_list]) do
    response =
      with reason <- Enum.join(reason_list, " "),
           {:ok, member} <- Converters.to_member(msg.guild_id, user),
           {:ok, role} <- Converters.to_role(msg.guild_id, role),
           {:ok, expiry} <- Parsers.human_future_date(duration),
           {:ok} <-
             Api.modify_guild_member(
               msg.guild_id,
               member.user.id,
               roles: Enum.uniq(member.roles ++ [role.id])
             ),
           infraction <- %{
             type: "temprole",
             guild_id: msg.guild_id,
             user_id: member.user.id,
             actor_id: msg.author.id,
             reason: if(reason != "", do: reason, else: nil),
             expires_at: expiry,
             data: %{
               "role_id" => role.id
             }
           },
           changeset <- Infraction.changeset(%Infraction{}, infraction),
           {:ok, _created_infraction} <- Repo.insert(changeset),
           {:ok, _event} <-
             Handler.create(%{
               timestamp: expiry,
               event: "REMOVE_ROLE",
               data: %{
                 "guild_id" => msg.guild_id,
                 "user_id" => member.user.id,
                 "role_id" => role.id
               }
             }) do
               "👌 temporary role #{role.name} applied to "
                          <> "#{User.full_name(member.user)} until #{Helpers.datetime_to_human(expiry)}"
      else
        {:error, %{message: %{"message" => reason}, status_code: status}} ->
          "❌ API error: #{reason} (status code `#{status}`)"

        {:error, %{message: :timeout}} ->
          "❌ API request timed out, please retry"

        {:error, reason} ->
          "❌ error: #{Helpers.clean_content(reason)}"
      end

    {:ok, _msg} = Api.create_message(msg.channel_id, response)
  end

  def command(msg, _incorrect_args) do
    response = "🚫 failed to parse arguments, check `help temprole` for details"
    {:ok, _msg} = Api.create_message(msg.channel_id, response)
  end
end
