# AIPIN 声存 Branding Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Ship the AIPIN 声存 voice-page identity, matching native and Flutter startup surfaces, and migrate Android, iOS, and Dart identifiers to com.aigutta.aipin.

**Architecture:** Keep branding data in a small app-level constants file and render startup UI in a focused presentation widget. Generate all raster icon outputs from one deterministic Dart tool so Android launchers, iOS AppIcon entries, and the iOS launch asset share the identical mark. Limit platform work to labels, package identifiers, the Bluetooth method channel, and existing native launch surfaces.

**Tech Stack:** Flutter Material 3, Flutter widget tests, package:image dev tool, Android resource XML/Kotlin, iOS asset catalogs/storyboard/Xcode project settings.

---

## File Structure

- Create: lib/app/branding/aipin_brand.dart - Product identity constants.
- Create: lib/app/branding/aipin_voice_page_mark.dart - Reusable Flutter CustomPaint implementation of the approved voice-page mark.
- Create: lib/app/branding/aipin_brand_splash.dart - Stateless branded loading surface while onboarding state is read.
- Create: test/app/branding/aipin_brand_splash_test.dart - Widget regression coverage for the startup identity.
- Create: tool/generate_aipin_brand_assets.dart - Deterministic renderer for the approved voice-page logo and all target PNG sizes.
- Create: assets/branding/aipin_voice_page_icon.png - Generated 1024 px canonical icon source.
- Create: android/app/src/main/res/drawable/voice_page_mark.xml - Vector mark used by Android's native launch background.
- Create: ios/Runner/Assets.xcassets/BrandLaunch.imageset/Contents.json - Mapping for generated native iOS launch image variants.
- Modify: lib/app/app_shell.dart - Render the branded splash instead of a generic progress spinner while onboarding loads.
- Modify: lib/app/evt_app.dart - Give MaterialApp the product name.
- Modify: lib/features/onboarding/presentation/welcome_page.dart - Show the full consumer product name on first use.
- Modify: pubspec.yaml - Rename the Dart package and add the icon-generation dev dependency.
- Modify: every first-party lib/**/*.dart and test/**/*.dart import - Change package:evt_ble_app/ to package:aipin/.
- Modify: Android Gradle, manifest, MainActivity, and bluetooth_enable_gateway.dart - Migrate Android identity and the paired method channel.
- Modify: Android launch resources, iOS Info.plist, project settings, and LaunchScreen.storyboard - Match native labels, identities, and launch UI.
- Modify: existing Android launcher PNGs, iOS AppIcon PNGs, README.md, and pubspec.lock - Apply generated assets and user-facing branding.

The current worktree contains unrelated uncommitted work. Every review
checkpoint below must inspect only the listed files; do not stage or commit
existing user changes without an explicit instruction to do so.

### Task 1: Lock the Flutter Startup Contract

**Files:**
- Create: test/app/branding/aipin_brand_splash_test.dart
- Modify: test/smoke_test.dart
- Modify: test/app/app_shell_test.dart

- [x] **Step 1: Write the failing splash widget test**

~~~dart
import 'package:evt_ble_app/app/branding/aipin_brand.dart';
import 'package:evt_ble_app/app/branding/aipin_brand_splash.dart';
import 'package:evt_ble_app/app/branding/aipin_voice_page_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('startup surface presents the AIPIN 声存 identity', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AipinBrandSplash()));

    expect(find.byKey(const ValueKey('aipinBrandSplash')), findsOneWidget);
    expect(find.text(AipinBrand.displayName), findsOneWidget);
    expect(find.text(AipinBrand.tagline), findsOneWidget);
    expect(find.byType(AipinVoicePageMark), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      AipinBrand.launchCanvas,
    );
  });
}
~~~

Update the welcome smoke assertion from AIPIN to AIPIN 声存. Add an initial
pump assertion that AppShell renders aipinBrandSplash while onboarding remains
unresolved.

- [x] **Step 2: Run the test to verify it fails**

Run: flutter test test/app/branding/aipin_brand_splash_test.dart

Expected: compilation failure because aipin_brand.dart and
aipin_brand_splash.dart do not exist.

