defmodule Ramshackle.Authz.Resource.Scope do
  @moduledoc "A `scope` declared in a resource's `authz` section."
  defstruct [:name, :filter, :__spark_metadata__]
end
