#!/usr/bin/env python3
"""Validate the actual exported APK; write inspectable metadata beside it."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import zipfile

apk = Path(sys.argv[1]).resolve()
tools = Path(os.environ.get('ANDROID_HOME', '/workspace/tools/android-sdk')) / 'build-tools/34.0.0'

def run(name, *args):
    return subprocess.check_output([str(tools/name), *map(str, args)], text=True, stderr=subprocess.STDOUT)

badging = run('aapt2', 'dump', 'badging', apk)
manifest = run('aapt', 'dump', 'xmltree', apk, 'AndroidManifest.xml')
signature = run('apksigner', 'verify', '--verbose', '--print-certs', apk)
alignment = run('zipalign', '-c', '-v', '4', apk)
assert "package: name='com.kawanangames.kawananisland'" in badging
assert "versionCode='3'" in badging and "versionName='0.6.0-dev'" in badging
assert "application-label:'Kawanan Island'" in badging
assert "native-code: 'arm64-v8a'" in badging
assert 'application-debuggable' in badging
assert 'android.intent.category.LAUNCHER' in manifest
assert re.search(r'android:screenOrientation[^\n]*=\(type 0x10\)0x0(?:\s|$)', manifest), 'Landscape is required'
permissions = re.findall(r"uses-permission(?:-sdk-\d+)?: name='([^']+)'", badging)
assert not permissions, permissions
assert 'Verified using v2 scheme (APK Signature Scheme v2): true' in signature
assert alignment.rstrip().endswith(('Verification successful', 'Verification succesful'))
with zipfile.ZipFile(apk) as z:
    assert z.testzip() is None
    names = z.namelist()
    assert len(names) == len(set(names)), 'Duplicate ZIP entries'
    assert 'assets/licenses/Godot-LICENSE.txt' in names
    assert 'assets/licenses/Godot-COPYRIGHT.txt' in names
    assert 'assets/addons/proton_scatter/LICENSE' in names
    assert 'classes.dex' in names and 'AndroidManifest.xml' in names
    assert 'lib/arm64-v8a/libgodot_android.so' in names
    assert any(n.startswith('assets/') and 'main_game' in n for n in names), 'Missing game scene'
    assert not any(n.startswith(('assets/tests/', 'assets/docs/', 'assets/scripts/')) for n in names)
    assert not any(n.endswith(('.keystore', '.jks', '.apk', '.aab')) for n in names)
    abis = sorted({n.split('/')[1] for n in names if n.startswith('lib/')})
    assert abis == ['arm64-v8a'], abis
    elf = z.read('lib/arm64-v8a/libgodot_android.so')
    assert elf[:5] == b'\x7fELF\x02' and int.from_bytes(elf[18:20], 'little') == 183
for suffix, value in [('badging.txt',badging), ('manifest.txt',manifest), ('signature.txt',signature), ('alignment.txt',alignment)]:
    apk.with_suffix('.'+suffix).write_text(value)
report = {
    'apk': apk.name, 'bytes': apk.stat().st_size,
    'sha256': hashlib.file_digest(apk.open('rb'), 'sha256').hexdigest(),
    'package': 'com.kawanangames.kawananisland', 'version': '0.6.0-dev',
    'abis': abis, 'permissions': permissions, 'debuggable': True,
    'orientation': 'landscape', 'signature_v2_verified': True,
    'zip_crc_and_alignment': 'passed', 'physical_device_tested': False,
}
apk.with_suffix('.validation.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report, indent=2))
