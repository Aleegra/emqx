defmodule EMQXUmbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      app: :emqx,
      version: pkg_vsn(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  defp deps do
    [
      {:jiffy, github: "emqx/jiffy", tag: "1.0.5", override: true},
      {:jsx, "~> 3.1", override: true},
      {:gun, github: "emqx/gun", tag: "1.3.4", override: true},
      {:hocon, github: "emqx/hocon", tag: "0.20.5", override: true},
      {:cuttlefish,
       github: "emqx/cuttlefish",
       manager: :rebar3,
       system_env: [{"CUTTLEFISH_ESCRIPT", "true"}],
       override: true},
      {:getopt, github: "emqx/getopt", tag: "v1.0.2", override: true},
      {:cowboy, github: "emqx/cowboy", tag: "2.8.2", override: true},
      {:cowlib, "~> 2.8", override: true},
      {:ranch, "~> 2.0", override: true},
      {:poolboy, github: "emqx/poolboy", tag: "1.5.2", override: true},
      {:esockd, github: "emqx/esockd", tag: "5.8.0", override: true},
      {:gproc, "~> 0.9", override: true},
      {:eetcd, "~> 0.3", override: true},
      {:grpc, github: "emqx/grpc-erl", tag: "0.6.2", override: true},
      {:pbkdf2, github: "emqx/erlang-pbkdf2", tag: "2.0.4", override: true},
      {:typerefl, github: "k32/typerefl", tag: "0.8.4", manager: :rebar3, override: true},
      {:gen_rpc, github: "emqx/gen_rpc", tag: "2.5.1", override: true},
      {:gen_coap, github: "emqx/gen_coap", tag: "v0.3.2", override: true},
      {:snabbkaffe, github: "kafka4beam/snabbkaffe", tag: "0.14.0", override: true},
      {:emqx_http_lib, github: "emqx/emqx_http_lib", tag: "0.4.0", override: true},
      ####
      {:emqx, path: "apps/emqx"},
    ] ++ ((enable_bcrypt() && [{:bcrypt, github: "emqx/erlang-bcrypt", tag: "0.6.0"}]) || [])
  end

  defp releases do
    [
      emqx: fn ->
        [
          applications: EmqxReleaseHelper.applications(),
          steps: [:assemble, &EmqxReleaseHelper.run/1]
        ]
      end
    ]
  end

  def enable_bcrypt do
    not match?({:win_32, _}, :os.type())
  end

  def project_path do
    Path.expand("..", __ENV__.file)
  end

  def pkg_vsn do
    project_path()
    |> Path.join("pkg-vsn.sh")
    |> System.cmd([])
    |> elem(0)
    |> String.trim()
    |> String.split("-")
    |> Enum.reverse()
    |> tl()
    |> Enum.reverse()
    |> Enum.join("-")
  end
end
