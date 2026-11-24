defmodule Slapdash.Test.Domain do
  @moduledoc "Test-only resources. Not registered in `:ash_domains`."
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Slapdash.Test.TenantNote
  end
end
