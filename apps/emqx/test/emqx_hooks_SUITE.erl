%%--------------------------------------------------------------------
%% Copyright (c) 2018-2022 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_hooks_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("eunit/include/eunit.hrl").

all() -> emqx_common_test_helpers:all(?MODULE).

% t_lookup(_) ->
%     error('TODO').

% t_run_fold(_) ->
%     error('TODO').

% t_run(_) ->
%     error('TODO').

% t_del(_) ->
%     error('TODO').

% t_add(_) ->
%     error('TODO').
    
t_add_put_del_hook(_) ->
    {ok, _} = emqx_hooks:start_link(),
    ok = emqx:hook(test_hook, {?MODULE, hook_fun1, []}),
    ok = emqx:hook(test_hook, {?MODULE, hook_fun2, []}),
    ?assertEqual({error, already_exists},
                 emqx:hook(test_hook, {?MODULE, hook_fun2, []})),
    Callbacks0 = [{callback, {?MODULE, hook_fun1, []}, undefined, 0},
                  {callback, {?MODULE, hook_fun2, []}, undefined, 0}],
    ?assertEqual(Callbacks0, emqx_hooks:lookup(test_hook)),

    ok = emqx_hooks:put(test_hook, {?MODULE, hook_fun1, [test]}),
    ok = emqx_hooks:put(test_hook, {?MODULE, hook_fun2, [test]}),
    Callbacks1 = [{callback, {?MODULE, hook_fun1, [test]}, undefined, 0},
                  {callback, {?MODULE, hook_fun2, [test]}, undefined, 0}],
    ?assertEqual(Callbacks1, emqx_hooks:lookup(test_hook)),

    ok = emqx:unhook(test_hook, {?MODULE, hook_fun1}),
    ok = emqx:unhook(test_hook, {?MODULE, hook_fun2}),
    timer:sleep(200),
    ?assertEqual([], emqx_hooks:lookup(test_hook)),

    ok = emqx:hook(emqx_hook, {?MODULE, hook_fun8, []}, 8),
    ok = emqx:hook(emqx_hook, {?MODULE, hook_fun2, []}, 2),
    ok = emqx:hook(emqx_hook, {?MODULE, hook_fun10, []}, 10),
    ok = emqx:hook(emqx_hook, {?MODULE, hook_fun9, []}, 9),
    Callbacks2 = [{callback, {?MODULE, hook_fun10, []}, undefined, 10},
                  {callback, {?MODULE, hook_fun9, []}, undefined, 9},
                  {callback, {?MODULE, hook_fun8, []}, undefined, 8},
                  {callback, {?MODULE, hook_fun2, []}, undefined, 2}],
    ?assertEqual(Callbacks2, emqx_hooks:lookup(emqx_hook)),

    ok = emqx_hooks:put(emqx_hook, {?MODULE, hook_fun8, [test]}, 3),
    ok = emqx_hooks:put(emqx_hook, {?MODULE, hook_fun2, [test]}, 4),
    ok = emqx_hooks:put(emqx_hook, {?MODULE, hook_fun10, [test]}, 1),
    ok = emqx_hooks:put(emqx_hook, {?MODULE, hook_fun9, [test]}, 2),
    Callbacks3 = [{callback, {?MODULE, hook_fun2, [test]}, undefined, 4},
                  {callback, {?MODULE, hook_fun8, [test]}, undefined, 3},
                  {callback, {?MODULE, hook_fun9, [test]}, undefined, 2},
                  {callback, {?MODULE, hook_fun10, [test]}, undefined, 1}],
    ?assertEqual(Callbacks3, emqx_hooks:lookup(emqx_hook)),

    ok = emqx:unhook(emqx_hook, {?MODULE, hook_fun2, [test]}),
    ok = emqx:unhook(emqx_hook, {?MODULE, hook_fun8, [test]}),
    ok = emqx:unhook(emqx_hook, {?MODULE, hook_fun9, [test]}),
    ok = emqx:unhook(emqx_hook, {?MODULE, hook_fun10, [test]}),
    timer:sleep(200),
    ?assertEqual([], emqx_hooks:lookup(emqx_hook)),
    ok = emqx_hooks:stop().

