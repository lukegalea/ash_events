# SPDX-FileCopyrightText: 2023 ash_events contributors <https://github.com/ash-project/ash_events/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshEvents.SensitiveAttributesTest do
  @moduledoc """
  On a non-encrypted event log, `sensitive?` attribute and argument values are
  not stored in clear: not in `data` (action input) and not in
  `changed_attributes` (attributes set by changes, defaults and hooks),
  unless the resource lists the attribute in `store_sensitive_attributes`.
  """
  use AshEvents.RepoCase, async: false

  alias AshEvents.Accounts
  alias AshEvents.Accounts.Credential
  alias AshEvents.Accounts.User
  alias AshEvents.EventLogs
  alias AshEvents.EventLogs.EventLog

  require Ash.Query

  @secret "correct-horse-battery-staple"
  @rotated_secret "tr0ub4dor-and-3"
  @api_key "ak_live_0123456789"

  defp digest(secret), do: :sha256 |> :crypto.hash(secret) |> Base.encode16(case: :lower)

  defp credential_events do
    EventLog
    |> Ash.Query.filter(resource == ^Credential)
    |> Ash.Query.sort(occurred_at: :asc)
    |> Ash.read!()
  end

  defp refute_stored(event, values) do
    stored =
      Jason.encode!(%{data: event.data, changed: event.changed_attributes, meta: event.metadata})

    for value <- values do
      refute stored =~ value, "event #{event.action} stored a sensitive value: #{inspect(value)}"
    end
  end

  test "a create stores neither sensitive input nor sensitive derived values" do
    credential =
      Accounts.create_credential!(%{label: "deploy", api_key: @api_key, secret: @secret},
        context: %{ash_events_metadata: %{source: "test"}}
      )

    assert credential.secret_digest == digest(@secret)

    [event] = credential_events()

    # sensitive argument and sensitive accepted attribute: key kept, value nil
    assert Map.fetch!(event.data, "secret") == nil
    assert Map.fetch!(event.data, "api_key") == nil
    # sensitive attribute set by a change: key kept, value nil
    assert Map.fetch!(event.changed_attributes, "secret_digest") == nil

    # non-sensitive input and derived values are still recorded
    assert event.data["label"] == "deploy"
    assert event.changed_attributes["secret_hint"] == "le"
    assert event.changed_attributes["id"] == credential.id
    assert event.metadata["source"] == "test"

    refute_stored(event, [@secret, @api_key, digest(@secret)])
  end

  test "an update stores neither sensitive input nor sensitive derived values" do
    credential = Accounts.create_credential!(%{label: "deploy", secret: @secret})
    Accounts.rotate_credential!(credential, %{label: "deploy-2", secret: @rotated_secret})

    [_create, rotate] = credential_events()

    assert rotate.action == :rotate
    assert Map.fetch!(rotate.data, "secret") == nil
    assert Map.fetch!(rotate.changed_attributes, "secret_digest") == nil
    assert rotate.data["label"] == "deploy-2"
    assert rotate.changed_attributes["secret_hint"] == "-3"

    refute_stored(rotate, [@rotated_secret, digest(@rotated_secret)])
  end

  test "replay rebuilds non-sensitive state; redacted values replay as nil" do
    credential =
      Accounts.create_credential!(%{label: "deploy", api_key: @api_key, secret: @secret})

    Accounts.rotate_credential!(credential, %{label: "deploy-2", secret: @rotated_secret})

    :ok = EventLogs.replay_events!()

    [replayed] = Ash.read!(Credential)

    assert replayed.id == credential.id
    assert replayed.label == "deploy-2"
    assert replayed.secret_hint == "-3"
    assert replayed.created_at == credential.created_at
    assert replayed.api_key == nil
    assert replayed.secret_digest == nil
  end

  describe "store_sensitive_attributes" do
    test "a listed attribute is stored; sensitive arguments still are not" do
      password = "listed-attribute-pw"

      user =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "listed@example.com",
          password: password,
          password_confirmation: password
        })
        |> Ash.create!(context: %{private: %{ash_authentication?: true}})

      [event] =
        EventLog
        |> Ash.Query.filter(resource == ^User and record_id == ^user.id)
        |> Ash.read!()

      # User lists :hashed_password, so the hash set by HashPasswordChange is kept
      assert event.changed_attributes["hashed_password"] == user.hashed_password
      # the plaintext arguments are not attributes, so the list never covers them
      assert Map.fetch!(event.data, "password") == nil
      assert Map.fetch!(event.data, "password_confirmation") == nil
      refute_stored(event, [password])
    end
  end
end
