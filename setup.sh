#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Reusable Android toolchain setup for Codex Cloud
# ---------------------------------------------------------------------------

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/android-sdk}"
ANDROID_HOME="$ANDROID_SDK_ROOT"

# AGP 9.3.x default/minimum build tools.
ANDROID_BUILD_TOOLS_VERSION="${ANDROID_BUILD_TOOLS_VERSION:-36.0.0}"
ANDROID_JDK_VERSION="${ANDROID_JDK_VERSION:-17}"

echo "Setting up Android SDK in $ANDROID_SDK_ROOT"

# ---------------------------------------------------------------------------
# Java
#
# Codex's universal image already has JDK 17 installed via mise.
# ---------------------------------------------------------------------------

if ! command -v mise >/dev/null 2>&1; then
    echo "mise not found; this script expects the Codex universal image" >&2
    exit 1
fi

JAVA_HOME="$(mise where "java@$ANDROID_JDK_VERSION")"

export JAVA_HOME
export ANDROID_HOME
export ANDROID_SDK_ROOT
export PATH="$JAVA_HOME/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

# Persist for the Codex agent shell.
cat > "$HOME/.codex-android-env" <<EOF
export JAVA_HOME="$JAVA_HOME"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"
export PATH="\$JAVA_HOME/bin:\$ANDROID_SDK_ROOT/platform-tools:\$PATH"
EOF

if ! grep -qF 'source "$HOME/.codex-android-env"' "$HOME/.bashrc" 2>/dev/null; then
    echo 'source "$HOME/.codex-android-env"' >> "$HOME/.bashrc"
fi

# ---------------------------------------------------------------------------
# Android CLI
#
# Use Google's new Android CLI rather than sdkmanager.
# Codex Cloud currently runs on amd64 Ubuntu, so use Google's apt repository.
# ---------------------------------------------------------------------------

install -d -m 0755 /etc/apt/keyrings

curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
    -o /etc/apt/keyrings/google.asc

cat > /etc/apt/sources.list.d/android-cli.list <<'EOF'
deb [arch=amd64 signed-by=/etc/apt/keyrings/google.asc] http://dl.google.com/android/cli/latest/debian/ stable main
EOF

apt-get update
apt-get install -y --no-install-recommends android-cli

echo "Android CLI:"
android --version

mkdir -p "$ANDROID_SDK_ROOT"

# Tell Android CLI which SDK tree this environment uses.
printf -- '--sdk=%s\n' "$ANDROID_SDK_ROOT" > "$HOME/.androidrc"

# ---------------------------------------------------------------------------
# Discover compile SDKs used by this repository.
#
# Examples:
#
#   compileSdk = 36
#
# becomes:
#
#   platforms/android-36
#
# while:
#
#   compileSdk = 37
#   compileSdkMinor = 1
#
# becomes:
#
#   platforms/android-37.1
#
# API 37 introduced the minor-SDK package naming scheme, so bare API 37
# is represented by 37.0 rather than "37".
#
# Override autodetection with, for example:
#
#   ANDROID_PLATFORM_VERSIONS="36 37.1"
# ---------------------------------------------------------------------------

declare -A PLATFORM_SET=()

if [[ -n "${ANDROID_PLATFORM_VERSIONS:-}" ]]; then
    for version in $ANDROID_PLATFORM_VERSIONS; do
        PLATFORM_SET["$version"]=1
    done
else
    while IFS= read -r -d '' build_file; do
        api="$(
            sed -nE \
                's/.*compileSdk(Version)?[[:space:]]*(=[[:space:]]*)?([0-9]+).*/\3/p' \
                "$build_file" |
            head -n 1
        )"

        [[ -z "$api" ]] && continue

        minor="$(
            sed -nE \
                's/.*compileSdkMinor[[:space:]]*(=[[:space:]]*)?([0-9]+).*/\2/p' \
                "$build_file" |
            head -n 1
        )"

        if [[ -n "$minor" ]]; then
            version="${api}.${minor}"
        elif (( api >= 37 )); then
            # API 37+ uses explicit minor SDK package names.
            version="${api}.0"
        else
            version="$api"
        fi

        PLATFORM_SET["$version"]=1

    done < <(
        find . \
            -type f \
            \( -name '*.gradle' -o -name '*.gradle.kts' \) \
            -not -path './.gradle/*' \
            -print0
    )
fi

if [[ "${#PLATFORM_SET[@]}" -eq 0 ]]; then
    echo "Could not determine compileSdk." >&2
    echo "Set ANDROID_PLATFORM_VERSIONS explicitly, e.g.:" >&2
    echo '  ANDROID_PLATFORM_VERSIONS="36 37.1"' >&2
    exit 1
fi

mapfile -t PLATFORM_VERSIONS < <(
    printf '%s\n' "${!PLATFORM_SET[@]}" | sort -V
)

echo "Android platform SDKs required: ${PLATFORM_VERSIONS[*]}"

# ---------------------------------------------------------------------------
# Install SDK components using Android CLI
# ---------------------------------------------------------------------------

PACKAGES=(
    "platform-tools"
    "build-tools/$ANDROID_BUILD_TOOLS_VERSION"
)

for version in "${PLATFORM_VERSIONS[@]}"; do
    PACKAGES+=("platforms/android-$version")
done

echo "Installing:"
printf '  %s\n' "${PACKAGES[@]}"

# Android CLI may ask for SDK licence acceptance.
# Preserve the android command's exit status rather than `yes`'s SIGPIPE.
set +o pipefail
yes | android sdk install "${PACKAGES[@]}"
android_status=${PIPESTATUS[1]}
set -o pipefail

if (( android_status != 0 )); then
    echo "Android SDK installation failed" >&2
    exit "$android_status"
fi

# Install the android agent skills so we have them in the context as well.
android init

# ---------------------------------------------------------------------------
# Warm the Gradle cache.
#
# Codex setup has network access, while the subsequent agent environment
# may not. This fetches the wrapper, AGP and Maven dependencies now.
# ---------------------------------------------------------------------------

if [[ -x ./gradlew ]]; then
    PREFETCH_TASK="${CODEX_ANDROID_PREFETCH_TASK:-assembleDebug}"

    echo "Warming Gradle cache with: $PREFETCH_TASK"

    ./gradlew \
        --no-daemon \
        "$PREFETCH_TASK" \
        -x lint
fi

echo
echo "Android Codex environment ready:"
echo "  Android CLI: $(android --version)"
echo "  JAVA_HOME=$JAVA_HOME"
echo "  ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT"
echo "  Platforms=${PLATFORM_VERSIONS[*]}"
echo "  Build Tools=$ANDROID_BUILD_TOOLS_VERSION"
