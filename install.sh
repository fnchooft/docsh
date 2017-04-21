#!/usr/bin/env bash

set -e

HOME_ERLANG="$HOME/.erlang"
HOME_ERLANG_D="$HOME/.erlang.d"
HOME_USER_DEFAULT="$HOME_ERLANG_D/user_default.erl"

echo
echo "Installing docsh"
echo
echo "This install script will make docsh globally available in your"
echo "user environment."
echo "It will install the following files:"
echo
echo "  $HOME_ERLANG"
echo "  $HOME_USER_DEFAULT"
echo
echo "To know more about these files please refer to:"
echo
echo "  man erl - sections about 'The .erlang startup file'"
echo "            and 'user_default and shell_default'"
echo "  man shell_default - parts about user_default"
echo

read -p "Do you want to proceed? [y/N] " -n 1 -r
echo
echo

if [ ! x"$REPLY" = xy ]; then
    echo Nothing to do
    exit 0
fi

if [ -f "$HOME_ERLANG" ]; then
    echo "$HOME_ERLANG exists - aborting"
    exit 1
fi

if [ -f "$HOME_USER_DEFAULT" ]; then
    echo "$HOME_USER_DEFAULT exists - aborting"
    exit 2
fi


pushd $(dirname $0) > /dev/null
DOCSH_BASE=$PWD
popd > /dev/null

cd $DOCSH_BASE
./rebar3 compile
cd - > /dev/null

cat <<EOF > "$HOME_ERLANG"
proplists:is_defined(noshell, init:get_arguments()) == false andalso begin
    DocshBase = "$DOCSH_BASE",
    code:add_path(DocshBase ++ "/_build/default/lib/docsh/ebin"),
    io:format("Enabled docsh from: ~s\n", [DocshBase])
end.
code:load_abs(os:getenv("HOME") ++ "/.erlang.d/user_default").
EOF

mkdir -p "$HOME_ERLANG_D"
cd $HOME_ERLANG_D
cat <<EOF > $HOME_USER_DEFAULT
-module(user_default).
-include("docsh_user_default.hrl").
EOF
erlc -I $DOCSH_BASE/include $HOME_USER_DEFAULT > /dev/null
cd - > /dev/null

echo
echo "Ok, it's done!"

