%%--------------------------------------------------------------------
%% Copyright (c) 2021-2022 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_exhook_api).

-behaviour(minirest_api).

-include_lib("typerefl/include/types.hrl").
-include_lib("emqx/include/logger.hrl").

-export([api_spec/0, paths/0, schema/1, fields/1, namespace/0]).

-export([exhooks/2, action_with_name/2, move/2, server_hooks/2]).

-import(hoconsc, [mk/2, ref/1, enum/1, array/1, map/2]).
-import(emqx_dashboard_swagger, [schema_with_example/2, error_codes/2]).

-define(TAGS, [<<"exhooks">>]).
-define(BAD_REQUEST, 'BAD_REQUEST').
-define(BAD_RPC, 'BAD_RPC').

-type rpc_result() :: {error, any()}
                    | any().

-dialyzer([{nowarn_function, [ fill_cluster_server_info/5
                             , nodes_server_info/5
                             , fill_server_hooks_info/4
                             ]}]).

%%--------------------------------------------------------------------
%% schema
%%--------------------------------------------------------------------
namespace() -> "exhook".

api_spec() ->
    emqx_dashboard_swagger:spec(?MODULE).

paths() -> ["/exhooks", "/exhooks/:name", "/exhooks/:name/move", "/exhooks/:name/hooks"].

schema(("/exhooks")) ->
    #{
      'operationId' => exhooks,
      get => #{tags => ?TAGS,
               description => <<"List all servers">>,
               responses => #{200 => mk(array(ref(detail_server_info)), #{})}
              },
      post => #{tags => ?TAGS,
                description => <<"Add a servers">>,
                'requestBody' => server_conf_schema(),
                responses => #{201 => mk(ref(detail_server_info), #{}),
                               500 => error_codes([?BAD_RPC], <<"Bad RPC">>)
                              }
               }
     };

schema("/exhooks/:name") ->
    #{'operationId' => action_with_name,
      get => #{tags => ?TAGS,
               description => <<"Get the detail information of server">>,
               parameters => params_server_name_in_path(),
               responses => #{200 => mk(ref(detail_server_info), #{}),
                              400 => error_codes([?BAD_REQUEST], <<"Bad Request">>)
                             }
              },
      put => #{tags => ?TAGS,
               description => <<"Update the server">>,
               parameters => params_server_name_in_path(),
               'requestBody' => server_conf_schema(),
               responses => #{200 => <<>>,
                              400 => error_codes([?BAD_REQUEST], <<"Bad Request">>),
                              500 => error_codes([?BAD_RPC], <<"Bad RPC">>)
                             }
              },
      delete => #{tags => ?TAGS,
                  description => <<"Delete the server">>,
                  parameters => params_server_name_in_path(),
                  responses => #{204 => <<>>,
                                 500 => error_codes([?BAD_RPC], <<"Bad RPC">>)
                                }
                 }
     };

schema("/exhooks/:name/hooks") ->
    #{'operationId' => server_hooks,
      get => #{tags => ?TAGS,
               description => <<"Get the hooks information of server">>,
               parameters => params_server_name_in_path(),
               responses => #{200 => mk(array(ref(list_hook_info)), #{}),
                              400 => error_codes([?BAD_REQUEST], <<"Bad Request">>)
                             }
              }
     };

schema("/exhooks/:name/move") ->
    #{'operationId' => move,
      post => #{tags => ?TAGS,
                description => <<"Move the server">>,
                parameters => params_server_name_in_path(),
                'requestBody' => mk(ref(move_req), #{}),
                responses => #{200 => <<>>,
                               400 => error_codes([?BAD_REQUEST], <<"Bad Request">>),
                               500 => error_codes([?BAD_RPC], <<"Bad RPC">>)
                              }
               }
     }.

