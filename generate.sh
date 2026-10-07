#!/bin/sh
# Regenerates PayDay.xcodeproj from project.yml, then adds the capability list
# Xcode's Signing & Capabilities tab reads (iCloud, Push, Background Modes).
# xcodegen can't write nested target attributes, and without them Xcode shows
# "The capability associated with ICLOUD could not be determined".
set -e
cd "$(dirname "$0")"
xcodegen generate
python3 - <<'PY'
import re
p = "PayDay.xcodeproj/project.pbxproj"
s = open(p).read()
caps = """SystemCapabilities = {
							com.apple.BackgroundModes = {
								enabled = 1;
							};
							com.apple.Push = {
								enabled = 1;
							};
							com.apple.iCloud = {
								enabled = 1;
							};
						};
						ProvisioningStyle = Automatic;"""
s, n = re.subn(r"ProvisioningStyle = Automatic;", caps, s, count=1)
assert n == 1, "target attributes not found"
open(p, "w").write(s)
print("Added iCloud / Push / Background Modes capabilities")
PY
