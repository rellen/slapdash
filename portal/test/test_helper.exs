ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Slapdash.Repo, :manual)

# Comments that Slapdash.Test.FakeProvider records. This process lives for
# the whole test run, so the table does too.
:ets.new(Slapdash.Test.FakeProvider, [:named_table, :public, :set])
