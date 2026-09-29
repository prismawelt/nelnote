#!/usr/bin/env bash
set -euo pipefail

NEL_APP="build/Build/Products/Release-iphoneos/NelNote.app"
NEL_EXTENSION="$NEL_APP/PlugIns/NelNoteWidgets.appex"
test -d "$NEL_APP"
test -d "$NEL_EXTENSION"
test -x "$NEL_EXTENSION/NelNoteWidgets"

# Work in a fresh staging directory without touching the build products.
NEL_STAGE=$(mktemp -d)
trap 'rm -rf "$NEL_STAGE"' EXIT
mkdir -p "$NEL_STAGE/Payload"
ditto "$NEL_APP" "$NEL_STAGE/Payload/NelNote.app"

python3 - "$NEL_STAGE" <<'PY'
import pathlib, plistlib, sys
stage = pathlib.Path(sys.argv[1])
app = stage / "Payload/NelNote.app"
extension = app / "PlugIns/NelNoteWidgets.appex"
groups = []
for bundle, name in [(app, "app"), (extension, "widget")]:
    with (bundle / "Info.plist").open("rb") as f:
        info = plistlib.load(f)
    group = info["NelNoteAppGroup"]
    assert group.startswith("group.") and "$(" not in group, group
    groups.append(group)
    with (stage / f"{name}.entitlements").open("wb") as f:
        plistlib.dump({"com.apple.security.application-groups": [group]}, f)
    if name == "widget":
        assert info["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.widgetkit-extension"
assert groups[0] == groups[1], "App and widget must share the same group"
PY

# Keep entitlement metadata in the IPA for re-signing tools such as AltStore.
# This ad-hoc signature is not an Apple provisioning profile.
codesign --force --sign - --timestamp=none --generate-entitlement-der \
  --entitlements "$NEL_STAGE/widget.entitlements" "$NEL_STAGE/Payload/NelNote.app/PlugIns/NelNoteWidgets.appex"
codesign --force --sign - --timestamp=none --generate-entitlement-der \
  --entitlements "$NEL_STAGE/app.entitlements" "$NEL_STAGE/Payload/NelNote.app"
codesign --verify --deep --strict "$NEL_STAGE/Payload/NelNote.app"

NEL_IPA="$PWD/NelNote.ipa"
(cd "$NEL_STAGE" && zip -qry "$NEL_IPA" Payload)
python3 - "$NEL_IPA" <<'PY'
import plistlib, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as ipa:
    app = plistlib.loads(ipa.read("Payload/NelNote.app/Info.plist"))
    widget = plistlib.loads(ipa.read("Payload/NelNote.app/PlugIns/NelNoteWidgets.appex/Info.plist"))
    assert widget["CFBundleIdentifier"].startswith(app["CFBundleIdentifier"] + ".")
    assert widget["CFBundleVersion"] == app["CFBundleVersion"]
    assert app["NelNoteAppGroup"] == widget["NelNoteAppGroup"]
    assert any("nelnote" in t["CFBundleURLSchemes"] for t in app["CFBundleURLTypes"])
    assert ipa.testzip() is None
    print("Verified IPA: app, WidgetKit extension, matching App Groups, and widget deep links.")
PY