- [x] **Step 3: Create the identity constants and splash widget**

Create lib/app/branding/aipin_brand.dart:

~~~dart
import 'package:flutter/material.dart';

abstract final class AipinBrand {
  static const displayName = 'AIPIN 声存';
  static const tagline = '让声音表达更简单';
  static const launchCanvas = Color(0xFFF0F4F8);
}
~~~

Create lib/app/branding/aipin_voice_page_mark.dart with a CustomPaint widget
that accepts a square size and paints the selected charcoal waveform and open
page outline. Use a rounded Paint with Color(0xFF19212B), stroke width scaled
from 6 logical pixels at a 128 logical-pixel reference canvas, and the approved
Bezier points from the design specification. Create
lib/app/branding/aipin_brand_splash.dart with a Scaffold keyed
aipinBrandSplash, backgroundColor AipinBrand.launchCanvas, a centered
AipinVoicePageMark at 112 px, then the product name and tagline at 20 px
vertical spacing. Do not add a timer, gradient, or progress indicator.

Update AppShell so its unresolved onboarding branch returns
const AipinBrandSplash instead of the generic circular indicator. Wrap the
loading and resolved branches in an AnimatedSwitcher using
EvtTheme.motionDuration. Set MaterialApp.title to AipinBrand.displayName.
Change the welcome page heading to AipinBrand.displayName.

- [x] **Step 4: Run the focused widget tests to verify they pass**

Run: flutter test test/app/branding/aipin_brand_splash_test.dart test/smoke_test.dart test/app/app_shell_test.dart

Expected: all three files pass, and a completed onboarding store still reaches
consumer navigation.

- [x] **Step 5: Review the startup UI diff without staging other work**

~~~powershell
git diff -- lib/app/branding lib/app/app_shell.dart lib/app/evt_app.dart lib/features/onboarding/presentation/welcome_page.dart test/app/branding test/smoke_test.dart test/app/app_shell_test.dart
~~~

### Task 2: Create One Reproducible Voice-Page Asset Source

**Files:**
- Modify: pubspec.yaml
- Create: tool/generate_aipin_brand_assets.dart
- Create: assets/branding/aipin_voice_page_icon.png
- Modify: Android mipmap ic_launcher.png outputs
- Modify: iOS AppIcon.appiconset PNG outputs
- Create: ios/Runner/Assets.xcassets/BrandLaunch.imageset contents and PNG outputs

- [x] **Step 1: Add the generator dependency**

Add image: ^4.5.4 under dev_dependencies in pubspec.yaml.

Run: flutter pub get

Expected: pubspec.lock resolves image without adding a production runtime dependency.

- [x] **Step 2: Implement the deterministic renderer**

Create tool/generate_aipin_brand_assets.dart. Render a 4096 px ivory
ColorRgba8(240, 244, 248, 255) canvas. Use sampled cubic Bezier segments plus
round end caps to draw the charcoal ColorRgba8(25, 33, 43, 255) waveform, then
draw the open page outline with the same rounded stroke.

Use one ordered output list. It must write the canonical 1024 px asset and
these Android outputs:

~~~text
mipmap-mdpi/ic_launcher.png=48
mipmap-hdpi/ic_launcher.png=72
mipmap-xhdpi/ic_launcher.png=96
mipmap-xxhdpi/ic_launcher.png=144
mipmap-xxxhdpi/ic_launcher.png=192
~~~

It must parse the existing iOS AppIcon Contents.json and write every listed
filename at size multiplied by scale, including the 1024 px marketing image.
It must also write BrandLaunch image variants at 112 px, 224 px, and 336 px,
with this exact Contents.json:

~~~json
{
  "images": [
    {"idiom":"universal","filename":"brand_launch.png","scale":"1x"},
    {"idiom":"universal","filename":"brand_launch@2x.png","scale":"2x"},
    {"idiom":"universal","filename":"brand_launch@3x.png","scale":"3x"}
  ],
  "info": {"version":1,"author":"xcode"}
}
~~~

Run: dart run tool/generate_aipin_brand_assets.dart

- [x] **Step 3: Inspect generated dimensions**

