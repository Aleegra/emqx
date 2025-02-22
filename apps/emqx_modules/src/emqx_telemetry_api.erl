%%--------------------------------------------------------------------
%% Copyright (c) 2020-2022 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_telemetry_api).

-behaviour(minirest_api).

-include_lib("typerefl/include/types.hrl").

-import(hoconsc, [mk/2, ref/1, ref/2, array/1]).

% -export([cli/1]).

-export([ status/2
        , data/2
        ]).

-export([enable_telemetry/2]).

-export([ api_spec/0
        , paths/0
        , schema/1
        , fields/1
        ]).

-define(BAD_REQUEST, 'BAD_REQUEST').

api_spec() ->
    emqx_dashboard_swagger:spec(?MODULE, #{check_schema => true}).

paths() ->
    [ "/telemetry/status"
    , "/telemetry/data"
    ].

schema("/telemetry/status") ->
    #{ 'operationId' => status,
       get =>
           #{ description => <<"Get telemetry status">>
            , responses =>
                  #{ 200 => status_schema(<<"Get telemetry status">>)}
            },
       put =>
           #{ description => <<"Enable or disable telemetry">>
            , 'requestBody' => status_schema(<<"Enable or disable telemetry">>)
            , responses =>
                  #{ 200 => status_schema(<<"Enable or disable telemetry successfully">>)
                   , 400 => emqx_dashboard_swagger:error_codes([?BAD_REQUEST], <<"Bad Request">>)
                   }
            }
     };
schema("/telemetry/data") ->
    #{ 'operationId' => data,
       get =>
           #{ description => <<"Get telemetry data">>
            , responses =>
                  #{ 200 => mk(ref(?MODULE, telemetry), #{ desc => <<"Get telemetry data">>})}}
     }.

status_schema(Desc) ->
    mk(ref(?MODULE, status), #{desc => Desc}).

fields(status) ->
    [ { enable
      , mk( boolean()
          , #{ desc => <<"Telemetry status">>
             , default => false
             , example => false
             })
      }
    ];
fields(telemetry) ->
    [ { emqx_version
      , mk( string()
          , #{ desc => <<"EMQ X Version">>
             , example => <<"5.0.0-beta.3-32d1547c">>
             })
      }
    , { license
      , mk( map()
          , #{ desc => <<"EMQ X License">>
             , example => #{edition => <<"community">>}
             })
      }
    , { os_name
      , mk( string()
          , #{ desc => <<"OS Name">>
             , example => <<"Linux">>
             })
      }
    , { os_version
      , mk( string()
          , #{ desc => <<"OS Version">>
             , example => <<"20.04">>
             })
      }
    , { otp_version
      , mk( string()
          , #{ desc => <<"Erlang/OTP Version">>
             , example => <<"24">>
             })
      }
    , { up_time
      , mk( integer()
          , #{ desc => <<"EMQ X Runtime">>
             , example => 20220113
             })
      }
    , { uuid
      , mk( string()
          , #{ desc => <<"EMQ X UUID">>
             , example => <<"AAAAAAAA-BBBB-CCCC-2022-DDDDEEEEFFF">>
             })
      }
    , { nodes_uuid
      , mk( array(binary())
          , #{ desc => <<"EMQ X Cluster Nodes UUID">>
             , example => [ <<"AAAAAAAA-BBBB-CCCC-2022-DDDDEEEEFFF">>
                          , <<"ZZZZZZZZ-CCCC-BBBB-2022-DDDDEEEEFFF">>]
             })
      }
    , { active_plugins
      , mk( array(binary())
          , #{ desc => <<"EMQ X Active Plugins">>
             , example => [<<"Plugin A">>, <<"Plugin B">>]
             })
      }
    , { active_modules
      , mk( array(binary())
          , #{ desc => <<"EMQ X Active Modules">>
             , example => [<<"Module A">>, <<"Module B">>]
             })
      }
    , { num_clients
      , mk( integer()
          , #{ desc => <<"EMQ X Current Connections">>
             , example => 20220113
             })
      }
    , { messages_received
      , mk( integer()
          , #{ desc => <<"EMQ X Current Received Message">>
             , example => 2022
             })
      }
    , { messages_sent
      , mk( integer()
          , #{ desc => <<"EMQ X Current Sent Message">>
             , example => 2022
             })
      }
    ].

%%--------------------------------------------------------------------
%% HTTP API
%%--------------------------------------------------------------------
status(get, _Params) ->
    {200, get_telemetry_status()};

status(put, #{body := Body}) ->
    Enable = maps:get(<<"enable">>, Body),
    case Enable =:= emqx_telemetry:get_status() of
        true ->
            Reason = case Enable of
                true -> <<"Telemetry status is already enabled">>;
                false -> <<"Telemetry status is already disable">>
            end,
            {400, #{code => 'BAD_REQUEST', message => Reason}};
        false ->
            enable_telemetry(Enable),
            {200, #{<<"enable">> => emqx_telemetry:get_status()}}
    end.

data(get, _Request) ->
    {200, emqx_json:encode(get_telemetry_data())}.
%%--------------------------------------------------------------------
%% CLI
%%--------------------------------------------------------------------
% cli(["enable", Enable0]) ->
%     Enable = list_to_atom(Enable0),
%     case Enable =:= emqx_telemetry:is_enabled() of
%         true ->
%             case Enable of
%                 true -> emqx_ctl:print("Telemetry status is already enabled~n");
%                 false -> emqx_ctl:print("Telemetry status is already disable~n")
%             end;
%         false ->
%             enable_telemetry(Enable),
%             case Enable of
%                 true -> emqx_ctl:print("Enable telemetry successfully~n");
%                 false -> emqx_ctl:print("Disable telemetry successfully~n")
%             end
%     end;

% cli(["get", "status"]) ->
%     case get_telemetry_status() of
%         [{enabled, true}] ->
%             emqx_ctl:print("Telemetry is enabled~n");
%         [{enabled, false}] ->
%             emqx_ctl:print("Telemetry is disabled~n")
%     end;

% cli(["get", "data"]) ->
%     TelemetryData = get_telemetry_data(),
%     case emqx_json:safe_encode(TelemetryData, [pretty]) of
%         {ok, Bin} ->
%             emqx_ctl:print("~ts~n", [Bin]);
%         {error, _Reason} ->
%             emqx_ctl:print("Failed to get telemetry data")
%     end;

% cli(_) ->
%     emqx_ctl:usage([{"telemetry enable",   "Enable telemetry"},
%                     {"telemetry disable",  "Disable telemetry"},
%                     {"telemetry get data", "Get reported telemetry data"}]).

%%--------------------------------------------------------------------
%% internal function
%%--------------------------------------------------------------------
enable_telemetry(Enable) ->
    lists:foreach(fun(Node) ->
        enable_telemetry(Node, Enable)
    end, mria_mnesia:running_nodes()).

enable_telemetry(Node, true) ->
    is_ok(emqx_telemetry_proto_v1:enable_telemetry(Node));
enable_telemetry(Node, false) ->
    is_ok(emqx_telemetry_proto_v1:disable_telemetry(Node)).

get_telemetry_status() ->
    #{enabled => emqx_telemetry:get_status()}.

get_telemetry_data() ->
    {ok, TelemetryData} = emqx_telemetry:get_telemetry(),
    TelemetryData.

is_ok(Result) ->
    case Result of
        {badrpc, Reason} -> {error, Reason};
        Result -> Result
    end.
