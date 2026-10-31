#!/usr/bin/env bash
# Release gate: checks that Pianissimac cannot reach the network.
#   1. no network entitlement (com.apple.security.network.*) in the project or the signed app;
#   2. no networking API in the Swift sources;
#   3. no URL in the binary other than the score sources listed in ScoreSourcesView.swift,
#      which are only handed to the browser with openURL.
#
# Usage: scripts/check-offline.sh [path/to/Pianissimac.app]   (defaults to dist/Pianissimac.app if present)
# Steps 1 (signed app) and 3 need macOS and a built app; they are skipped otherwise.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-dist/Pianissimac.app}"
SOURCES=(Pianissimac Packages/PianissimacKit/Sources)
SCORE_SOURCES=Pianissimac/Features/Library/ScoreSourcesView.swift
status=0
fail() { echo "FAIL: $*"; status=1; }

# The only URLs the app may contain: the score sources opened in the browser.
allowed_urls=$(grep -oE 'https?://[^"]+' "$SCORE_SOURCES" | sort -u)

echo "==> 1. Entitlements"
if grep -n 'com\.apple\.security\.network' project.yml Pianissimac/Pianissimac.entitlements; then
  fail "network entitlement declared"
fi
if grep -n 'NSAppTransportSecurity\|NSAllowsArbitraryLoads' project.yml Pianissimac/Info.plist; then
  fail "App Transport Security exception declared"
fi
if [[ -d "$APP" ]] && command -v codesign >/dev/null; then
  entitlements=$(codesign -d --entitlements - "$APP" 2>/dev/null || true)
  if grep -q 'com.apple.security.network' <<<"$entitlements"; then
    fail "network entitlement in the signed app $APP"
  fi
  grep -q 'com.apple.security.app-sandbox' <<<"$entitlements" || fail "$APP is not sandboxed"
else
  echo "    (signed app check skipped: no $APP or no codesign)"
fi

echo "==> 2. Networking APIs in the sources"
NETWORK_API='\b(URLSession|URLRequest|NSURLConnection|NSURLSession|NWConnection|NWListener|NWBrowser|NWPathMonitor|NWEndpoint|CFSocket|CFStreamCreatePairWithSocket|CFHTTPMessage|WKWebView|WebView|SCNetworkReachability|getaddrinfo|gethostbyname)\b|^\s*import\s+(Network|WebKit|CFNetwork)\b|\bsocket\('
if grep -rnE "$NETWORK_API" "${SOURCES[@]}" --include='*.swift'; then
  fail "networking API used in the sources"
fi
# Remote URLs are only allowed in the score sources list.
if grep -rnE 'https?://' "${SOURCES[@]}" --include='*.swift' | grep -v "^$SCORE_SOURCES:"; then
  fail "remote URL outside $SCORE_SOURCES"
fi
# Those URLs must only be opened in the browser, never loaded by the app.
if grep -nE 'contentsOf:|dataTask|downloadTask|\.data\(from' "$SCORE_SOURCES"; then
  fail "$SCORE_SOURCES loads its URLs instead of opening them in the browser"
fi

echo "==> 3. URLs in the binary"
binary="$APP/Contents/MacOS/Pianissimac"
if [[ -f "$binary" ]] && command -v strings >/dev/null; then
  found=$(strings -a "$binary" | grep -oE 'https?://[^[:space:]"<>]+' | sort -u || true)
  unexpected=$(comm -23 <(echo "$found") <(echo "$allowed_urls") | sed '/^$/d')
  if [[ -n "$unexpected" ]]; then
    echo "$unexpected"
    fail "unexpected URL in $binary"
  fi
  echo "    URLs found: $(echo "$found" | sed '/^$/d' | wc -l | tr -d ' ') (all from $SCORE_SOURCES)"
else
  echo "    (binary check skipped: no $binary or no strings; run scripts/build-release.sh first)"
fi

if [[ $status -eq 0 ]]; then
  echo "Offline check passed."
fi
exit $status