~~~powershell
Add-Type -AssemblyName System.Drawing
@('assets/branding/aipin_voice_page_icon.png','android/app/src/main/res/mipmap-mdpi/ic_launcher.png','android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png','ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png','ios/Runner/Assets.xcassets/BrandLaunch.imageset/brand_launch@3x.png') | ForEach-Object { $image = [System.Drawing.Image]::FromFile((Resolve-Path $_)); "$_ $($image.Width)x$($image.Height)"; $image.Dispose() }
~~~

Expected: 1024x1024, 48x48, 192x192, 1024x1024, and 336x336 in that order.

- [x] **Step 4: Run the startup test after asset generation**

Run: flutter test test/app/branding/aipin_brand_splash_test.dart

Expected: the startup identity remains green because its Flutter mark uses the
same approved geometry as the platform raster source.

- [x] **Step 5: Review generated branding assets and tooling**

~~~powershell
git diff --stat -- pubspec.yaml pubspec.lock tool/generate_aipin_brand_assets.dart assets/branding android/app/src/main/res/mipmap-* ios/Runner/Assets.xcassets/AppIcon.appiconset ios/Runner/Assets.xcassets/BrandLaunch.imageset
~~~

### Task 3: Match Native Launch Surfaces to the Brand

**Files:**
- Create: android/app/src/main/res/drawable/voice_page_mark.xml
- Modify: android/app/src/main/res/drawable/launch_background.xml
- Modify: android/app/src/main/res/drawable-v21/launch_background.xml
- Modify: android/app/src/main/res/values/styles.xml
- Modify: android/app/src/main/res/values-night/styles.xml
- Modify: ios/Runner/Base.lproj/LaunchScreen.storyboard

- [x] **Step 1: Add the Android native voice-page vector**

Create a 96 dp vector with this charcoal path:

~~~xml
<path
    android:fillColor="@android:color/transparent"
    android:strokeColor="#19212B"
    android:strokeWidth="6"
    android:strokeLineCap="round"
    android:strokeLineJoin="round"
    android:pathData="M22,68 C31,68 33,50 42,50 C51,50 53,82 62,82 C71,82 72,39 81,39 C90,39 91,70 100,70 M27,88 H91 C101,88 107,82 107,72 V43" />
~~~

- [x] **Step 2: Make both Android native launch backgrounds ivory and centered**

Replace both launch_background.xml files with:

~~~xml
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="#F0F4F8" />
    <item
        android:gravity="center"
        android:drawable="@drawable/voice_page_mark" />
</layer-list>
~~~

Set both LaunchTheme parents to Theme.Light.NoTitleBar so status icons remain
dark against the brand canvas. Do not change NormalTheme.

- [x] **Step 3: Replace the iOS native launch artwork and background**

In LaunchScreen.storyboard, change image LaunchImage to BrandLaunch, set
background RGB values to 0.941176, 0.956863, 0.972549, and constrain the
centered image view to 112 pt square. Update the resources entry to BrandLaunch
at 112 by 112.

- [x] **Step 4: Build Android to verify native resources compile**

Run: flutter build apk --debug

Expected: successful APK build and Android resource linking accepts the vector
and launch background.

- [x] **Step 5: Review native launch surface changes**

~~~powershell
git diff -- android/app/src/main/res/drawable android/app/src/main/res/drawable-v21 android/app/src/main/res/values android/app/src/main/res/values-night ios/Runner/Base.lproj/LaunchScreen.storyboard
~~~

### Task 4: Migrate Product Labels and Platform Identifiers

**Files:**
- Modify: pubspec.yaml
- Modify: every first-party lib and test Dart package import
- Modify: android/app/build.gradle.kts and android/app/src/main/AndroidManifest.xml
- Move: android/app/src/main/kotlin/com/xkp/evt_ble_app/MainActivity.kt to android/app/src/main/kotlin/com/aigutta/aipin/MainActivity.kt
- Modify: lib/core/ble/bluetooth_enable_gateway.dart
- Modify: ios/Runner/Info.plist and ios/Runner.xcodeproj/project.pbxproj
- Modify: README.md

- [x] **Step 1: Rename the Dart package and every first-party import**

