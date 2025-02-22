%%--------------------------------------------------------------------
%% Copyright (c) 2022 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_gateway_SUITE).

-include_lib("eunit/include/eunit.hrl").

-compile(export_all).
-compile(nowarn_export_all).

-define(GWNAME, mqttsn).
-define(CONF_DEFAULT, <<"gateway {}">>).

%%--------------------------------------------------------------------
%% setups
%%--------------------------------------------------------------------

all() -> emqx_common_test_helpers:all(?MODULE).

init_per_suite(Conf) ->
    emqx_config:erase(gateway),
    emqx_config:init_load(emqx_gateway_schema, ?CONF_DEFAULT),
    emqx_common_test_helpers:start_apps([emqx_gateway]),
    Conf.

end_per_suite(_Conf) ->
    emqx_common_test_helpers:stop_apps([emqx_gateway]).

%%--------------------------------------------------------------------
%% cases
%%--------------------------------------------------------------------

t_registered_gateway(_) ->
    [{coap, #{cbkmod := emqx_coap_impl}},
     {exproto, #{cbkmod := emqx_exproto_impl}},
     {lwm2m, #{cbkmod := emqx_lwm2m_impl}},
     {mqttsn, #{cbkmod := emqx_sn_impl}},
     {stomp, #{cbkmod := emqx_stomp_impl}}] =  emqx_gateway:registered_gateway().

t_load_unload_list_lookup(_) ->
    {ok, _} = emqx_gateway:load(?GWNAME, #{idle_timeout => 1000}),
    ?assertEqual(
       {error, alredy_existed},
       emqx_gateway:load(?GWNAME, #{})),
    ?assertEqual(
       {error, {unknown_gateway_name, bad_gw_name}},
       emqx_gateway:load(bad_gw_name, #{})),

    ?assertEqual(1, length(emqx_gateway:list())),
    ?assertEqual(
       emqx_gateway:lookup(?GWNAME),
       lists:nth(1, emqx_gateway:list())),

    ?assertEqual(ok, emqx_gateway:unload(?GWNAME)),
    ?assertEqual({error, not_found}, emqx_gateway:unload(?GWNAME)).

t_start_stop_update(_) ->
    {ok, _} = emqx_gateway:load(?GWNAME, #{idle_timeout => 1000}),

    #{status := running} = emqx_gateway:lookup(?GWNAME),

    ok = emqx_gateway:stop(?GWNAME),
    {error, already_stopped} = emqx_gateway:stop(?GWNAME),

    #{status := stopped} = emqx_gateway:lookup(?GWNAME),

    ok = emqx_gateway:update(
           ?GWNAME, #{enable => false, idle_timeout => 2000}),
    #{status := stopped,
      config := #{idle_timeout := 2000}} = emqx_gateway:lookup(?GWNAME),

    ok = emqx_gateway:update(
           ?GWNAME, #{enable => true, idle_timeout => 3000}),
    #{status := running,
      config := #{idle_timeout := 3000}} = emqx_gateway:lookup(?GWNAME),

    ok = emqx_gateway:update(
           ?GWNAME, #{enable => false, idle_timeout => 4000}),
    #{status := stopped,
      config := #{idle_timeout := 4000}} = emqx_gateway:lookup(?GWNAME),

    ok = emqx_gateway:start(?GWNAME),
    #{status := running,
      config := #{idle_timeout := 4000}} = emqx_gateway:lookup(?GWNAME),

    {error, already_started} = emqx_gateway:start(?GWNAME),
    ok.
