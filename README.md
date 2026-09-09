# Android Codex toolchain

Reusable setup for Android projects running in a headless Codex environment.
It installs the Android command-line tools, Java 17, platform tools, the
project's required Android platforms, and the configured build-tools version.
It resolves every resolvable Gradle configuration and proves that it can be
resolved again offline while setup still has network access.

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

Use the companion script as the Codex environment's maintenance script. Pin it
to the same revision:

```bash
set -euo pipefail

TOOLCHAIN_REV="<same commit SHA>"
curl -fsSL \
  "https://raw.githubusercontent.com/nedrichards/android-codex-toolchain/${TOOLCHAIN_REV}/refresh.sh" \
  -o /tmp/android-codex-refresh.sh
bash /tmp/android-codex-refresh.sh
```

Run the setup from the Android repository. By default, `setup.sh` discovers
numeric `compileSdk` or `compileSdkVersion` declarations in Gradle files and
installs each corresponding platform. If the value is held indirectly, set
the levels explicitly:

```bash
ANDROID_PLATFORM_VERSIONS="36 37.1" bash /tmp/android-codex-setup.sh
```

The setup script creates the ignored, machine-local `local.properties`,
persists `JAVA_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, and the SDK paths in
`~/.codex-android-env`, and sources that file from `.bashrc` for subsequent
shells. The maintenance script recreates `local.properties` and refreshes the
dependency cache after Codex checks out the requested branch.

Also configure these ordinary variables in the Codex environment so they are
available to both setup and agent shells:

```text
ANDROID_HOME=/root/android-sdk
ANDROID_SDK_ROOT=/root/android-sdk
```

Agent internet access can remain disabled. Run Gradle with `--offline` during
cloud tasks so a missing prefetched dependency fails immediately and clearly.
For example, add this guidance to the Android project's `AGENTS.md`:

```markdown
In Codex Cloud, run Gradle with `--offline`. Dependencies must be populated by
the environment setup or maintenance script; do not enable agent internet to
resolve them.
```

## Overrides

The defaults can be overridden without editing the script:

- `ANDROID_SDK_ROOT`: SDK installation directory (`$HOME/android-sdk`)
- `ANDROID_JDK_VERSION`: Java version selected through `mise` (`17`)
- `ANDROID_BUILD_TOOLS_VERSION`: build-tools package (`36.0.0`)
- `ANDROID_PLATFORM_VERSIONS`: space-separated platform versions when discovery is not enough

Android Studio is intentionally not installed: the command-line SDK is enough
for Gradle builds and is better suited to a headless environment.
