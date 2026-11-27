defmodule Slapdash.Bots.Runner do
  @moduledoc """
  The behaviour for a runner: the part that runs a bot somewhere.

  `Slapdash.Bots.dispatch/2` gives each new run to the bot's runner with
  `dispatch/2`. The runner must arrange for `Slapdash.Bots.Execution.run/2`
  to run, or for an equivalent that records the same result on the run.
  `dispatch/2` can get the same queued run more than one time, so it must
  not run a run two times.

  `Slapdash.Bots.Runners.InProcess` runs bots in the portal with Oban. A
  runner on remote machines also implements this behaviour.
  """

  @doc "Arranges for a queued run to run. Return quickly."
  @callback dispatch(Slapdash.Bots.Run.t(), tenant :: Slapdash.Tenancy.Tenant.t()) ::
              :ok | {:error, term()}
end
