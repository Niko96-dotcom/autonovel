#!/usr/bin/env bash
# Distribution readiness probe for AutoNovel Studio (packaging-notarization light).
# Inspects an exported .app; does not Developer ID-sign, notarize, or staple.
# Local debug continues to use script/build_and_run.sh (ad-hoc only).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/dist/AutoNovelStudio.app}"
APP_NAME="AutoNovelStudio"
EXPECTED_ID="org.nousresearch.autonovelstudio"

usage() {
  echo "usage: $0 [path/to/AutoNovelStudio.app]" >&2
  echo "  Read-only packaging / notarization readiness report." >&2
  echo "  Does not re-sign, notarize, or change the local ad-hoc build path." >&2
}

case "${1:-}" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Missing app bundle: $APP_BUNDLE" >&2
  echo "Build first: ./script/build_and_run.sh --build-only" >&2
  exit 2
fi

BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
RESOURCES="$APP_BUNDLE/Contents/Resources"

echo "=== AutoNovel Studio distribution readiness (light) ==="
echo "Artifact: $APP_BUNDLE"
echo "Goal: report packaging / notarization prerequisites; local ad-hoc runs do not need notarization."
echo

bundle_ok=1
echo "-- Bundle structure"
if [[ -f "$INFO_PLIST" && -x "$BINARY" && -d "$RESOURCES" ]]; then
  echo "OK: Info.plist, MacOS/$APP_NAME, Resources/"
else
  echo "FAIL: incomplete app bundle layout"
  bundle_ok=0
fi

if [[ -f "$INFO_PLIST" ]]; then
  bundle_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$INFO_PLIST" 2>/dev/null || true)"
  exec_name="$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST" 2>/dev/null || true)"
  pkg_type="$(/usr/bin/plutil -extract CFBundlePackageType raw -o - "$INFO_PLIST" 2>/dev/null || true)"
  echo "  CFBundleIdentifier=$bundle_id (expect $EXPECTED_ID)"
  echo "  CFBundleExecutable=$exec_name (expect $APP_NAME)"
  echo "  CFBundlePackageType=$pkg_type (expect APPL)"
  if [[ "$bundle_id" != "$EXPECTED_ID" || "$exec_name" != "$APP_NAME" || "$pkg_type" != "APPL" ]]; then
    bundle_ok=0
  fi
fi

# Nested helpers / frameworks — Studio ships a flat SwiftPM executable today.
nested_count="$(find "$APP_BUNDLE/Contents" \( -name '*.framework' -o -name '*.dylib' -o -path '*/Helpers/*' \) 2>/dev/null | wc -l | tr -d ' ')"
echo "  Nested frameworks/helpers/dylibs: $nested_count"
echo

echo "-- Signing & runtime (on-disk)"
codesign_dv="$(/usr/bin/codesign -dvvv --entitlements - "$APP_BUNDLE" 2>&1 || true)"
printf '%s\n' "$codesign_dv" | /usr/bin/grep -E '^(Executable|Identifier|Format|CodeDirectory|Signature|TeamIdentifier|flags=)' || true

adhoc=0
if printf '%s\n' "$codesign_dv" | /usr/bin/grep -Eq 'Signature=adhoc|flags=0x2\(adhoc\)'; then
  adhoc=1
  echo "Class: ad-hoc (local development)"
fi

runtime=0
if printf '%s\n' "$codesign_dv" | /usr/bin/grep -Eq 'flags=0x10000\(runtime\)|flags=.*\(runtime\)'; then
  runtime=1
  echo "Hardened runtime: present"
else
  echo "Hardened runtime: absent (required for notarized distribution)"
fi

integrity_ok=1
if /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE" 2>/dev/null; then
  echo "codesign --verify --deep --strict: OK"
else
  echo "codesign --verify --deep --strict: FAIL"
  integrity_ok=0
fi

