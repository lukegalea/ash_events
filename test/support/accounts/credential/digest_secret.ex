# SPDX-FileCopyrightText: 2023 ash_events contributors <https://github.com/ash-project/ash_events/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshEvents.Accounts.Credential.DigestSecret do
  @moduledoc false
  # Derives a sensitive attribute (`secret_digest`) and a non-sensitive one
  # (`secret_hint`) from the sensitive `secret` argument, the way a password
  # hashing change derives `hashed_password`.
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :secret) do
      secret when is_binary(secret) ->
        changeset
        |> Ash.Changeset.force_change_attribute(:secret_digest, digest(secret))
        |> Ash.Changeset.force_change_attribute(:secret_hint, String.slice(secret, -2, 2))

      _ ->
        changeset
    end
  end

  defp digest(secret), do: :sha256 |> :crypto.hash(secret) |> Base.encode16(case: :lower)
end
