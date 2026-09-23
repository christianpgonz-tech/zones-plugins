#!/bin/bash
# Builds Football.zone and Football.zip (the file you put on your website).
set -e
cd "$(dirname "$0")"
NAME=Football
SRC="../Shared/SportsPicker.swift FootballPicker.swift FootballData.swift FootballViews.swift FootballWindow.swift FootballChip.swift FootballAlert.swift FootballZone.swift"
rm -rf build && mkdir -p build/$NAME.zone/Contents/MacOS
swiftc -emit-library -module-name $NAME -o build/$NAME.zone/Contents/MacOS/$NAME \
  -Xlinker -bundle -target arm64-apple-macos14.0 $SRC
swiftc -emit-library -module-name $NAME -o build/x86 -Xlinker -bundle -target x86_64-apple-macos14.0 $SRC
lipo -create build/$NAME.zone/Contents/MacOS/$NAME build/x86 -output build/$NAME.zone/Contents/MacOS/$NAME.fat
mv build/$NAME.zone/Contents/MacOS/$NAME.fat build/$NAME.zone/Contents/MacOS/$NAME; rm build/x86
cp Info.plist build/$NAME.zone/Contents/Info.plist
mkdir -p build/$NAME.zone/Contents/Resources && cp ZoneIcon.png build/$NAME.zone/Contents/Resources/
codesign --force --sign - build/$NAME.zone
(cd build && ditto -c -k --norsrc --keepParent $NAME.zone ../$NAME.zip)
echo "Built $NAME.zip"
