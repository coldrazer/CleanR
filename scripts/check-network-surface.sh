#!/bin/bash
# check-network-surface.sh
#
# Verifies the SHIPPED BINARY's network surface matches what the README claims:
# the only networking class it imports is URLSession, the only URLs compiled in
# are the two disclosed update endpoints, and there is no tracker, analytics, or
# crash-reporter SDK anywhere in it.
#
# The point (raised by a reviewer): the repo and the installed binary are two
# different artifacts, so grepping the source proves nothing about the build on
# a user's disk. This inspects the binary itself, the same thing a user can run
# with `nm -u` / `strings` after `brew install`. It runs in CI on every PR so a
# hidden network path or a snuck-in SDK fails the build before it can ship.
#
# Usage: scripts/check-network-surface.sh [path-to-binary]
#   Defaults to the SPM build, then the installed app.

set -euo pipefail

BIN="${1:-}"
if [ -z "$BIN" ]; then
    for cand in \
        ".build/release/CleanR" \
        ".build/debug/CleanR" \
        "/Applications/CleanR.app/Contents/MacOS/CleanR"; do
        if [ -f "$cand" ]; then BIN="$cand"; break; fi
    done
fi
if [ -z "$BIN" ] || [ ! -f "$BIN" ]; then
    echo "::error::check-network-surface: no binary found to inspect (pass a path)"
    exit 1
fi
echo "Inspecting network surface of: $BIN"

# Snapshot the symbol table and strings once, then match against those. Grepping
# the pipelines directly would race `grep -q`'s early exit against SIGPIPE under
# `set -o pipefail` and mis-report matches.
SYMS="$(nm -u "$BIN" 2>/dev/null || true)"
STRS="$(strings -a "$BIN" 2>/dev/null || true)"

fail=0

# 1) Low-level networking symbols would mean a channel that bypasses the
#    disclosed, URLSession-based update checks. None should be present.
BANNED_SYMBOLS='NWConnection|NWBrowser|nw_connection|nw_endpoint|CFSocket|CFStreamCreatePairWithSocketToHost|CFReadStreamCreate|CFWriteStreamCreate'
sym_hits="$(grep -iE "$BANNED_SYMBOLS" <<<"$SYMS" | sort -u || true)"
if [ -n "$sym_hits" ]; then
    echo "::error::Unexpected low-level networking symbols:"
    echo "$sym_hits"
    fail=1
fi

# 2) Tracker / analytics / crash-reporter endpoints.
#
#    Matched only against URL-shaped strings, never the whole binary. CleanR
#    ships a table of *third-party* leftover directories it can clean, and some
#    of them are named after analytics SDKs (`~/Library/Caches/Amplitude`,
#    `~/Library/Caches/com.crashlytics`). Those are paths on the user's disk
#    that the uninstaller removes from other apps, not endpoints CleanR talks
#    to, and substring-matching the whole binary turned them into false
#    failures. A tracker that actually shipped here would appear as a URL (2),
#    as a linked SDK class (3), or as an undisclosed endpoint (4).
BANNED_HOSTS='sentry\.io|mixpanel|firebase|firebaseio|google-analytics|googletagmanager|doubleclick|segment\.(io|com)|amplitude\.com|bugsnag|crashlytics|datadoghq|posthog\.app|appcenter\.ms|adjust\.com|appsflyer|flurry|umeng'
URL_TOKENS="$(grep -oE 'https?://[^ "[:cntrl:]]+' <<<"$STRS" | sort -u || true)"
host_hits="$(grep -iE "$BANNED_HOSTS" <<<"$URL_TOKENS" | sort -u || true)"
if [ -n "$host_hits" ]; then
    echo "::error::Tracker/analytics endpoint found in binary:"
    echo "$host_hits"
    fail=1
fi

# 3) A linked tracker SDK is the stronger signal: it can phone home to a host
#    that is not on the denylist above. ObjC class references survive linking,
#    so a snuck-in Firebase/Sentry/Amplitude framework shows up here even when
#    its endpoints are obfuscated in string data.
#
#    Match on the class NAME, anchored at its start, not as a loose substring:
#    these frameworks ship under short prefixes (FIR* for Firebase, AMP* for
#    Amplitude, MSAC* for App Center, BSG* for Bugsnag) that a vendor-word-only
#    grep misses entirely.
CLASS_NAMES="$(grep -oE '_OBJC_(META)?CLASS_\$_[A-Za-z0-9_]+' <<<"$SYMS" | sed 's/.*\$_//' | sort -u || true)"
BANNED_SDK_CLASSES='^(Sentry|SBInstance|FIR|Crashlytics|CLS(Log|Report|Session)|Mixpanel|MP(Event|Instance)|GAI|Bugsnag|BSG|DataDog|DD(Log|Trace)|PostHog|MSAC|MSCR|AppsFlyer|Flurry|UMeng|Amplitude|AMP(Track|Session|Instance|Configuration)|Segment|SEGPayload|Matomo|Piwik|NewRelic|Instabug|Telemetry(Deck|Client))'
sdk_hits="$(grep -E "$BANNED_SDK_CLASSES" <<<"$CLASS_NAMES" | sort -u || true)"
if [ -n "$sdk_hits" ]; then
    echo "::error::Tracker/analytics/crash-reporter SDK class linked into the binary:"
    echo "$sdk_hits"
    fail=1
fi

# 4) Allowlist the disclosed surface. The denylist alone is not enough: a new
#    telemetry host that is not on the banned list would pass it silently. The
#    README promises these exact endpoints and nothing else, so anything
#    outside this set is a regression against that promise.
ALLOWED_URLS='https://api.github.com/repos/coldrazer/CleanR/releases/latest
https://buymeacoffee.com/cleanus
https://formulae.brew.sh/api/cask/cleanr.json
https://github.com/coldrazer/CleanR
https://github.com/coldrazer/CleanR/issues/new/choose
https://github.com/coldrazer/CleanR/releases'
unknown_urls="$(comm -23 <(printf '%s\n' "$URL_TOKENS" | sed '/^$/d') \
                         <(printf '%s\n' "$ALLOWED_URLS" | sort -u) || true)"
if [ -n "$unknown_urls" ]; then
    echo "::error::Undisclosed URL compiled into the binary (add it to the README and this allowlist, or remove it):"
    echo "$unknown_urls"
    fail=1
fi

# 5) Sanity: the two disclosed update endpoints should be present.
for endpoint in \
    "api.github.com/repos/coldrazer/CleanR/releases/latest" \
    "formulae.brew.sh/api/cask/cleanr.json"; do
    if ! grep -qF "$endpoint" <<<"$URL_TOKENS"; then
        echo "::warning::expected update endpoint not found in binary: $endpoint"
    fi
done

# 6) Print the full surface for the record (shows up in CI logs every run).
echo "--- Networking symbols imported (expect only NSURLSession) ---"
grep -iE 'URLSession|URLConnection|CFNetwork|NWConnection|CFSocket|CFStream' <<<"$SYMS" | sort -u || echo "(none)"
echo "--- URLs compiled into the binary ---"
grep -iE 'https?://' <<<"$STRS" | sort -u || echo "(none)"

if [ "$fail" -ne 0 ]; then
    echo "::error::Network-surface check FAILED (see above)."
    exit 1
fi
echo "Network-surface check passed: only URLSession, only the disclosed endpoints."
