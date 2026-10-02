"""Generate current Flutter Android/iOS wrappers and camera permissions safely.
Run once from the project: python tool/setup.py
"""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import re

root=Path(__file__).resolve().parents[1]
if shutil.which('flutter') is None:
    raise SystemExit('Install Flutter and put flutter on PATH first.')
# Keep app source/tests/config even if Flutter regenerates template files.
with tempfile.TemporaryDirectory() as temporary:
    backup=Path(temporary)
    for name in ['lib','test','pubspec.yaml']:
        source=root/name
        if source.is_dir():shutil.copytree(source,backup/name)
        elif source.exists():shutil.copy2(source,backup/name)
    try:
        subprocess.run(['flutter','create','--platforms=android,ios','--org','com.hexagoncompanion','--project-name','hexagon_companion','.'],cwd=root,check=True)
    finally:
        for name in ['lib','test','pubspec.yaml']:
            original=backup/name
            if not original.exists():continue
            destination=root/name
            if original.is_dir():
                if destination.exists():shutil.rmtree(destination)
                shutil.copytree(original,destination)
            else:shutil.copy2(original,destination)
plist=root/'ios/Runner/Info.plist'
if plist.exists():
    with plist.open('rb') as f:data=plistlib.load(f)
    data['CFBundleDisplayName']='Hexagon Companion'
    data['NSCameraUsageDescription']='Take a photo of your physical puzzle to recognize its starting pieces.'
    data['NSPhotoLibraryUsageDescription']='Choose a puzzle photo for local recognition.'
    with plist.open('wb') as f:plistlib.dump(data,f,sort_keys=False)
for path in [root/'android/app/build.gradle.kts',root/'android/app/build.gradle']:
    if path.exists():
        text=path.read_text()
        if path.suffix=='.kts':text=re.sub(r'minSdk\s*=\s*[^\n]+','minSdk = 24',text)
        else:text=re.sub(r'minSdkVersion\s+[^\n]+','minSdkVersion 24',text)
        path.write_text(text)
manifest=root/'android/app/src/main/AndroidManifest.xml'
if manifest.exists():manifest.write_text(manifest.read_text().replace('android:label="hexagon_companion"','android:label="Hexagon Companion"'))
subprocess.run(['flutter','pub','get'],cwd=root,check=True)
print('Ready: flutter analyze, flutter test, then flutter run')
