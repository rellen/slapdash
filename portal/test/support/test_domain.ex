defmodule Slapdash.Test.Domain do
  @moduledoc "Test-only resources. Not registered in `:ash_domains`."
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshPaperTrail.Domain]

  resources do
    resource Slapdash.Test.TenantNote
  end

  paper_trail do
    include_versions? true
  end
end
