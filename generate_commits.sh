#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-simple}"
TARGET_PATH="${2:-src}"
TEST_FILE="$TARGET_PATH/__release_test.txt"

mkdir -p "$TARGET_PATH"
echo "🧪 Using path: $TARGET_PATH"
echo "📝 Commit mode: $MODE"

commits_simple=(
  "fix($TARGET_PATH): trigger a patch release"
)

commits_full=(
  "feat($TARGET_PATH): test a feature bump"
  "fix($TARGET_PATH): test a patch bump"
  "docs($TARGET_PATH): update docs"
  "style($TARGET_PATH): whitespace"
  "refactor($TARGET_PATH): internal refactor"
  "perf($TARGET_PATH): improve loop performance"
  "test($TARGET_PATH): add unit test"
  "chore($TARGET_PATH): clean up code"
  "refactor($TARGET_PATH)!: breaking change refactor

BREAKING CHANGE: major refactor"
)

# Initial commit to create the file
echo "initial commit for path $TARGET_PATH in mode $MODE - $(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$TEST_FILE"
git add "$TEST_FILE"
git commit -m "chore($TARGET_PATH): initial commit for $MODE mode"

# Select the right commit set
if [[ "$MODE" == "simple" ]]; then
  commits=("${commits_simple[@]}")
else
  commits=("${commits_full[@]}")
fi

i=0
for commit in "${commits[@]}"; do
  echo "change-$i" >> "$TEST_FILE"
  git add "$TEST_FILE"
  echo "🔨 Commit $i: $commit"
  git commit -m "$commit"
  ((i+=1))
done

echo "✅ $i commits created in $TARGET_PATH"
git --no-pager log --oneline -n $((i + 1))
