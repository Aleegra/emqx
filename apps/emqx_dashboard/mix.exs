defmodule EMQXDashboard.MixProject do
  use Mix.Project
  Code.require_file("../../lib/emqx/mix/common.ex")

  def project do
    [
      app: :emqx_dashboard,
      version: "4.4.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.12",
      # start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "EMQ X Web Dashboard"
    ]
  end

  def application do
    [
      registered: [:emqx_dashboard_sup],
      mod: {:emqx_dashboard_app, []},
      applications: EMQX.Mix.Common.from_erl!(:emqx_dashboard, :applications),
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:emqx, in_umbrella: true, runtime: false},
      # {:minirest, github: "emqx/minirest", tag: "1.2.4"}
    ]
  end
end
