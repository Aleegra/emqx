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
%%
-module(emqx_gateway_api).

-include("emqx_gateway_http.hrl").
-include_lib("typerefl/include/types.hrl").
-include_lib("hocon/include/hoconsc.hrl").
-include_lib("emqx/include/emqx_placeholder.hrl").
-include_lib("emqx/include/emqx_authentication.hrl").

-behaviour(minirest_api).

-import(hoconsc, [mk/2, ref/1, ref/2]).

-import(emqx_gateway_http,
        [ return_http_error/2
        , with_gateway/2
        ]).

%% minirest/dashbaord_swagger behaviour callbacks
-export([ api_spec/0
        , paths/0
        , schema/1
        ]).

-export([ roots/0
        , fields/1
        ]).

%% http handlers
-export([ gateway/2
        , gateway_insta/2
        , gateway_insta_stats/2
        ]).

%%--------------------------------------------------------------------
%% minirest behaviour callbacks
%%--------------------------------------------------------------------

api_spec() ->
    emqx_dashboard_swagger:spec(?MODULE, #{check_schema => true}).

paths() ->
    [ "/gateway"
    , "/gateway/:name"
    , "/gateway/:name/stats"
    ].

%%--------------------------------------------------------------------
%% http handlers

gateway(get, Request) ->
    Params = maps:get(query_string, Request, #{}),
    Status = case maps:get(<<"status">>, Params, undefined) of
                 undefined -> all;
                 S0 -> binary_to_existing_atom(S0, utf8)
             end,
    {200, emqx_gateway_http:gateways(Status)};
gateway(post, Request) ->
    Body = maps:get(body, Request, #{}),
    try
        Name0 = maps:get(<<"name">>, Body),
        GwName = binary_to_existing_atom(Name0),
        case emqx_gateway_registry:lookup(GwName) of
            undefined -> error(badarg);
            _ ->
                GwConf = maps:without([<<"name">>], Body),
                case emqx_gateway_conf:load_gateway(GwName, GwConf) of
                    {ok, NGwConf} ->
                        {201, NGwConf};
                    {error, Reason} ->
                        emqx_gateway_http:reason2resp(Reason)
                end
        end
    catch
        error : {badkey, K} ->
            return_http_error(400, [K, " is required"]);
        error : badarg ->
            return_http_error(404, "Bad gateway name")
    end.

gateway_insta(delete, #{bindings := #{name := Name0}}) ->
    with_gateway(Name0, fun(GwName, _) ->
        case emqx_gateway_conf:unload_gateway(GwName) of
            ok ->
                {204};
            {error, Reason} ->
                return_http_error(400, Reason)
        end
    end);
gateway_insta(get, #{bindings := #{name := Name0}}) ->
    try
        binary_to_existing_atom(Name0)
    of
        GwName ->
            case emqx_gateway:lookup(GwName) of
                undefined ->
                    {200, #{name => GwName, status => unloaded}};
                Gateway ->
                    GwConf = emqx_gateway_conf:gateway(Name0),
                    GwInfo0 = emqx_gateway_utils:unix_ts_to_rfc3339(
                                [created_at, started_at, stopped_at],
                                Gateway),
                    GwInfo1 = maps:with([name,
                                         status,
                                         created_at,
                                         started_at,
                                         stopped_at], GwInfo0),
                    {200, maps:merge(GwConf, GwInfo1)}
            end
    catch
        error : badarg ->
            return_http_error(400, "Bad gateway name")
    end;
gateway_insta(put, #{body := GwConf0,
                     bindings := #{name := Name0}
                    }) ->
    with_gateway(Name0, fun(GwName, _) ->
        %% XXX: Clear the unused fields
        GwConf = maps:without([<<"name">>], GwConf0),
        case emqx_gateway_conf:update_gateway(GwName, GwConf) of
            {ok, Gateway} ->
                {200, Gateway};
            {error, Reason} ->
                return_http_error(500, Reason)
        end
    end).

gateway_insta_stats(get, _Req) ->
    return_http_error(401, "Implement it later (maybe 5.1)").

%%--------------------------------------------------------------------
%% Swagger defines
%%--------------------------------------------------------------------

schema("/gateway") ->
    #{ 'operationId' => gateway,
       get =>
         #{ description => <<"Get gateway list">>
          , parameters => params_gateway_status_in_qs()
          , responses =>
              ?STANDARD_RESP(
                 #{200 => emqx_dashboard_swagger:schema_with_example(
                            hoconsc:array(ref(gateway_overview)),
                            examples_gateway_overview())})
          },
       post =>
         #{ description => <<"Load a gateway">>
          %% TODO: distinguish create & response swagger schema
          , 'requestBody' => schema_gateways_conf()
          , responses =>
              ?STANDARD_RESP(#{201 => schema_gateways_conf()})
          }
     };
schema("/gateway/:name") ->
    #{ 'operationId' => gateway_insta,
       get =>
         #{ description => <<"Get the gateway configurations">>
          , parameters => params_gateway_name_in_path()
          , responses =>
              ?STANDARD_RESP(#{200 => schema_gateways_conf()})
          },
       delete =>
         #{ description => <<"Delete/Unload the gateway">>
          , parameters => params_gateway_name_in_path()
          , responses =>
              ?STANDARD_RESP(#{204 => <<"Deleted">>})
          },
       put =>
         #{ description => <<"Update the gateway configurations/status">>
          , parameters => params_gateway_name_in_path()
          , 'requestBody' => schema_update_gateways_conf()
          , responses =>
              ?STANDARD_RESP(#{200 => schema_gateways_conf()})
          }
     };
