# SPDX-FileCopyrightText: 2023 ash_events contributors <https://github.com/ash-project/ash_events/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshEvents.Accounts.Credential do
  @moduledoc false
  # A resource whose actions take a sensitive argument, accept a sensitive
  # attribute as input, and derive sensitive attributes in a change, so the
  # event log's handling of each can be asserted.
  use Ash.Resource,
    domain: AshEvents.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshEvents.Events]

  postgres do
    table "credentials"
    repo AshEvents.TestRepo
  end

  events do
    event_log AshEvents.EventLogs.EventLog
  end

  actions do
    defaults [:read]

    create :create do
      accept [:id, :label, :api_key]

      # Not required: a sensitive argument is stored as nil, so a required
      # one could only be replayed through a replay_override action.
      argument :secret, :string do
        sensitive? true
      end

      change AshEvents.Accounts.Credential.DigestSecret
    end

    update :rotate do
      require_atomic? false
      accept [:label]

      # Not required: a sensitive argument is stored as nil, so a required
      # one could only be replayed through a replay_override action.
      argument :secret, :string do
        sensitive? true
      end

      change AshEvents.Accounts.Credential.DigestSecret
    end
  end

  attributes do
    uuid_primary_key :id do
      writable? true
    end

    attribute :label, :string do
      public? true
      allow_nil? false
    end

    attribute :api_key, :string do
      public? true
      sensitive? true
    end

    attribute :secret_digest, :string do
      public? true
      sensitive? true
    end

    attribute :secret_hint, :string do
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end
end