Set the pubspec name to aipin. Perform a scoped replacement only in lib and
test:

~~~powershell
Get-ChildItem lib,test -Recurse -Filter *.dart | ForEach-Object {
  (Get-Content -Raw $_.FullName).Replace('package:evt_ble_app/', 'package:aipin/') | Set-Content -NoNewline $_.FullName
}
~~~

Run: flutter pub get

Expected: generated package configuration identifies the root package as aipin,
and no first-party source imports package:evt_ble_app.

- [x] **Step 2: Rename Android identity and its paired Bluetooth channel**

Set Android namespace and applicationId to com.aigutta.aipin. Set the manifest
label to AIPIN 声存. Create the destination directory and move MainActivity:

~~~powershell
New-Item -ItemType Directory -Force android/app/src/main/kotlin/com/aigutta/aipin
Move-Item -LiteralPath android/app/src/main/kotlin/com/xkp/evt_ble_app/MainActivity.kt -Destination android/app/src/main/kotlin/com/aigutta/aipin/MainActivity.kt
~~~

Change the Kotlin package and Bluetooth method channel to
com.aigutta.aipin/bluetooth. Change the matching Dart MethodChannel constant to
the same string.

- [x] **Step 3: Rename iOS display labels and bundle identifiers**

Set CFBundleDisplayName and CFBundleName to AIPIN 声存. In project.pbxproj,
change every Runner product bundle identifier to com.aigutta.aipin and every
RunnerTests identifier to com.aigutta.aipin.RunnerTests for Debug, Release, and
Profile.

- [x] **Step 4: Align user documentation**

Update README heading to AIPIN 声存 and add the tagline 让声音表达更简单 below
it. Keep EVT where it denotes the existing protocol or evidence database.

- [x] **Step 5: Verify renamed references and Android package**

~~~powershell
rg -n --glob '!build/**' --glob '!*\.g.dart' 'package:evt_ble_app/|com\.xkp\.evt_ble_app|com\.xkp\.evtBleApp|evtBleApp/bluetooth' lib test android ios pubspec.yaml
flutter analyze
flutter build apk --debug
~~~

Expected: rg returns no matches; static analysis has no issues; the debug APK
build succeeds with application ID com.aigutta.aipin.

- [x] **Step 6: Review the identifier migration without staging prior changes**

~~~powershell
git diff -- pubspec.yaml pubspec.lock lib test android/app/build.gradle.kts android/app/src/main/AndroidManifest.xml android/app/src/main/kotlin/com/aigutta/aipin/MainActivity.kt lib/core/ble/bluetooth_enable_gateway.dart ios/Runner/Info.plist ios/Runner.xcodeproj/project.pbxproj README.md
~~~

### Task 5: Run Final Regression and Handoff Checks

**Files:**
- Modify: docs/superpowers/plans/2026-08-24-aipin-shengcun-branding-migration.md - Mark completed execution steps only.

- [x] **Step 1: Format first-party source**

Run: dart format lib test tool

Expected: all renamed imports and branding files use canonical Dart formatting.

- [x] **Step 2: Run the complete static and unit/widget suite**

~~~powershell
flutter analyze
flutter test
~~~

Expected: analyzer exits with no issues and every test passes.

- [x] **Step 3: Inspect the final Android package output**

~~~powershell
flutter build apk --debug
$apk = Resolve-Path build/app/outputs/flutter-apk/app-debug.apk
& "$env:ANDROID_HOME/build-tools/$(Get-ChildItem "$env:ANDROID_HOME/build-tools" | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name)/aapt.exe" dump badging $apk | Select-String '^package: name='
~~~

Expected: the badging line contains name='com.aigutta.aipin'.

- [x] **Step 4: Record the iOS verification boundary**

Do not claim an iOS build from Windows. Record that the project contains the
new bundle IDs, label, icon set, and launch storyboard; an xcodebuild archive
and device icon inspection remain required on a macOS/Xcode host.

- [x] **Step 5: Record final verification in the task handoff**

Report the exact analyzer, test, Android build, Android package-inspection, and
iOS verification-boundary results without staging unrelated work.
