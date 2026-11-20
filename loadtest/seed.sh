#!/usr/bin/env bash
# Fills an EMPTY server with the data the Tsung scenario needs, and writes the user lists Tsung reads.
#
#   BASE=http://159.223.95.98 ADMIN_LOGIN=admin@gmail.com ADMIN_PASSWORD='...' ./seed.sh
#
# Creates: price per kg, 2 size classes, 1 sale item, STATIONS stations (one Location each), Routes
# between every pair, STAFF staff users + 1 supervisor per station. Run it once; run it again only
# after `uat reset db`, or you get duplicates.
#
# Why 100 staff: the server allows 5 sign-ins per account per 15 min. The full Tsung run starts ~400
# sessions, so each account must be reused at most ~4 times. Fewer accounts = 429s.
set -euo pipefail

BASE="${BASE:?set BASE, e.g. http://159.223.95.98}"
ADMIN_LOGIN="${ADMIN_LOGIN:?set ADMIN_LOGIN}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:?set ADMIN_PASSWORD}"
STATIONS="${STATIONS:-10}"
STAFF="${STAFF:-10}"
USER_PASSWORD="${USER_PASSWORD:-LoadTest-$(openssl rand -hex 4)}"
cd "$(dirname "$0")"

CT='content-type: application/vnd.api+json'

api() { # api METHOD PATH [JSON] -> prints the response body; fails on a non-2xx status
  local out code
  out="$(curl -sS -X "$1" "$BASE/api/v1$2" -H "$CT" ${TOKEN:+-H "authorization: Bearer $TOKEN"} ${3:+-d "$3"} -w '\n%{http_code}')"
  code="${out##*$'\n'}"
  out="${out%$'\n'*}"
  if [[ "$code" != 2* ]]; then echo "FAILED $1 $2 -> $code: $out" >&2; exit 1; fi
  printf '%s' "$out"
}
# Every body is built by jq from --arg values, never by hand-quoted JSON: macOS /bin/bash 3.2
# brace-expands "{...,...}" inside nested "$( ... )" and splits the JSON apart.
body() { jq -nc --arg t "$1" --argjson a "$2" '{data: {type: $t, attributes: $a}}'; }
named() { # named EN KM [extra jq args...] [extra jq object]
  local en="$1" km="$2"; shift 2
  jq -nc --arg en "$en" --arg km "$km" "$@"
}

TOKEN=""
TOKEN="$(api POST /users/sign-in "$(body user "$(jq -nc --arg l "$ADMIN_LOGIN" --arg p "$ADMIN_PASSWORD" '{login: $l, password: $p}')")" | jq -r .meta.token)"
echo "signed in as $ADMIN_LOGIN"

attrs="$(jq -nc '{price_per_kg: {amount: "2000", currency: "KHR"}}')"
api POST /pricing/price-per-kg "$(body pricing-setting "$attrs")" > /dev/null

attrs="$(named 'Small box' 'ប្រអប់តូច' '{name_en: $en, name_km: $km, price: {amount: "5000", currency: "KHR"}}')"
small="$(api POST /size-classes "$(body size-class "$attrs")" | jq -r .data.id)"
attrs="$(named 'Large box' 'ប្រអប់ធំ' '{name_en: $en, name_km: $km, price: {amount: "12000", currency: "KHR"}}')"
api POST /size-classes "$(body size-class "$attrs")" > /dev/null
attrs="$(named 'Packing tape' 'ស្កុត' '{name_en: $en, name_km: $km, unit_price: {amount: "1000", currency: "KHR"}}')"
api POST /sale-items "$(body sale-item "$attrs")" > /dev/null
echo "pricing set"

locations=()
stations=()
for i in $(seq 1 "$STATIONS"); do
  attrs="$(named "LT City $i" "ទីក្រុង $i" '{name_en: $en, name_km: $km}')"
  loc="$(api POST /locations "$(body location "$attrs")" | jq -r .data.id)"
  attrs="$(named "LT Station $i" "ស្ថានីយ $i" --arg l "$loc" '{name_en: $en, name_km: $km, location_id: $l}')"
  st="$(api POST /stations "$(body station "$attrs")" | jq -r .data.id)"
  locations+=("$loc")
  stations+=("$st")
done
echo "$STATIONS stations created"

for from in "${locations[@]}"; do
  for to in "${locations[@]}"; do
    [ "$from" = "$to" ] && continue
    attrs="$(jq -nc --arg o "$from" --arg d "$to" '{origin_location_id: $o, destination_location_id: $d}')"
    api POST /routes "$(body route "$attrs")" > /dev/null
  done
done
echo "routes created"

user() { # user ROLE PHONE STATION
  jq -nc --arg r "$1" --arg ph "$2" --arg s "$3" --arg pw "$USER_PASSWORD" \
    '{role: $r, phone: $ph, station_id: $s, password: $pw, password_confirmation: $pw}'
}

# staff.csv: login;password;destination station (another station);size class
: > staff.csv
: > supervisors.csv
for i in $(seq 1 "$STATIONS"); do
  st="${stations[$((i - 1))]}"
  dest="${stations[$((i % STATIONS))]}"
  for j in $(seq 1 "$STAFF"); do
    phone="$(printf '016%02d%04d' "$i" "$j")"
    api POST /users "$(body user "$(user staff "$phone" "$st")")" > /dev/null
    echo "$phone;$USER_PASSWORD;$dest;$small" >> staff.csv
  done
  phone="$(printf '017%02d0001' "$i")"
  api POST /users "$(body user "$(user supervisor "$phone" "$st")")" > /dev/null
  echo "$phone;$USER_PASSWORD" >> supervisors.csv
done
echo "$((STATIONS * STAFF)) staff + $STATIONS supervisors created -> staff.csv, supervisors.csv"
