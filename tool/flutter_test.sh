#!/usr/bin/env bash
set -euo pipefail

# Flutter's test listener runs on localhost. If HTTP(S)_PROXY / ALL_PROXY are
# set without NO_PROXY, Dart WebSocket.connect can route that localhost
# handshake through the proxy and fail with HTTP 400 instead of upgrading.
localhost_no_proxy="localhost,127.0.0.1,::1"
if [[ -n "${NO_PROXY:-}" ]]; then
  export NO_PROXY="$localhost_no_proxy,$NO_PROXY"
else
  export NO_PROXY="$localhost_no_proxy"
fi
if [[ -n "${no_proxy:-}" ]]; then
  export no_proxy="$localhost_no_proxy,$no_proxy"
else
  export no_proxy="$localhost_no_proxy"
fi

exec flutter test "$@"
