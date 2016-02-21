-module(ct_docsh).

-export([core_transform/2]).

-import(docsh_lib, [print/2]).

-spec core_transform(cerl:c_module(), _) -> cerl:c_module().
core_transform(Mod, _Opts) ->
    %print("core ast: ~p~n", [Mod]),
    %print("core: ~s~n", [core_pp:format(Mod)]),
    Addons = addons(Mod, templates()),
    Exports = cerl:module_exports(Mod),
    Defs = cerl:module_defs(Mod),
    After = cerl:update_c_module(Mod,
                                 cerl:module_name(Mod),
                                 exports(Addons, cerl:module_exports(Mod)),
                                 cerl:module_attrs(Mod),
                                 defs(Addons, cerl:module_defs(Mod))),
    %print("after: ~p~n", [After]),
    After.

addons(Mod, Templates) ->
    [h0(Mod, Templates),
     h2(Mod, Templates)].

h0(Mod, Templates) ->
    ProtoFName = cerl:c_fname(h, 1),
    ProtoF = get_proto(ProtoFName, Templates),
    FBody = cerl:c_apply(ProtoF, [cerl:module_name(Mod)]),
    F = cerl:c_fun([], FBody),
    FName = cerl:c_fname(h, 0),
    {FName, F}.

h2(Mod, Templates) ->
    ProtoFName = cerl:c_fname(h, 3),
    ProtoF = get_proto(ProtoFName, Templates),
    Vars = [cerl:c_var(docsh0), cerl:c_var(docsh1)],
    FBody = cerl:c_apply(ProtoF, [cerl:module_name(Mod)] ++ Vars),
    F = cerl:c_fun(Vars, FBody),
    FName = cerl:c_fname(h, 2),
    {FName, F}.

get_proto(FName, Templates) ->
    case lists:keyfind(FName, 1, Templates) of
        false -> error(not_found);
        {FName, CoreFun} -> CoreFun
    end.

exports(Addons, Exports) ->
    [ FName || {FName, _} <- Addons ] ++ Exports.

defs(Addons, Defs) ->
    Addons ++ Defs.

templates() ->
    {ok, _, CoreTemplate} = compile:file("src/docsh_rt.erl", [to_core, binary]),
    cerl:module_defs(CoreTemplate).