fields(move_req) ->
    [ {position, mk(enum([top, bottom, before, 'after']), #{})}
    , {related, mk(string(), #{desc => <<"Relative position of movement">>,
                               default => <<>>,
                               example => <<>>
                              })}
    ];

fields(detail_server_info) ->
    [ {metrics, mk(ref(metrics), #{})}
    , {node_metrics, mk(array(ref(node_metrics)), #{})}
    , {node_status, mk(array(ref(node_status)), #{})}
    , {hooks, mk(array(ref(hook_info)), #{})}
    ] ++ emqx_exhook_schema:server_config();

fields(list_hook_info) ->
    [ {name, mk(binary(), #{desc => <<"The hook's name">>})}
    , {params, mk(map(name, binary()),
                  #{desc => <<"The parameters used when the hook is registered">>})}
    , {metrics, mk(ref(metrics), #{})}
    , {node_metrics, mk(array(ref(node_metrics)), #{})}
    ];

fields(node_metrics) ->
    [ {node, mk(string(), #{})}
    , {metrics, mk(ref(metrics), #{})}
    ];

fields(node_status) ->
    [ {node, mk(string(), #{})}
    , {status, mk(enum([running, waiting, stopped, error]), #{})}
    ];

fields(hook_info) ->
    [ {name, mk(binary(), #{desc => <<"The hook's name">>})}
    , {params, mk(map(name, binary()),
                  #{desc => <<"The parameters used when the hook is registered">>})}
    ];

fields(metrics) ->
    [ {succeed, mk(integer(), #{})}
    , {failed, mk(integer(), #{})}
    , {rate, mk(integer(), #{})}
    , {max_rate, mk(integer(), #{})}
    ];

fields(server_config) ->
    emqx_exhook_schema:server_config().

params_server_name_in_path() ->
    [{name, mk(string(), #{in => path,
                           required => true,
                           example => <<"default">>})}
    ].

server_conf_schema() ->
    schema_with_example(ref(server_config),
                        #{ name => "default"
                         , enable => true
                         , url => <<"http://127.0.0.1:8081">>
                         , request_timeout => "5s"
                         , failed_action => deny
                         , auto_reconnect => "60s"
                         , pool_size => 8
                         , ssl => #{ enable => false
                                   , cacertfile => <<"{{ platform_etc_dir }}/certs/cacert.pem">>
                                   , certfile => <<"{{ platform_etc_dir }}/certs/cert.pem">>
                                   , keyfile => <<"{{ platform_etc_dir }}/certs/key.pem">>
                                   }
                         }).

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------
exhooks(get, _) ->
    Confs = emqx:get_config([exhook, servers]),
    Infos = nodes_all_server_info(Confs),
    {200, Infos};

exhooks(post, #{body := Body}) ->
    case emqx_exhook_mgr:update_config([exhook, servers], {add, Body}) of
        {ok, _} ->
            #{<<"name">> := Name} = Body,
            get_nodes_server_info(Name);
        {error, Error} ->
            {500, #{code => <<"BAD_RPC">>,
                    message => Error
                   }}
    end.

action_with_name(get, #{bindings := #{name := Name}}) ->
    get_nodes_server_info(Name);

action_with_name(put, #{bindings := #{name := Name}, body := Body}) ->
    case emqx_exhook_mgr:update_config([exhook, servers],
                                       {update, Name, Body}) of
        {ok, not_found} ->
            {400, #{code => <<"BAD_REQUEST">>,
                    message => <<"Server not found">>
                   }};
        {ok, {error, Reason}} ->
            {400, #{code => <<"BAD_REQUEST">>,
                    message => unicode:characters_to_binary(io_lib:format("Error Reason:~p~n", [Reason]))
                   }};
        {ok, _} ->
            {200};
        {error, Error} ->
            {500, #{code => <<"BAD_RPC">>,
                    message => Error
                   }}
    end;

action_with_name(delete, #{bindings := #{name := Name}}) ->
    case emqx_exhook_mgr:update_config([exhook, servers],
                                       {delete, Name}) of
        {ok, _} ->
            {200};
        {error, Error} ->
            {500, #{code => <<"BAD_RPC">>,
                    message => Error
                   }}
    end.

move(post, #{bindings := #{name := Name}, body := Body}) ->
    #{<<"position">> := PositionT, <<"related">> := Related} = Body,
    Position = erlang:binary_to_atom(PositionT),
    case emqx_exhook_mgr:update_config([exhook, servers],
                                       {move, Name, Position, Related}) of
        {ok, ok} ->
            {200};
        {ok, not_found} ->
            {400, #{code => <<"BAD_REQUEST">>,
                    message => <<"Server not found">>
                   }};
        {error, Error} ->
            {500, #{code => <<"BAD_RPC">>,
                    message => Error
                   }}
    end.

server_hooks(get, #{bindings := #{name := Name}}) ->
    Confs = emqx:get_config([exhook, servers]),
    case lists:search(fun(#{name := CfgName}) -> CfgName =:= Name end, Confs) of
        false ->
            {400, #{code => <<"BAD_REQUEST">>,
                    message => <<"Server not found">>
                   }};
        _ ->
            Info = get_nodes_server_hooks_info(Name),
            {200, Info}
    end.

get_nodes_server_info(Name) ->
    Confs = emqx:get_config([exhook, servers]),
    case lists:search(fun(#{name := CfgName}) -> CfgName =:= Name end, Confs) of
        false ->
            {400, #{code => <<"BAD_REQUEST">>,
                    message => <<"Server not found">>
                   }};
        {value, Conf} ->
            NodeStatus = nodes_server_info(Name),
            {200, maps:merge(Conf, NodeStatus)}
    end.

%%--------------------------------------------------------------------
%% GET /exhooks
%%--------------------------------------------------------------------
nodes_all_server_info(ConfL) ->
    AllInfos = call_cluster(emqx_exhook_mgr, all_servers_info, []),
    Default = emqx_exhook_metrics:new_metrics_info(),
    node_all_server_info(ConfL, AllInfos, Default, []).

node_all_server_info([#{name := ServerName} = Conf | T], AllInfos, Default, Acc) ->
    Info = fill_cluster_server_info(AllInfos, [], [], ServerName, Default),
    AllInfo = maps:merge(Conf, Info),
    node_all_server_info(T, AllInfos, Default, [AllInfo | Acc]);

node_all_server_info([], _, _, Acc) ->
    lists:reverse(Acc).

fill_cluster_server_info([{Node, {error, _}} | T], StatusL, MetricsL, ServerName, Default) ->
    fill_cluster_server_info(T,
                             [#{node => Node, status => error} | StatusL],
                             [#{node => Node, metrics => Default} | MetricsL],
                             ServerName,
                             Default);

fill_cluster_server_info([{Node, Result} | T], StatusL, MetricsL, ServerName, Default) ->
    #{status := Status, metrics := Metrics} = Result,
    fill_cluster_server_info(T,
                             [#{node => Node, status => maps:get(ServerName, Status, error)} | StatusL],
                             [#{node => Node, metrics => maps:get(ServerName, Metrics, Default)} | MetricsL],
                             ServerName,
                             Default);

fill_cluster_server_info([], StatusL, MetricsL, ServerName, _) ->
    Metrics = emqx_exhook_metrics:metrics_aggregate_by_key(metrics, MetricsL),
    #{metrics => Metrics,
      node_metrics => MetricsL,
      node_status => StatusL,
      hooks => emqx_exhook_mgr:hooks(ServerName)
     }.

%%--------------------------------------------------------------------
%% GET /exhooks/{name}
%%--------------------------------------------------------------------
nodes_server_info(Name) ->
    InfoL = call_cluster(emqx_exhook_mgr, server_info, [Name]),
    Default = emqx_exhook_metrics:new_metrics_info(),
    nodes_server_info(InfoL, Name, Default, [], []).

nodes_server_info([{Node, {error, _}} | T], Name, Default, StatusL, MetricsL) ->
    nodes_server_info(T,
                      Name,
                      Default,
                      [#{node => Node, status => error} | StatusL],
                      [#{node => Node, metrics => Default} | MetricsL]
                     );

nodes_server_info([{Node, Result} | T], Name, Default, StatusL, MetricsL) ->
    #{status := Status, metrics := Metrics} = Result,
    nodes_server_info(T,
                      Name,
                      Default,
                      [#{node => Node, status => Status} | StatusL],
                      [#{node => Node, metrics => Metrics} | MetricsL]
                     );

nodes_server_info([], Name, _, StatusL, MetricsL) ->
    #{metrics => emqx_exhook_metrics:metrics_aggregate_by_key(metrics, MetricsL),
      node_status => StatusL,
      node_metrics => MetricsL,
      hooks => emqx_exhook_mgr:hooks(Name)
     }.

%%--------------------------------------------------------------------
%% GET /exhooks/{name}/hooks
%%--------------------------------------------------------------------
get_nodes_server_hooks_info(Name) ->
    case emqx_exhook_mgr:hooks(Name) of
        [] -> [];
        Hooks ->
            AllInfos = call_cluster(emqx_exhook_mgr, server_hooks_metrics, [Name]),
            Default = emqx_exhook_metrics:new_metrics_info(),
            get_nodes_server_hooks_info(Hooks, AllInfos, Default, [])
    end.

get_nodes_server_hooks_info([#{name := Name} = Spec | T], AllInfos, Default, Acc) ->
    Info = fill_server_hooks_info(AllInfos, Name, Default, []),
    AllInfo = maps:merge(Spec, Info),
    get_nodes_server_hooks_info(T, AllInfos, Default, [AllInfo | Acc]);

get_nodes_server_hooks_info([], _, _, Acc) ->
    Acc.

fill_server_hooks_info([{_, {error, _}} | T], Name, Default, MetricsL) ->
    fill_server_hooks_info(T, Name, Default, MetricsL);

fill_server_hooks_info([{Node, MetricsMap} | T], Name, Default, MetricsL) ->
    Metrics = maps:get(Name, MetricsMap, Default),
    NodeMetrics = #{node => Node, metrics => Metrics},
    fill_server_hooks_info(T, Name, Default, [NodeMetrics | MetricsL]);

fill_server_hooks_info([], _Name, _Default, MetricsL) ->
    Metrics = emqx_exhook_metrics:metrics_aggregate_by_key(metrics, MetricsL),
    #{metrics => Metrics, node_metrics => MetricsL}.

%%--------------------------------------------------------------------
%% cluster call
%%--------------------------------------------------------------------
call_cluster(Module, Fun, Args) ->
    Nodes = mria_mnesia:running_nodes(),
    [{Node, rpc_call(Node, Module, Fun, Args)} || Node <- Nodes].

-spec rpc_call(node(), atom(), atom(), list()) -> rpc_result().
rpc_call(Node, Module, Fun, Args) when Node =:= node() ->
    erlang:apply(Module, Fun, Args);

rpc_call(Node, Module, Fun, Args) ->
    case rpc:call(Node, Module, Fun, Args) of
        {badrpc, Reason} -> {error, Reason};
        Res -> Res
    end.
