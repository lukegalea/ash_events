# SPDX-FileCopyrightText: 2023 ash_events contributors <https://github.com/ash-project/ash_events/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshEvents.Accounts.GuardedNote do
  @moduledoc """
  Test resource whose table refuses writes in the database.

  A row trigger raises an `ash_error:` exception (the shape `ash_raise_error/1`
  raises) for the operation named in the `ash_events_test.refuse` setting:
  `UPDATE` or `DELETE`. AshPostgres answers that with
  `{:error, :no_rollback, error}`, which the action wrappers must turn into a
  plain `{:error, error}`.
  """
  use Ash.Resource,
    domain: AshEvents.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshEvents.Events]

  postgres do
    table "guarded_notes"
    repo AshEvents.TestRepo

    custom_statements do
      statement :guarded_notes_refuse_function do
        up """
        CREATE OR REPLACE FUNCTION guarded_notes_refuse() RETURNS trigger AS $$
        BEGIN
          IF current_setting('ash_events_test.refuse', true) = TG_OP THEN
            RAISE EXCEPTION 'ash_error: %', json_build_object(
              'exception', 'Elixir.Ash.Error.Changes.InvalidChanges',
              'input', json_build_object('message', 'refused by the database')
            )::text;
          END IF;

          IF TG_OP = 'DELETE' THEN
            RETURN OLD;
          END IF;

          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        """

        down "DROP FUNCTION IF EXISTS guarded_notes_refuse()"
      end

      statement :guarded_notes_refuse_trigger do
        up """
        CREATE TRIGGER guarded_notes_refuse
          BEFORE UPDATE OR DELETE ON guarded_notes
          FOR EACH ROW EXECUTE FUNCTION guarded_notes_refuse()
        """

        down "DROP TRIGGER IF EXISTS guarded_notes_refuse ON guarded_notes"
      end
    end
  end

  events do
    event_log AshEvents.EventLogs.EventLog
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:body]
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:body]
    end

    destroy :destroy do
      primary? true
      require_atomic? false
      accept []
    end

    destroy :soft_destroy do
      require_atomic? false
      soft? true
      accept []
      change set_attribute(:deleted_at, &DateTime.utc_now/0)
    end
  end

  attributes do
    uuid_primary_key :id do
      writable? true
    end

    attribute :body, :string do
      public? true
      allow_nil? false
    end

    attribute :deleted_at, :utc_datetime_usec do
      public? true
      allow_nil? true
    end
  end
end
