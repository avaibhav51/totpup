#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
build_configuration="${1:-release}"
swift build -c "$build_configuration" --product Totpup
binary_directory="$(swift build -c "$build_configuration" --show-bin-path)"
mkdir -p dist/Totpup.app/Contents/MacOS
cp "$binary_directory/Totpup" dist/Totpup.app/Contents/MacOS/Totpup
mkdir -p dist/Totpup.app/Contents/Resources dist/AppIcon.iconset
"$binary_directory/Totpup" --render-icon "${PWD}/dist/AppIcon.png"
for icon_size in 16 32 128 256 512; do
  sips -z "$icon_size" "$icon_size" dist/AppIcon.png --out "dist/AppIcon.iconset/icon_${icon_size}x${icon_size}.png" > /dev/null
  retina_size=$((icon_size * 2))
  sips -z "$retina_size" "$retina_size" dist/AppIcon.png --out "dist/AppIcon.iconset/icon_${icon_size}x${icon_size}@2x.png" > /dev/null
done
iconutil -c icns dist/AppIcon.iconset -o dist/Totpup.app/Contents/Resources/AppIcon.icns
cp dist/AppIcon.png dist/Totpup.app/Contents/Resources/AppIcon.png
widget_contents="dist/Totpup.app/Contents/PlugIns/TotpupWidgets.appex/Contents"
mkdir -p "$widget_contents/MacOS"
xcrun swiftc -parse-as-library -application-extension -target "$(uname -m)-apple-macos14.0" \
  -Xlinker -e -Xlinker _NSExtensionMain \
  Widgets/TotpupWidget.swift Sources/Totpup/Design.swift \
  -o "$widget_contents/MacOS/TotpupWidgets"
cp Widgets/Info.plist "$widget_contents/Info.plist"
codesign --force --sign - --entitlements Widgets/Widget.entitlements "${widget_contents:h}"
cat > dist/Totpup.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Totpup</string>
<key>CFBundleIdentifier</key><string>app.totpup.authenticator</string>
<key>CFBundleName</key><string>Totpup</string>
<key>CFBundleDisplayName</key><string>Totpup</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.2</string>
<key>CFBundleVersion</key><string>13</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>LSUIElement</key><true/>
<key>CFBundleURLTypes</key><array><dict>
<key>CFBundleURLName</key><string>app.totpup.fetch</string>
<key>CFBundleURLSchemes</key><array><string>totpup</string></array>
</dict></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSFaceIDUsageDescription</key><string>Unlock your Totpup verification codes.</string>
</dict></plist>
PLIST
codesign --force --sign - dist/Totpup.app
print "Built: ${PWD}/dist/Totpup.app"
