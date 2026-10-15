# SPDX-FileCopyrightText: 2023 ash_events contributors <https://github.com/ash-project/ash_events/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshEvents.Events.Verifiers.VerifyStoreSensitiveAttributes do
  @moduledoc """
  Verifies that store_sensitive_attributes configuration is valid.

  Checks that:
  - store_sensitive_attributes is not configured when the event log is encrypted
  - all listed names are attributes of the resource
  - all listed attributes are marked `sensitive?`
  """
  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    store_sensitive_attributes =
      AshEvents.Events.Info.events_store_sensitive_attributes!(dsl_state)

    resource = Spark.Dsl.Verifier.get_persisted(dsl_state, :module)
    attributes = Ash.Resource.Info.attributes(dsl_state)

    cond do
      store_sensitive_attributes == [] ->
        :ok

      cloaked_event_log?(dsl_state) ->
        error(
          resource,
          "store_sensitive_attributes cannot be used with an encrypted event log, which already stores every sensitive value."
        )

      true ->
        Enum.reduce_while(store_sensitive_attributes, :ok, fn name, :ok ->
          case Enum.find(attributes, &(&1.name == name)) do
            nil ->
              {:halt,
               error(
                 resource,
                 "Attribute #{inspect(name)} in store_sensitive_attributes does not exist on resource #{inspect(resource)}"
               )}

            %{sensitive?: false} ->
              {:halt,
               error(
                 resource,
                 "Attribute #{inspect(name)} in store_sensitive_attributes is not marked sensitive? on resource #{inspect(resource)}. Only sensitive attributes need to be listed."
               )}

            _ ->
              {:cont, :ok}
          end
        end)
    end
  end

  defp cloaked_event_log?(dsl_state) do
    case AshEvents.Events.Info.events_event_log(dsl_state) do
      {:ok, event_log} -> AshEvents.EventLog.Info.cloaked?(event_log)
      :error -> false
    end
  end

  defp error(resource, message) do
    {:error,
     Spark.Error.DslError.exception(
       message: message,
       path: [:events, :store_sensitive_attributes],
       module: resource
     )}
  end
end
