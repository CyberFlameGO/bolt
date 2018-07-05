defmodule Bolt.Cogs.Tempban do
  @moduledoc false

  @behaviour Bolt.Command

  alias Bolt.Commander.Checks
  alias Bolt.Events.Handler
  alias Bolt.{Helpers, ModLog, Parsers, Repo}
  alias Bolt.Schema.Infraction
  alias Nostrum.Api
  alias Nostrum.Struct.User
  import Ecto.Query, only: [from: 2]

  @impl true
  def usage, do: ["tempban <user:snowflake|member> <duration:duration> [reason:str...]"]

  @impl true
  def description,
    do: """
    Temporarily ban the given user for the given duration with an optional reason.
    An infraction is stored in the infraction database, and can be retrieved later.
    Requires the `BAN_MEMBERS` permission.

    **Examples**:
    ```rs
    // tempban Dude for 2 days without a reason
    tempban @Dude#0001 2d

    // the same thing, but with a specified reason
    tempban @Dude#0001 2d posting cats instead of ducks
    ```
    """

  @impl true
  def predicates,
    do: [&Checks.guild_only/1, &Checks.can_ban_members?/1]

  @impl true
  def command(msg, [user, duration | reason_list]) do
    response =
      with reason <- Enum.join(reason_list, " "),
           {:ok, user_id, converted_user} <- Helpers.into_id(msg.guild_id, user),
           {:ok, expiry} <- Parsers.human_future_date(duration),
           query <-
             from(
               infr in Infraction,
               where:
                 infr.active and infr.user_id == ^user_id and infr.guild_id == ^msg.guild_id and
                   infr.type == "tempban",
               limit: 1,
               select: {infr.id, infr.expires_at}
             ),
           [] <- Repo.all(query),
           {:ok} <- Api.create_guild_ban(msg.guild_id, user_id, 7),
           infraction_map <- %{
             type: "tempban",
             guild_id: msg.guild_id,
             user_id: user_id,
             actor_id: msg.author.id,
             reason: if(reason != "", do: reason, else: nil),
             expires_at: expiry
           },
           {:ok, _created_infraction} <- Handler.create(infraction_map) do
        user_string =
          if converted_user == nil do
            "`#{user_id}`"
          else
            "#{User.full_name(converted_user)} (`#{user_id}`)"
          end

        ModLog.emit(
          msg.guild_id,
          "INFRACTION_CREATE",
          "#{User.full_name(msg.author)} (`#{msg.author.id}`) temporarily banned" <>
            " #{user_string} until #{Helpers.datetime_to_human(expiry)}" <>
            if(reason != "", do: " with reason `#{Helpers.clean_content(reason)}`", else: "")
        )

        response =
          "👌 temporarily banned #{user_string} until #{Helpers.datetime_to_human(expiry)}"

        if reason != "" do
          response <> " with reason `#{Helpers.clean_content(reason)}`"
        else
          response
        end
      else
        {:error, %{status_code: status, message: %{"message" => reason}}} ->
          "❌ API error: #{reason} (status code `#{status}`)"

        {:error, reason} ->
          "❌ error: #{reason}"

        [{existing_id, existing_expiry}] ->
          "❌ there already is a tempban for that member under ID" <>
            " ##{existing_id} which will expire on " <> Helpers.datetime_to_human(existing_expiry)
      end

    {:ok, _msg} = Api.create_message(msg.channel_id, response)
  end

  def command(msg, _args) do
    response = "ℹ️ usage: `tempban <user:snowflake|member> <duration:duration> [reason:str...]`"
    {:ok, _msg} = Api.create_message(msg.channel_id, response)
  end
end