schema("/gateway/:name/stats") ->
    #{ 'operationId' => gateway_insta_stats,
       get =>
         #{ description => <<"Get gateway Statistic">>
          , parameters => params_gateway_name_in_path()
          , responses =>
              ?STANDARD_RESP(
                 #{200 => emqx_dashboard_swagger:schema_with_examples(
                           ref(gateway_stats),
                           examples_gateway_stats())
                  })
          }
     }.

%%--------------------------------------------------------------------
%% params defines

params_gateway_name_in_path() ->
    [{name,
      mk(binary(),
         #{ in => path
          , desc => <<"Gateway Name">>
          , example => <<"">>
          })}
    ].

params_gateway_status_in_qs() ->
    %% FIXME: enum in swagger ??
    [{status,
      mk(binary(),
         #{ in => query
          , nullable => true
          , desc => <<"Gateway Status">>
          , example => <<"">>
          })}
    ].

%%--------------------------------------------------------------------
%% schemas

roots() ->
    [ gateway_overview
    , gateway_stats
    ].

fields(gateway_overview) ->
    [ {name,
       mk(binary(),
          #{ desc => <<"Gateway Name">>})}
    , {status,
       mk(hoconsc:enum([running, stopped, unloaded]),
          #{ desc => <<"The Gateway status">>})}
    , {created_at,
       mk(binary(),
          #{desc => <<"The Gateway created datetime">>})}
    , {started_at,
       mk(binary(),
          #{ nullable => true
           , desc => <<"The Gateway started datetime">>})}
    , {stopped_at,
       mk(binary(),
          #{ nullable => true
           , desc => <<"The Gateway stopped datetime">>})}
    , {max_connections,
       mk(integer(),
          #{ desc => <<"The Gateway allowed maximum connections/clients">>})}
    , {current_connections,
       mk(integer(),
          #{ desc => <<"The Gateway current connected connections/clients">>
           })}
    , {listeners,
       mk(hoconsc:array(ref(gateway_listener_overview)),
         #{ nullable => {true, recursively}
          , desc => <<"The Gateway listeners overview">>})}
    ];
fields(gateway_listener_overview) ->
    [ {id,
       mk(binary(),
          #{ desc => <<"Listener ID">>})}
    , {running,
       mk(boolean(),
          #{ desc => <<"Listener Running status">>})}
    , {type,
       mk(hoconsc:enum([tcp, ssl, udp, dtls]),
          #{ desc => <<"Listener Type">>})}
    ];

fields(Gw) when Gw == stomp; Gw == mqttsn;
                Gw == coap;  Gw == lwm2m;
                Gw == exproto ->
    [{name,
      mk(hoconsc:union([Gw]), #{ desc => <<"Gateway Name">>})}
    ] ++ convert_listener_struct(emqx_gateway_schema:fields(Gw));

fields(Gw) when Gw == update_stomp; Gw == update_mqttsn;
                Gw == update_coap;  Gw == update_lwm2m;
                Gw == update_exproto ->
    "update_" ++ GwStr = atom_to_list(Gw),
    Gw1 = list_to_existing_atom(GwStr),
    remove_listener_and_authn(emqx_gateway_schema:fields(Gw1));

fields(Listener) when Listener == tcp_listener;
                      Listener == ssl_listener;
                      Listener == udp_listener;
                      Listener == dtls_listener ->
    [ {id,
       mk(binary(),
          #{ nullable => true
           , desc => <<"Listener ID">>})}
    , {type,
       mk(hoconsc:union([tcp, ssl, udp, dtls]),
          #{ desc => <<"Listener type">>})}
    , {name,
       mk(binary(),
          #{ desc => <<"Listener Name">>})}
    , {running,
       mk(boolean(),
          #{ nullable => true
           , desc => <<"Listener running status">>})}
    ] ++ emqx_gateway_schema:fields(Listener);

fields(gateway_stats) ->
    [{key, mk(binary(), #{})}].

schema_update_gateways_conf() ->
    emqx_dashboard_swagger:schema_with_examples(
      hoconsc:union([ref(?MODULE, update_stomp),
                     ref(?MODULE, update_mqttsn),
                     ref(?MODULE, update_coap),
                     ref(?MODULE, update_lwm2m),
                     ref(?MODULE, update_exproto)]),
      examples_update_gateway_confs()
     ).

schema_gateways_conf() ->
    emqx_dashboard_swagger:schema_with_examples(
      hoconsc:union([ref(?MODULE, stomp), ref(?MODULE, mqttsn),
                     ref(?MODULE, coap), ref(?MODULE, lwm2m),
                     ref(?MODULE, exproto)]),
      examples_gateway_confs()
     ).

convert_listener_struct(Schema) ->
    {value, {listeners,
             #{type := Type}}, Schema1} = lists:keytake(listeners, 1, Schema),
    ListenerSchema = hoconsc:mk(listeners_schema(Type),
                                #{ nullable => {true, recursively}
                                 , desc => <<"The gateway listeners">>
                                 }),
    lists:keystore(listeners, 1, Schema1, {listeners, ListenerSchema}).

remove_listener_and_authn(Schmea) ->
    lists:keydelete(
      authentication, 1,
      lists:keydelete(listeners, 1, Schmea)).

listeners_schema(?R_REF(_Mod, tcp_listeners)) ->
    hoconsc:array(hoconsc:union([ref(tcp_listener), ref(ssl_listener)]));
listeners_schema(?R_REF(_Mod, udp_listeners)) ->
    hoconsc:array(hoconsc:union([ref(udp_listener), ref(dtls_listener)]));
listeners_schema(?R_REF(_Mod, udp_tcp_listeners)) ->
    hoconsc:array(hoconsc:union([ref(tcp_listener), ref(ssl_listener),
                                 ref(udp_listener), ref(dtls_listener)])).

%%--------------------------------------------------------------------
%% examples

examples_gateway_overview() ->
    [ #{ name => <<"coap">>
       , status => <<"unloaded">>
       }
    , #{ name => <<"exproto">>
       , status => <<"unloaded">>
      }
    , #{ name => <<"lwm2m">>
       , status => <<"running">>
       , current_connections => 0
       , max_connections => 1024000
       , listeners =>
            [ #{ id => <<"lwm2m:udp:default">>
               , type => <<"udp">>
               , name => <<"default">>
               , running => true
               }
            ]
       , created_at => <<"2021-12-08T14:41:26.171+08:00">>
       , started_at => <<"2021-12-08T14:41:26.202+08:00">>
      }
    , #{ name => <<"mqttsn">>
       , status => <<"stopped">>
       , current_connections => 0
       , max_connections => 1024000
       , listeners =>
            [ #{ id => <<"mqttsn:udp:default">>
               , name => <<"default">>
               , running => false
               , type => <<"udp">>
               }
            ]
       , created_at => <<"2021-12-08T14:41:45.071+08:00">>
       , stopped_at => <<"2021-12-08T14:56:35.576+08:00">>
      }
    , #{ name => <<"stomp">>
       , status => <<"running">>
       , current_connections => 0
       , max_connections => 1024000
       , listeners =>
            [ #{ id => <<"stomp:tcp:default">>
               , name => <<"default">>
               , running => true
               , type => <<"tcp">>
               }
            ]
      , created_at => <<"2021-12-08T14:42:15.272+08:00">>
      , started_at => <<"2021-12-08T14:42:15.274+08:00">>
      }
    ].

examples_gateway_confs() ->
    #{ stomp_gateway =>
        #{ summary => <<"A simple STOMP gateway configs">>
         , value =>
            #{ enable => true
             , name => <<"stomp">>
             , enable_stats => true
             , idle_timeout => <<"30s">>
             , mountpoint => <<"stomp/">>
             , frame =>
                #{ max_headers => 10
                 , max_headers_length => 1024
                 , max_body_length => 65535
                 }
             , listeners =>
                [ #{ type => <<"tcp">>
                   , name => <<"default">>
                   , bind => <<"61613">>
                   , max_connections => 1024000
                   , max_conn_rate => 1000
                   }
                ]
             }
         }
     , mqttsn_gateway =>
        #{ summary => <<"A simple MQTT-SN gateway configs">>
         , value =>
            #{ enable => true
             , name => <<"mqttsn">>
             , enable_stats => true
             , idle_timeout => <<"30s">>
             , mountpoint => <<"mqttsn/">>
             , gateway_id => 1
             , broadcast => true
             , enable_qos3 => true
             , predefined =>
                [ #{ id => <<"1001">>
                   , topic => <<"pred/1001">>
                   }
                , #{ id => <<"1002">>
                   , topic => <<"pred/1002">>
                   }
                ]
             , listeners =>
                [ #{ type => <<"udp">>
                   , name => <<"default">>
                   , bind => <<"1884">>
                   , max_connections => 1024000
                   , max_conn_rate => 1000
                   }
                ]
             }
         }
     , coap_gateway =>
        #{ summary => <<"A simple CoAP gateway configs">>
         , value =>
            #{ enable => true
             , name => <<"coap">>
             , enable_stats => true
             , idle_timeout => <<"30s">>
             , mountpoint => <<"coap/">>
             , heartbeat => <<"30s">>
             , connection_required => false
             , notify_type => <<"qos">>
             , subscribe_qos => <<"coap">>
             , publish_qos => <<"coap">>
             , listeners =>
                [ #{ type => <<"udp">>
                   , name => <<"default">>
                   , bind => <<"5683">>
                   , max_connections => 1024000
                   , max_conn_rate => 1000
                   }
                ]
             }
         }
     , lwm2m_gateway =>
        #{ summary => <<"A simple LwM2M gateway configs">>
         , value =>
            #{ enable => true
             , name => <<"lwm2m">>
             , enable_stats => true
             , idle_timeout => <<"30s">>
             , mountpoint => <<"lwm2m/">>
             , xml_dir => <<"etc/lwm2m_xml">>
             , lifetime_min => <<"1s">>
             , lifetime_max => <<"86400s">>
             , qmode_time_window => <<"22s">>
             , auto_observe => false
             , update_msg_publish_condition => <<"always">>
             , translators =>
                #{ command => #{topic => <<"dn/#">>}
                 , response => #{topic => <<"up/resp">>}
                 , notify => #{topic => <<"up/notify">>}
                 , register => #{topic => <<"up/resp">>}
                 , update => #{topic => <<"up/resp">>}
                 }
             , listeners =>
                [ #{ type => <<"udp">>
                   , name => <<"default">>
                   , bind => <<"5783">>
                   , max_connections => 1024000
                   , max_conn_rate => 1000
                   }
                ]
             }
         }
     , exproto_gateway =>
        #{ summary => <<"A simple ExProto gateway configs">>
         , value =>
            #{ enable => true
             , name => <<"exproto">>
             , enable_stats => true
             , idle_timeout => <<"30s">>
             , mountpoint => <<"exproto/">>
             , server =>
                #{ bind => <<"9100">>
                 }
             , handler =>
                #{ address => <<"http://127.0.0.1:9001">>
                 }
             , listeners =>
                [ #{ type => <<"tcp">>
                   , name => <<"default">>
                   , bind => <<"7993">>
                   , max_connections => 1024000
                   , max_conn_rate => 1000
                   }
                ]
             }
         }
     }.

