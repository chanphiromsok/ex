#!/usr/bin/env bash
# Tsung 1.8.0 crashes on Erlang/OTP 27+ when a response is chunked (all our API responses are):
#   'function not exported' httpd_util:hexlist_to_integer/1
# OTP removed httpd_util:hexlist_to_integer/integer_to_hexlist. This rebuilds the three Tsung
# modules that call them with erlang:list_to_integer/2 and integer_to_list/2 instead.
# Run once after `brew install tsung` (or after a brew reinstall/upgrade). Undo: brew reinstall tsung
set -euo pipefail

T="$(brew --prefix tsung)/lib/tsung/tsung-1.8.0"
W="$(mktemp -d)"
cp "$T"/src/{ts_http,ts_http_common,ts_digest}.erl "$W"
sed -i '' 's/httpd_util:hexlist_to_integer(binary_to_list(Digits))/erlang:list_to_integer(binary_to_list(Digits), 16)/' "$W/ts_http.erl"
sed -i '' 's/httpd_util:integer_to_hexlist(\([A-Za-z]*\))/erlang:integer_to_list(\1, 16)/' "$W/ts_http_common.erl" "$W/ts_digest.erl"
(cd "$W" && erlc -I "$T/include" -I "$T/src" ts_http.erl ts_http_common.erl ts_digest.erl 2> /dev/null)
for m in ts_http ts_http_common ts_digest; do
  chmod u+w "$T/ebin/$m.beam"
  cp "$W/$m.beam" "$T/ebin/$m.beam"
  chmod a-w "$T/ebin/$m.beam"
done
rm -rf "$W"
echo "Tsung patched for OTP $(erl -noshell -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().')"
