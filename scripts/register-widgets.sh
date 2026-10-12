#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app_bundle="${PWD}/dist/Totpup.app"
extension_bundle="${app_bundle}/Contents/PlugIns/TotpupWidgets.appex"
test -d "$extension_bundle"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_bundle"
pluginkit -a "$extension_bundle"
pluginkit -m -v -i app.totpup.authenticator.widgets
