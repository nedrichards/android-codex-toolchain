# Android Codex toolchain

Reusable setup for Android projects running in a headless Codex environment.
It installs the Android command-line tools, Java 17, platform tools, the
project's required Android platforms, and the configured build-tools version.
It also warms the Gradle cache during setup, when network access is available.

## Use from an Android project

Pin this repository to a commit SHA in each project's Codex environment:

```bash
set -euo pipefail

TOOLCHAIN_REV="<commit SHA>"
curl -fsSL \
  "https://raw.githubusercontent.com/nedrichards/android-codex-toolchain/${TOOLCHAIN_REV}/setup.sh" \
  -o /tmp/android-codex-setup.sh
bash /tmp/android-codex-setup.sh
```

Run the setup from the Android repository. By default, `setup.sh` discovers
numeric `compileSdk` or `compileSdkVersion` declarations in Gradle files and
installs each corresponding platform. If the value is held indirectly, set
the levels explicitly:

```bash
ANDROID_API_LEVELS="36 37" bash /tmp/android-codex-setup.sh
```

The script persists `JAVA_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, and the
SDK paths in `~/.codex-android-env`, and sources that file from `.bashrc` for
subsequent shells.

## Overrides

The defaults can be overridden without editing the script:

- `ANDROID_SDK_ROOT`: SDK installation directory (`$HOME/android-sdk`)
- `ANDROID_JDK_VERSION`: Java version selected through `mise` (`17`)
- `ANDROID_BUILD_TOOLS_VERSION`: build-tools package (`36.0.0`)
- `ANDROID_API_LEVELS`: space-separated API levels when discovery is not enough
- `CODEX_ANDROID_PREFETCH_TASK`: Gradle task (`assembleDebug`); use `help` to skip a build
- `ANDROID_CMDLINE_TOOLS_VERSION` and `ANDROID_CMDLINE_TOOLS_SHA256`: pinned command-line tools artifact

Android Studio is intentionally not installed: the command-line SDK is enough
for Gradle builds and is better suited to a headless environment.
