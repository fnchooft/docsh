%% @doc
%% Welcome to docsh, a documentation engine for the Erlang shell.
%% This project provides a number of helpers for accessing module and function
%% doc comments, function specs and exported types.
%%
%% If you want your project to have embedded documentation,
%% use `rebar3_docsh' plugin.
%% If you want to browse some docs first, read on.
%%
%% To access this documentation you've quite likely typed:
%%
%% ```
%% h(docsh).
%% '''
%%
%% `h/{1,2,3}' is the most generic invocation of docsh.
%% `h/1' prints documentation for a given module (as shown above) or function:
%%
%% ```
%% h(fun lists:keyfind/3).
%% '''
%%
%% `h/{2,3}' are limited to functions.
%% `h/2' displays information about all functions of the given name from
%% a particular module, while `h/3' also takes the expected function arity:
%%
%% ```
%% h(proplists, get_value).
%% h(proplists, get_value, 3).
%% '''
%%
%% `s/{1,2,3}' is the helper to use if you're only interested in function specs,
%% not their full documentation:
%%
%% ```
%% s(fun proplists:get_value/3).
%% s(proplists, get_value).
%% s(proplists, get_value, 3).
%% '''
%%
%% `t/{2,3}' is the helper for printing types exported from modules:
%%
%% ```
%% t(gen_tcp, connect_option).
%% t(gen_udp, socket).
%% '''
%%
%% If you want to use the helpers in erl you'll be set up by docsh's install script.
%% It will install a `user_default' module enabling the shell extensions.
%% See https://github.com/erszcz/docsh/README.md if unsure about
%% the installation steps or what `user_default' is.
%%
%% If you want to use docsh shell extensions in `rebar3 shell',
%% please refer to `script/docsh_rebar3_shell.escript'.
%%
%% If you want to call docsh as a library, please refer to `docsh_erl'.
%% @end

-module(docsh).

%% Escript API
-export([main/1]).

%% Scripting API
-export([activated/1,
         version/0,
         load_shell_extensions/0]).

-export_type([external/0]).

-import(docsh_lib, [print/2, print/3]).

-include("docsh_stacktrace.hrl").

%% External documentation format as described in EEP-48:
%% http://erlang.org/eep/eeps/eep-0048.html
-type external() :: any().

%%
%% Escript API
%%

-spec main([string()]) -> ok.
main(Args) ->
    process_args(Args, commands()).

%%
%% Scripting API
%%

-spec activated(path | user_default) -> ok.
activated(path) ->
    print("Enabled docsh ~s from: ~s\n",
          [docsh:version(), code:lib_dir(?MODULE)]);
activated(user_default) ->
    print("Call h(docsh) for interactive help.\n\n", []).

-spec version() -> string().
version() ->
    AppFile = filename:join([code:lib_dir(?MODULE), "ebin/docsh.app"]),
    {ok, [{_, docsh, AppSpec}]} = file:consult(AppFile),
    case lists:keyfind(vsn, 1, AppSpec) of
        false -> erlang:error({version_not_available, AppSpec});
        {vsn, V} -> V
    end.

-spec load_shell_extensions() -> ok.
load_shell_extensions() ->
    {ok, B} = docsh_beam:from_loaded_module(docsh_user_default),
    Forms = docsh_beam:abstract_code(B),
    NewForms = lists:map(fun ({attribute,_,module,_}) -> {attribute,1,module,user_default};
                             (F)                      -> F end, Forms),
    {ok, Mod, ModBin} = compile:forms(NewForms),
    {module, Mod} = code:load_binary(Mod, "docsh_user_default.beam", ModBin),
    ok.

%%
%% Helpers
%%

commands() ->
    [ {"diff BEAMFile1 BEAMFile2", fun diff/1},
      {"help",                     fun usage/1} ].

diff(["diff", BEAM1, BEAM2]) ->
    'try'(fun () -> Diff = docsh_lib:beam_diff(BEAM1, BEAM2),
                    print("~p~n", [Diff]) end).

usage(_) ->
    usage(),
    erlang:halt(1).

process_args(Args, Opts) ->
    lists:foldl(fun process_arg/2, {next, Args}, Opts),
    ok.

process_arg({_Desc, _}, done) -> done;
process_arg({_Desc, F}, {next, Args}) ->
    case catch erlang:apply(F, [Args]) of
        {'EXIT', {function_clause, _}} -> {next, Args};
        _ -> done
    end.

'try'(F) ->
    try
        F()
    catch ?STACKTRACE(_, R, Stacktrace)
        print(standard_error, "~s: ~s~n~s~n",
              [progname(), docsh_lib:format_error(R), Stacktrace]),
        erlang:halt(2)
    end.

usage() ->
    print(standard_error,
          "usage: ~s", [ [ [padding(I), progname(), " ", Desc, "\n"]
                           || {I, {Desc, _}} <- enum(commands()) ] ]).

padding(1) -> "";
padding(_) -> "       ".

enum(List) -> lists:zip(lists:seq(1, length(List)), List).

progname() ->
    filename:basename(hd(init:get_plain_arguments())).
