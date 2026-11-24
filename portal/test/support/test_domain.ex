defmodule Ramshackle.Test.Domain do
  @moduledoc "Test-only resources. Not registered in `:ash_domains`."
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Ramshackle.Test.TenantNote
  end
end
