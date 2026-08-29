#!/usr/bin/env bash
set -euo pipefail

# Generic Android toolchain setup for Codex cloud environments.
#
# The setup phase has network access and the later agent shell may not, so
# this script installs the SDK and warms the Gradle cache before the agent
# starts. Run it from the Android project that should be prepared.

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/android-sdk}"
ANDROID_HOME="$ANDROID_SDK_ROOT"

# Pin the command-line tools rather than following an unversioned latest URL.
ANDROID_CMDLINE_TOOLS_VERSION="${ANDROID_CMDLINE_TOOLS_VERSION:-15859902}"
ANDROID_CMDLINE_TOOLS_SHA256="${ANDROID_CMDLINE_TOOLS_SHA256:-4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583}"

# AGP 9.3's default build-tools line, overridable for another project.
ANDROID_BUILD_TOOLS_VERSION="${ANDROID_BUILD_TOOLS_VERSION:-36.0.0}"
ANDROID_JDK_VERSION="${ANDROID_JDK_VERSION:-17}"

echo "Setting up Android SDK in $ANDROID_SDK_ROOT"

if ! command -v mise >/dev/null 2>&1; then
    echo "mise not found; this script expects the Codex universal image" >&2
    exit 1
fi

JAVA_HOME="$(mise where "java@$ANDROID_JDK_VERSION")"
if [[ ! -x "$JAVA_HOME/bin/java" ]]; then
    echo "Could not find Java $ANDROID_JDK_VERSION through mise" >&2
    exit 1
fi

export JAVA_HOME ANDROID_HOME ANDROID_SDK_ROOT
export PATH="$JAVA_HOME/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

# Setup runs in a separate shell from the agent. Persist the exports for later
# shells without duplicating the source line in .bashrc.
CODEX_ANDROID_ENV="$HOME/.codex-android-env"
cat > "$CODEX_ANDROID_ENV" <<EOF
export JAVA_HOME="$JAVA_HOME"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"
export PATH="\$JAVA_HOME/bin:\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:\$ANDROID_SDK_ROOT/platform-tools:\$PATH"
EOF

if [[ -f "$HOME/.bashrc" ]] && ! grep -qF 'source "$HOME/.codex-android-env"' "$HOME/.bashrc"; then
    printf '%s\n' 'source "$HOME/.codex-android-env"' >> "$HOME/.bashrc"
fi

SDKMANAGER="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"

if [[ ! -x "$SDKMANAGER" ]]; then
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT
    archive="$tmpdir/commandlinetools.zip"
    unpacked="$tmpdir/unpacked"

    curl -fsSL \
        "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip" \
        -o "$archive"
    printf '%s  %s\n' "$ANDROID_CMDLINE_TOOLS_SHA256" "$archive" | sha256sum -c -

    mkdir -p "$unpacked" "$ANDROID_SDK_ROOT/cmdline-tools"
    unzip -q "$archive" -d "$unpacked"
    rm -rf "$ANDROID_SDK_ROOT/cmdline-tools/latest"
    mv "$unpacked/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
fi

# sdkmanager may exit successfully after yes receives SIGPIPE.
yes | "$SDKMANAGER" --sdk_root="$ANDROID_SDK_ROOT" --licenses >/dev/null 2>&1 || true

# Discover compileSdk declarations in the Android project being prepared.
# Supply ANDROID_API_LEVELS explicitly when the value is indirect.
if [[ -n "${ANDROID_API_LEVELS:-}" ]]; then
    read -r -a API_LEVELS <<< "$ANDROID_API_LEVELS"
else
    mapfile -t API_LEVELS < <(
        find . -type f \
            \( -name '*.gradle' -o -name '*.gradle.kts' \) \
            -not -path './.gradle/*' -print0 |
        xargs -0 -r grep -hE \
            'compileSdk(Version)?[[:space:]]*(=|[[:space:]])[[:space:]]*[0-9]+' 2>/dev/null |
        sed -nE 's/.*compileSdk(Version)?[[:space:]]*(=[[:space:]]*)?([0-9]+).*/\3/p' |
        sort -nu
    )
fi

if [[ "${#API_LEVELS[@]}" -eq 0 ]]; then
    echo "Could not determine compileSdk from this project." >&2
    echo 'Set ANDROID_API_LEVELS explicitly, for example: ANDROID_API_LEVELS="36 37"' >&2
    exit 1
fi

echo "Android API levels required: ${API_LEVELS[*]}"
PACKAGES=(
    "platform-tools"
    "build-tools;$ANDROID_BUILD_TOOLS_VERSION"
)
for api in "${API_LEVELS[@]}"; do
    PACKAGES+=("platforms;android-$api")
done

"$SDKMANAGER" --sdk_root="$ANDROID_SDK_ROOT" "${PACKAGES[@]}"

# Setup has internet access; use it to prime the wrapper, plugins and normal
# dependencies needed by the project. Set the variable to `help` to skip the
# expensive build while retaining SDK setup.
if [[ -x ./gradlew ]]; then
    PREFETCH_TASK="${CODEX_ANDROID_PREFETCH_TASK:-assembleDebug}"
    if [[ "$PREFETCH_TASK" == "help" ]]; then
        echo "Skipping Gradle cache warm-up (CODEX_ANDROID_PREFETCH_TASK=help)"
    else
        echo "Warming Gradle cache with: $PREFETCH_TASK"
        ./gradlew --no-daemon "$PREFETCH_TASK" -x lint
    fi
fi

echo
echo "Android Codex environment ready:"
echo "  JAVA_HOME=$JAVA_HOME"
echo "  ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT"
echo "  APIs=${API_LEVELS[*]}"
echo "  Build Tools=$ANDROID_BUILD_TOOLS_VERSION"
