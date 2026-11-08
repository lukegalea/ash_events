# SPDX-FileCopyrightText: 2023 ash_events contributors <https://github.com/ash-project/ash_events/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshEvents.DataLayerRefusalTest do
  @moduledoc """
  A write the database refuses, through the event-tracking action wrappers.

  AshPostgres answers an `ash_error:` exception raised in the database (a
  trigger, or an atomic `error/2` expression) with
  `{:error, :no_rollback, error}`. The wrappers are manual actions, and Ash
  validates a manual action's return, so passing that three-tuple through
  made `Ash.update/2` and `Ash.destroy/2` raise `Ash.Error.Framework`, and a
  hard destroy discarded the data layer's result and reported success.

  `AshEvents.Accounts.GuardedNote`'s table refuses the operation named in the
  `ash_events_test.refuse` setting. The setting is made inside the test's
  sandbox transaction, so it ends with the test.
  """
  use AshEvents.RepoCase, async: false

  alias AshEvents.Accounts
  alias AshEvents.Accounts.GuardedNote
  alias AshEvents.EventLogs
  alias AshEvents.EventLogs.EventLog
  alias AshEvents.EventLogs.SystemActor

  require Ash.Query

  @actor %SystemActor{name: "test_runner"}

  defp refuse(operation) do
    TestRepo.query!("SELECT set_config('ash_events_test.refuse', $1, false)", [operation])
  end

  defp events_for(note) do
    EventLog
    |> Ash.Query.filter(resource == ^GuardedNote and record_id == ^note.id)
    |> Ash.Query.sort(occurred_at: :asc)
    |> Ash.read!()
    |> Enum.map(& &1.action)
  end

  defp reload(note) do
    GuardedNote
    |> Ash.Query.filter(id == ^note.id)
    |> Ash.read_one!()
  end

  defp assert_refused(result) do
    assert {:error, %Ash.Error.Invalid{errors: errors}} = result

    assert Enum.any?(errors, fn
             %Ash.Error.Changes.InvalidChanges{message: message} ->
               message =~ "refused by the database"

             _ ->
               false
           end)
  end

  setup do
    %{note: Accounts.create_guarded_note!(%{body: "first"}, actor: @actor)}
  end

  test "a refused update returns an error and leaves no event", %{note: note} do
    refuse("UPDATE")

    assert_refused(Accounts.update_guarded_note(note, %{body: "second"}, actor: @actor))

    assert reload(note).body == "first"
    assert events_for(note) == [:create]
  end

  test "a refused soft destroy returns an error and leaves no event", %{note: note} do
    refuse("UPDATE")

    assert_refused(Accounts.soft_destroy_guarded_note(note, actor: @actor))

    assert reload(note).deleted_at == nil
    assert events_for(note) == [:create]
  end

  test "a refused hard destroy returns an error and leaves no event", %{note: note} do
    refuse("DELETE")

    assert_refused(Accounts.destroy_guarded_note(note, actor: @actor))

    assert reload(note).body == "first"
    assert events_for(note) == [:create]
  end

  test "the same writes succeed when the database allows them", %{note: note} do
    note = Accounts.update_guarded_note!(note, %{body: "second"}, actor: @actor)
    Accounts.destroy_guarded_note!(note, actor: @actor)

    assert reload(note) == nil
    assert events_for(note) == [:create, :update, :destroy]
  end

  describe "replay" do
    test "a replayed update the database refuses raises the typed error", %{note: note} do
      Accounts.update_guarded_note!(note, %{body: "second"}, actor: @actor)
      refuse("UPDATE")

      error = assert_raise Ash.Error.Invalid, fn -> EventLogs.replay_events!() end
      assert Exception.message(error) =~ "refused by the database"
    end

    test "a replayed hard destroy the database refuses raises the typed error", %{note: note} do
      Accounts.destroy_guarded_note!(note, actor: @actor)
      refuse("DELETE")

      error = assert_raise Ash.Error.Invalid, fn -> EventLogs.replay_events!() end
      assert Exception.message(error) =~ "refused by the database"
    end
  end
end
