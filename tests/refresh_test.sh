#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

cp "$REPOSITORY_ROOT/refresh.sh" "$TEST_DIRECTORY/refresh.sh"

cat > "$TEST_DIRECTORY/gradlew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> gradle-invocations

init_script=""
while (( $# > 0 )); do
    if [[ "$1" == "--init-script" ]]; then
        init_script="$2"
        break
    fi
    shift
done

if [[ -n "$init_script" ]]; then
    grep -q 'configuration.resolve()' "$init_script"
fi
EOF
chmod +x "$TEST_DIRECTORY/gradlew"

(
    cd "$TEST_DIRECTORY"
    ANDROID_SDK_ROOT=/tmp/codex-test-sdk ./refresh.sh
)

grep -qx 'sdk.dir=/tmp/codex-test-sdk' "$TEST_DIRECTORY/local.properties"

mapfile -t invocations < "$TEST_DIRECTORY/gradle-invocations"
[[ "${#invocations[@]}" -eq 2 ]]
[[ "${invocations[0]}" != *"--offline"* ]]
[[ "${invocations[1]}" == *"--offline"* ]]
[[ "${invocations[0]}" == *"codexResolveAllDependencies"* ]]
[[ "${invocations[1]}" == *"codexResolveAllDependencies"* ]]

echo "refresh_test: PASS"
