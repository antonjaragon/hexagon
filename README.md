# Hexagon Companion — Flutter mobile app

An offline companion for your physical puzzle. Take one photo, review recognition, then use **Solve / One tip / Undo / Hide answer**. There are no starting-position save or board-image export controls.

Photographed pieces and suggested pieces use exactly the same rounded renderer. No white circles or ghost styling appear on hints/solutions. Blocked cells are pale sage hexagons with diagonal hatching; empty playable sockets remain dark.

## Build and run on your phone

Install the stable Flutter SDK and Android Studio (Android) or Xcode (iPhone on macOS). Then open a terminal in this folder:

```bash
flutter doctor
python tool/setup.py
flutter analyze
flutter test
flutter run
```

Use `python3` if that is your Python command. `tool/setup.py` generates the Android/iOS wrappers with your installed Flutter version, preserves app source/tests, adds camera/photo explanations to the iOS plist, sets Android min SDK 24 and downloads Dart dependencies. It is safe to rerun. If Android/iOS wrappers already exist in this archive, setup refreshes them while retaining app source.

### Android

Enable Developer options and USB debugging, connect the phone, then:

```bash
flutter devices
flutter run -d YOUR_DEVICE_ID
```

For a release APK:

```bash
flutter build apk --release
```

Install `build/app/outputs/flutter-apk/app-release.apk` on the phone. This uses Flutter's default local signing configuration; set up your own release signing before distribution through a store. Android 7/API 24 or later is required by the photo plugin. Camera/gallery permission handling is provided by image_picker; no broad storage or microphone access is requested by this app.

### iPhone

Build on your Mac (your M1 is suitable). Run setup, open `ios/Runner.xcworkspace` in Xcode, select your development team under Signing & Capabilities, connect your iPhone, and run. iOS 13+ is required by image_picker. Xcode may request developer mode/trust on the phone. A Windows computer cannot perform the normal iOS signing/build workflow.

## Use

1. Tap the camera icon / **Take a photo**. An existing photo can also be selected.
2. Recognition suggests six board landmarks. Check that the markers are at the centers of the six OUTERMOST CELLS, not at the plastic rim. They run clockwise: top left, top right, right, bottom right, bottom left, left.
3. If incorrect, tap **Mark 6 centers**, then mark them on the photo. The numbered board below is your guide.
4. Tap **Recognize** and compare the recognized board preview to the physical puzzle.
5. If colors are confused, select the piece color, tap **Sample color**, then tap a colored area of that piece in the photo. Recognize again. Avoid glare and black pegs. The three blue pieces particularly benefit from shape-aware recognition and, when needed, calibration.
6. Tap **Use this recognized board** to enter the companion screen.

Only complete, geometrically valid recognized pieces are used. Missing/incorrect pieces require adjusting recognition or retaking the photo; the main screen deliberately has no editor, save or export tools. An empty recognition result does not prove that the photographed board is empty. Review every imported position before relying on its answer.

### Four controls

- **Solve:** displays all remaining pieces in a valid completion.
- **One tip:** reveals one additional piece. Further taps reveal one more each time, retaining earlier tips. Each tip is consistent with the current revealed continuation.
- **Undo:** reverses the last reveal/hide action. It never removes photographed pieces.
- **Hide answer:** removes all revealed pieces and restores the photographed starting position.

A tip is one valid continuation, not necessarily a uniquely forced move. No special hint paint is used: the piece name in the status message tells you which piece was added. Taking another photo replaces the session and resets its answer history.

## Photo recognition and privacy

All decoding, perspective alignment, color sampling, shape fitting and exact-cover solving run on-device. There is no server, Python installation, GPU requirement or API key. Photo decoding/recognition and search use isolates to keep the interface responsive. Camera cache files are managed by the system/image_picker; the app does not create a photo collection or persistent puzzle files. Recognition/results are held in memory.

Use a sharp, overhead photo with the entire dark board visible and diffuse lighting. Defaults match your provided puzzle; manual six-point registration and color calibration cover less ideal photos. Color evidence is constrained by the known shapes. Photo import covers only visible colored cells and never silently adds the missing pieces. If global shape fitting fails, individually valid color groups are retained for review.

The Dart recognition port has its own outline suggestion implementation. It may behave differently from the desktop OpenCV app on some photographs. Manual alignment is the reliable fallback. This is not a trained universal vision model: occlusion, strong glare/blur, unusual backgrounds, heavy perspective and different puzzle shapes can require a new photo. JPEG/PNG are supported by the Dart image decoder; use JPEG if a gallery HEIC file fails to decode.

The app includes the real full-board photo as a test fixture; it is not auto-loaded into the user flow. Your provided image is already complete, so its correct recognition should report that no additional pieces are needed.

## Implementation

`lib/engine.dart` ports exact-cover backtracking to Dart. Occupancy uses **BigInt**, because 72 usable cells exceed the native 64-bit integer width. The fixed board contains 91 positions, 19 blocked pegs, 12 pieces and 1,962 geometrically legal placements (rotations and reflections enabled). Search uses the most constrained cell/piece and has a 20-second timeout. A timeout is not proof of impossibility.

`lib/recognition.dart` handles EXIF orientation, bounded-size images, dark-outline alignment suggestions, six-landmark perspective fitting, HSV sampling and shape-aware placement recognition. Color fitting is bounded to roughly 2.2 seconds after preprocessing. The supplied `assets/board.json` defines the same physical pieces/rules as your desktop solver.

`lib/board_view.dart` provides a shared renderer for both recognized and revealed pieces. Blocked pegs are pale and hatched.

`lib/main.dart` provides capture/gallery recovery on Android, registration/calibration/review and the four companion actions. No persistent puzzle storage or export implementation is included.

Verification: Dart source formatting/parsing passed and the native Dart exact-cover engine executed successfully (1,962 placements, 72-bit occupancy, a valid one-piece completion). The standalone Dart recognition port also recognized all 12 whole pieces in the provided real photo, with seven sampled colors flagged for review, and the solver confirmed a complete valid board. Flutter tests are provided for solver completion, tip history, recognition, malformed images, registration, and identical hint/placed rendering. Full Flutter analysis/tests could not run here: automatic approval review stopped Flutter tooling after it attempted cloud metadata access. Run the commands above on your laptop. Physical camera capture, permissions, actual device performance and platform signing also require your phone.

Official references:

- https://pub.dev/packages/image_picker
- https://pub.dev/packages/image
- https://docs.flutter.dev/get-started/install