t_run_hooks(_) ->
    {ok, _} = emqx_hooks:start_link(),
    ok = emqx:hook(foldl_hook, {?MODULE, hook_fun3, [init]}),
    ok = emqx:hook(foldl_hook, {?MODULE, hook_fun4, [init]}),
    ok = emqx:hook(foldl_hook, {?MODULE, hook_fun5, [init]}),
    [r5,r4] = emqx:run_fold_hook(foldl_hook, [arg1, arg2], []),
    [] = emqx:run_fold_hook(unknown_hook, [], []),

    ok = emqx:hook(foldl_hook2, {?MODULE, hook_fun9, []}),
    ok = emqx:hook(foldl_hook2, {?MODULE, hook_fun10, []}),
    [r9] = emqx:run_fold_hook(foldl_hook2, [arg], []),

    ok = emqx:hook(foreach_hook, {?MODULE, hook_fun6, [initArg]}),
    {error, already_exists} = emqx:hook(foreach_hook, {?MODULE, hook_fun6, [initArg]}),
    ok = emqx:hook(foreach_hook, {?MODULE, hook_fun7, [initArg]}),
    ok = emqx:hook(foreach_hook, {?MODULE, hook_fun8, [initArg]}),
    ok = emqx:run_hook(foreach_hook, [arg]),

    ok = emqx:hook(foreach_filter1_hook, {?MODULE, hook_fun1, []}, {?MODULE, hook_filter1, []}, 0),
    ?assertEqual(ok, emqx:run_hook(foreach_filter1_hook, [arg])), %% filter passed
    ?assertEqual(ok, emqx:run_hook(foreach_filter1_hook, [arg1])), %% filter failed

    ok = emqx:hook(foldl_filter2_hook, {?MODULE, hook_fun2, []}, {?MODULE, hook_filter2, [init_arg]}),
    ok = emqx:hook(foldl_filter2_hook, {?MODULE, hook_fun2_1, []}, {?MODULE, hook_filter2_1, [init_arg]}),
    ?assertEqual(3, emqx:run_fold_hook(foldl_filter2_hook, [arg], 1)),
    ?assertEqual(2, emqx:run_fold_hook(foldl_filter2_hook, [arg1], 1)),

    ok = emqx_hooks:stop().

t_uncovered_func(_) ->
    {ok, _} = emqx_hooks:start_link(),
    Pid = erlang:whereis(emqx_hooks),
    gen_server:call(Pid, test),
    gen_server:cast(Pid, test),
    Pid ! test,
    ok = emqx_hooks:stop().

%%--------------------------------------------------------------------
%% Hook fun
%%--------------------------------------------------------------------

hook_fun1(arg) -> ok;
hook_fun1(_) -> error.

hook_fun2(arg) -> ok;
hook_fun2(_) -> error.

hook_fun2(_, Acc) -> {ok, Acc + 1}.
hook_fun2_1(_, Acc) -> {ok, Acc + 1}.

hook_fun3(arg1, arg2, _Acc, init) -> ok.
hook_fun4(arg1, arg2, Acc, init)  -> {ok, [r4 | Acc]}.
hook_fun5(arg1, arg2, Acc, init)  -> {ok, [r5 | Acc]}.

hook_fun6(arg, initArg) -> ok.
hook_fun7(arg, initArg) -> ok.
hook_fun8(arg, initArg) -> ok.

hook_fun9(arg, Acc)  -> {stop, [r9 | Acc]}.
hook_fun10(arg, Acc) -> {stop, [r10 | Acc]}.

hook_filter1(arg) -> true;
hook_filter1(_) -> false.

hook_filter2(arg, _Acc, init_arg) -> true;
hook_filter2(_, _Acc, _IntArg) -> false.

hook_filter2_1(arg, _Acc, init_arg)  -> true;
hook_filter2_1(arg1, _Acc, init_arg) -> true;
hook_filter2_1(_, _Acc, _IntArg)     -> false.