examples_update_gateway_confs() ->
    #{ stomp_gateway =>
        #{ summary => <<"A simple STOMP gateway configs">>
         , value =>
            #{ enable => true
             , enable_stats => true
             , idle_timeout => <<"30s">>
             , mountpoint => <<"stomp2/">>
             , frame =>
                #{ max_headers => 100
                 , max_headers_length => 10240
                 , max_body_length => 655350
                 }
             }
         }
     , mqttsn_gateway =>
        #{ summary => <<"A simple MQTT-SN gateway configs">>
         , value =>
            #{ enable => true
             , enable_stats => true
             , idle_timeout => <<"30s">>
             , mountpoint => <<"mqttsn2/">>
             , gateway_id => 1
             , broadcast => true
             , enable_qos3 => false
             , predefined =>
                [ #{ id => <<"1003">>
                   , topic => <<"pred/1003">>
                   }
                ]
             }
         }
     , coap_gateway =>
        #{ summary => <<"A simple CoAP gateway configs">>
         , value =>
            #{ enable => true
             , enable_stats => true
             , idle_timeout => <<"30s">>
             , mountpoint => <<"coap2/">>
             , heartbeat => <<"30s">>
             , connection_required => false
             , notify_type => <<"qos">>
             , subscribe_qos => <<"coap">>
             , publish_qos => <<"coap">>
             }
         }
     , lwm2m_gateway =>
        #{ summary => <<"A simple LwM2M gateway configs">>
         , value =>
            #{ enable => true
             , enable_stats => true
             , idle_timeout => <<"30s">>
             , mountpoint => <<"lwm2m2/">>
             , xml_dir => <<"etc/lwm2m_xml">>
             , lifetime_min => <<"1s">>
             , lifetime_max => <<"86400s">>
             , qmode_time_window => <<"22s">>
             , auto_observe => false
             , update_msg_publish_condition => <<"always">>
             , translators =>
                #{ command => #{topic => <<"dn/#">>}
                 , response => #{topic => <<"up/resp">>}
                 , notify => #{topic => <<"up/notify">>}
                 , register => #{topic => <<"up/resp">>}
                 , update => #{topic => <<"up/resp">>}
                 }
             }
         }
     , exproto_gateway =>
        #{ summary => <<"A simple ExProto gateway configs">>
         , value =>
            #{ enable => true
             , enable_stats => true
             , idle_timeout => <<"30s">>
             , mountpoint => <<"exproto2/">>
             , server =>
                #{ bind => <<"9100">>
                 }
             , handler =>
                #{ address => <<"http://127.0.0.1:9001">>
                 }
             }
         }
     }.

examples_gateway_stats() ->
    #{}.
