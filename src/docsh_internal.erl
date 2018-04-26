-module(docsh_internal).

-export([lookup/3,
         merge/1]).

-export_type([key/0,
              item_kind/0]).

%% Internal documentation format.
%% Until 0.5.0 all `docsh_reader` modules convert to this format from their input.
%% Until 0.5.0 all `docsh_writer` modules convert from this format to desired output.
-type t() :: [{atom(), any()}].

-type key() :: module() | mfa() | {module(), name(), any}.
-type item_kind() :: moduledoc | doc | spec | type.

%% Function or type name.
-type name() :: atom().

-define(a2b(A), atom_to_binary(A, utf8)).
-define(a2l(A), atom_to_list(A)).
-define(i2b(I), integer_to_binary(I)).
-define(il2b(IOList), iolist_to_binary(IOList)).

%%
%%' Public
%%

-spec lookup(docsh_format:t(), key(), [item_kind()]) -> R when
      R :: {ok, binary()} | {not_found, docsh_format:error_message()}.
lookup({docsh_docs_v1, Docs}, Key, Opts) ->
    case fetch_features(Docs, Key, Opts) of
        [] ->
            {not_found, ?il2b(no_features(Key, Opts))};
        Features ->
            {ok, ?il2b(format_features(Features, key_to_arity(Key), Opts))}
    end;
lookup(Format, _Key, _Opts) ->
    {not_found, ?il2b(unrecognized_format(Format))}.

-spec merge([Info]) -> MergedInfo when
      Info :: docsh_internal:t(),
      MergedInfo :: docsh_internal:t().
merge([]) -> [];
merge([Info]) -> Info;
merge([Info1, Info2 | Rest]) ->
    case are_disjoint(Info1, Info2) of
        false -> error(not_disjoint, [Info1, Info2 | Rest]);
        true ->
            (module(Info1) =:= module(Info2)
             orelse error(different_modules, [Info1, Info2 | Rest])),
            merge([merge2(Info1, Info2) | Rest])
    end.

%%.
%%' Internal
%%

merge2(Info1, Info2) ->
    %% TODO: this might discard valuable module info from Info2
    Info1 ++ lists:keydelete(module, 1, Info2).

are_disjoint(Info1, Info2) ->
    Keys1 = proplists:get_keys(Info1) -- [module],
    Keys2 = proplists:get_keys(Info2) -- [module],
    Keys1 -- Keys2 == Keys1.

module(Info) ->
    {_, Props} = lists:keyfind(module, 1, Info),
    {_, Mod} = lists:keyfind(name, 1, Props),
    Mod.

-spec key_to_arity(key()) -> any | arity().
key_to_arity(M) when is_atom(M) -> any;
key_to_arity({_,_,A}) -> A.

fetch_features(Docs, Key, Opts) ->
    FlatDocs = flatten_docs(Docs),
    Features = filter_features(FlatDocs, Key, Opts),
    Arities = find_arities(Features),
    generate_headers(Key, Arities) ++ Features.

flatten_docs(Docs) ->
    F = fun ({moduledoc, _} = ModDoc) -> [ModDoc];
            ({docs, Functions}) ->
                [ {doc, Fun, Arity, Doc}
                  %% TODO: ultimately, we should use all these fields
                  || {{Fun, Arity}, _, _, _, Doc} <- Functions ];
            ({Kind, Functions}) ->
                [ {map_kind(Kind), Fun, Arity, Doc}
                  || {{Fun, Arity}, Doc} <- Functions ]
        end,
    lists:flatmap(F, Docs).

map_kind(docs) -> doc;
map_kind(specs) -> spec;
map_kind(types) -> type.

filter_features(FlatDocs, Mod, [moduledoc]) when is_atom(Mod) ->
    {moduledoc, {_, Doc}} = lists:keyfind(moduledoc, 1, FlatDocs),
    [{moduledoc, Mod, Doc}];
filter_features(FlatDocs, Key, FeatureKinds) ->
    {_Mod, Name, Arity} = case Key of
                              M when is_atom(M) -> {M, any, any};
                              {M, N, A} -> {M, N, A}
                          end,
    [ Feature || {Kind, ActualName, ActualArity, _} = Feature <- FlatDocs,
                 lists:member(Kind, FeatureKinds),
                 does_name_match(Name, ActualName),
                 does_arity_match(Arity, ActualArity) ].

does_name_match(any, _) -> true;
does_name_match(N, N) -> true;
does_name_match(_, _) -> false.

does_arity_match(any, _) -> true;
does_arity_match(A, A) -> true;
does_arity_match(_, _) -> false.

find_arities(Features) ->
    lists:usort([ A || {Kind, _, A, _} <- Features,
                       Kind == doc orelse Kind == spec ]).

generate_headers(Mod, _Arities) when is_atom(Mod) ->
    [];
generate_headers({Mod, Name, _}, Arities) ->
    [ header(Mod, Name, Arity) || Arity <- Arities ].

header(M, F, A) -> {header, M, F, A}.

format_features(Features, any, [type]) ->
    [ format_feature(F) || F <- Features ];
format_features(Features, any, Opts) ->
    [ format_features(FeatureGroup, Arity, Opts)
      || {Arity, FeatureGroup} <- sort_by_arity(group_by_arity(Features)) ];
format_features(Features, Arity, _Opts) when is_integer(Arity) ->
    [ format_feature(F) || F <- sort_features(Features) ].

sort_features(Features) ->
    Order = [moduledoc, type, header, spec, doc],
    [ F || Key <- Order, F <- [lists:keyfind(Key, 1, Features)], F /= false ].

format_feature({moduledoc, Mod, Doc}) ->
    io_lib:format("\n# ~s~n~n~s~n", [Mod, Doc]);
format_feature({header, M, F, A}) ->
    [$\n, format_mfa(M, F, A), "\n\n"];
format_feature({_Kind, _, _, Doc}) ->
    [Doc, $\n].

no_features(Key, Opts) ->
    io_lib:format("\ndocsh: no ~ts for ~ts\n\n",
                  [format_kinds(Opts), format_key(Key)]).

unrecognized_format(Format) ->
    io_lib:format("\ndocsh: ~ts is not recognized by ~ts - please report at "
                  "https://github.com/erszcz/docsh\n\n",
                  [element(1, Format), ?MODULE]).

format_kinds(Kinds) ->
    string:join([ ?a2l(K) || K <- Kinds ], "/").

format_key(M) when is_atom(M) -> ?a2b(M);
format_key({M, F, A}) -> format_mfa(M, F, A).

format_mfa(M, F, A) ->
    [?a2b(M), $:, ?a2b(F), $/, case A of any -> $*; _ -> ?i2b(A) end].

group_by_arity(Features) ->
    dict:to_list(docsh_lib:group_by(fun feature_arity/1, Features)).

feature_arity({moduledoc, _, _}) -> 0;
feature_arity({header, _, _, A}) -> A;
feature_arity({doc, _, A, _}) -> A;
feature_arity({spec, _, A, _}) -> A;
feature_arity({type, _, A, _}) -> A.

sort_by_arity(FeatureGroups) ->
    lists:sort(FeatureGroups).

%%. vim: foldmethod=marker foldmarker=%%',%%.