echo
echo "-- Gatekeeper probe (distribution trust ≠ local launch)"
SPCTL_BIN="$(command -v spctl || true)"
if [[ -z "$SPCTL_BIN" ]]; then
  echo "spctl: not found on PATH (skip Gatekeeper probe)"
else
  spctl_out="$("$SPCTL_BIN" -a -vv "$APP_BUNDLE" 2>&1 || true)"
  printf '%s\n' "$spctl_out"
  if printf '%s\n' "$spctl_out" | /usr/bin/grep -qi 'accepted'; then
    echo "spctl: accepted"
  else
    echo "spctl: rejected (expected for ad-hoc / unsigned-for-distribution; not a local debug failure)"
  fi
fi

echo
echo "-- Host signing identities (availability only; unused by local build)"
identity_list="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)"
printf '%s\n' "$identity_list"
dev_id=0
if printf '%s\n' "$identity_list" | /usr/bin/grep -q 'Developer ID Application:'; then
  dev_id=1
  echo "Developer ID Application: found on this Mac (opt-in for shipping only)"
else
  echo "Developer ID Application: not found"
fi

echo
echo "-- Notary tooling (presence only; no submit)"
if /usr/bin/xcrun --find notarytool >/dev/null 2>&1; then
  echo "notarytool: available via xcrun"
else
  echo "notarytool: not found (install Xcode CLT / Xcode)"
fi
# Do not invent or print credentials; only note that a profile is required to submit.
echo "Notary credentials: not checked (configure a notarytool keychain profile before any submit)"

echo
echo "-- Verdict"
if [[ "$bundle_ok" -ne 1 || "$integrity_ok" -ne 1 ]]; then
  echo "Local package: BROKEN — fix bundle/signing integrity before any distribution work."
  echo "Distribution-ready: NO"
  echo "Top missing prerequisite: valid staged app bundle with passing codesign --verify."
  echo "Next: ./script/build_and_run.sh --build-only && $0"
elif [[ "$adhoc" -eq 1 || "$runtime" -eq 0 ]]; then
  echo "Local package: OK for ad-hoc debug (./script/build_and_run.sh)."
  echo "Distribution-ready: NO"
  if [[ "$adhoc" -eq 1 ]]; then
    echo "Top missing prerequisite: Developer ID Application signature with hardened runtime (not ad-hoc)."
  else
    echo "Top missing prerequisite: hardened runtime (--options runtime) on a Developer ID signature."
  fi
  if [[ "$dev_id" -eq 1 ]]; then
    echo "Note: a Developer ID Application identity exists on this host but is intentionally unused by the local build path."
  else
    echo "Note: no Developer ID Application identity on this host — cannot notarize until one is installed."
  fi
  echo "Next validation (when shipping, not for ordinary local runs):"
  echo "  1. codesign -dvvv --entitlements - \"$APP_BUNDLE\""
  echo "  2. codesign --verify --deep --strict \"$APP_BUNDLE\""
  echo "  3. spctl -a -vv \"$APP_BUNDLE\""
  echo "  4. (distribution only) re-sign with Developer ID + hardened runtime, then notarytool submit + staple"
else
  # Non-adhoc + hardened runtime on disk — still may lack notarization/staple.
  echo "Signing class: non-adhoc with hardened runtime."
  echo "Distribution-ready: NO (notarization / staple not performed by this light helper)."
  echo "Top missing prerequisite: notarytool submit + staple, then confirm spctl accepts."
  echo "Next: xcrun notarytool submit … && xcrun stapler staple \"$APP_BUNDLE\" && spctl -a -vv \"$APP_BUNDLE\""
fi

echo
echo "Guardrail: notarization is not required for ordinary local debug runs."

# Exit: structural/integrity failure → 1; readiness gaps alone → 0 (probe succeeded).
if [[ "$bundle_ok" -ne 1 || "$integrity_ok" -ne 1 ]]; then
  exit 1
fi
exit 0
