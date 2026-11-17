# QuickTranslate — GitHub-first iOS starter

This project is designed for someone who has an iPhone, a free Apple Account, GitHub, and **no Mac**.

## What it does

- SwiftUI iOS app (iOS 18+).
- Select a screenshot or photo using Apple's Photos picker.
- Recognize text and its bounding boxes using Apple Vision OCR.
- Translate each recognized text region using Apple's Translation framework.
- Draw translated labels over the corresponding source regions.
- Register an App Shortcut called **Open QuickTranslate** for Siri, Shortcuts, and Action Button use.

## Honest platform limitations

- iOS does not let ordinary third-party apps read another app's live screen or draw a permanent overlay over arbitrary apps.
- This version uses a Shortcut to open the app, then the user selects a screenshot in the app. Direct image handoff from a Shortcut to the app would need a properly configured shared container or a different transfer design; this starter deliberately avoids App Groups and their signing setup.
- The GitHub Actions workflow builds an **iOS Simulator app** without code signing. It is a build check and simulator artifact, not an installable iPhone IPA.
- Installing on a physical iPhone requires an iOS device build signed with an Apple development identity and provisioning profile. A free Apple Account can be used for limited personal testing, but this signing flow normally requires Xcode on a Mac. Do not assume the simulator artifact can be installed on an iPhone.

## Build in GitHub Actions

1. Create a **public** GitHub repository named `QuickTranslate` (public repositories get the simplest free GitHub Actions allowance; do not upload secrets or private source code).
2. Upload the contents of this project to the repository root. Make sure `.github/workflows/ios-simulator-build.yml` keeps its folder path.
3. Commit to the `main` branch.
4. Open the repository's **Actions** tab.
5. Select **Build QuickTranslate (iOS Simulator)** and choose **Run workflow**, or push a change to `main`.
6. When the run completes, open it and download the `QuickTranslate-iOS-Simulator` artifact.

## Why XcodeGen?

The repository keeps a small `project.yml` rather than a generated `.xcodeproj`. The macOS GitHub runner installs XcodeGen and creates the Xcode project during CI, so you do not need a Mac to create the project file.

## First-run language resources

Apple Translation may need to download language resources on the iPhone. Actual translation availability depends on the installed iOS version and Apple's supported language pairs.

## Project structure

- `QuickTranslate/` — SwiftUI app, OCR, translation, App Intents shortcut.
- `project.yml` — XcodeGen project definition.
- `.github/workflows/ios-simulator-build.yml` — cloud build workflow.
