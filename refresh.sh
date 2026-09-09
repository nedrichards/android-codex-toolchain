#!/usr/bin/env bash
set -euo pipefail

# Lightweight Codex Cloud maintenance script. Run this from the Android
# repository after a cached environment has checked out the requested branch.

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/android-sdk}"
ANDROID_HOME="$ANDROID_SDK_ROOT"

export ANDROID_HOME
export ANDROID_SDK_ROOT
export PATH="$ANDROID_SDK_ROOT/platform-tools:$PATH"

printf 'sdk.dir=%s\n' "$ANDROID_SDK_ROOT" > local.properties

prefetch_gradle_dependencies() {
    [[ -x ./gradlew ]] || return 0

    local init_script
    init_script="$(mktemp --suffix=.gradle)"
    trap 'rm -f "$init_script"' RETURN

    cat > "$init_script" <<'EOF'
gradle.projectsEvaluated {
    def root = gradle.rootProject

    root.tasks.register("codexResolveAllDependencies") {
        group = "codex"
        description = "Resolve all resolvable configurations for offline Codex use"

        doLast {
            root.allprojects.each { project ->
                project.configurations
                    .findAll { it.canBeResolved }
                    .sort { a, b -> a.name <=> b.name }
                    .each { configuration ->
                        logger.lifecycle("Resolving ${project.path}:${configuration.name}")
                        configuration.resolve()
                    }
            }
        }
    }
}
EOF

    echo "Prefetching all resolvable Gradle configurations..."
    ./gradlew \
        --no-daemon \
        --stacktrace \
        --init-script "$init_script" \
        codexResolveAllDependencies

    echo "Verifying the Gradle dependency cache offline..."
    ./gradlew \
        --offline \
        --no-daemon \
        --stacktrace \
        --init-script "$init_script" \
        codexResolveAllDependencies
}

prefetch_gradle_dependencies
