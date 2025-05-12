#!/usr/bin/env just --justfile

set dotenv-required
set dotenv-load
set dotenv-filename := '.env'
set export


# Default target (list everything)
_default:
  @just --list

# Execute arbitrary shell commands within the justfile context
exec +args:
  {{ args }}

init:
  #!/usr/bin/env bash
  set -euxo pipefail

  echo "🔧 Verifying setup..."
  if ! command -v release-please >/dev/null; then
    echo "📦 Installing release-please globally..."
    npm install -g release-please
  else
    echo "✅ release-please is already installed"
  fi

  if ! command -v jq >/dev/null; then
    echo "❌ jq is not installed (required for manifest pretty-printing)"
    echo "👉 Install it via: brew install jq | sudo apt install jq | choco install jq"
    exit 1
  else
    echo "✅ jq is installed"
  fi

  if [ ! -f ${GITHUB_SECRET_FILE} ]; then
    echo "❌ Token file '${GITHUB_SECRET_FILE}' not found."
    exit 1
  fi

  export RELEASE_PLEASE_GITHUB_TOKEN=$(cat ${GITHUB_SECRET_FILE})
  echo "✅ GitHub token loaded from file"

  if [ ! -f .release-please-config.json ]; then
    echo "📝 Creating .release-please-config.json"
    echo '{ "packages": { ".": { "package-name": "test-package" } } }' > .release-please-config.json
  fi

  if [ ! -f .release-please-manifest.json ]; then
    echo "📝 Creating empty .release-please-manifest.json"
    echo '{}' > .release-please-manifest.json
  fi

  echo "✅ Initialization complete."

# 📊 Show project status: branch, tags, latest commit, manifest, dirty state
status:
  #!/usr/bin/env bash
  set -euo pipefail

  echo "📦 Project Status for omgwtfbbq"
  echo "🧠 Branch: $(git rev-parse --abbrev-ref HEAD)"
  echo "🔖 Tags:"
  git tag --list | sort || echo "  (no tags found)"
  echo "📝 Latest Commit:"
  git --no-pager log -1 --oneline
  echo "📂 Working Tree Status:"
  if [ -n "$$(git status --porcelain)" ]; then
    echo "❗ Uncommitted changes present:"
    git status --short
  else
    echo "✅ Clean"
  fi
  echo "📄 Manifest State:"
  if [ -f .release-please-manifest.json ]; then
    if command -v jq >/dev/null; then
      cat .release-please-manifest.json | jq
    else
      echo "  (jq not found — showing raw)"
      cat .release-please-manifest.json
    fi
  else
    echo "  (no manifest found)"
  fi

# 🔨 Generate scoped test commits for all omgwtfbbq packages
generate-commits mode="simple" path="src":
  bash ./generate_commits.sh {{mode}} {{path}}

# 🔁 Light reset for dev use (preserves commit history)
reset:
  #!/usr/bin/env bash
  set -euo pipefail
  git reset --hard HEAD
  git tag -d $(git tag) 2>/dev/null || true
  find . -name '__test_commit*' -exec rm -f {} \;
  echo "✅ Project reset (manifest preserved)"

# 🔁 Full test rollback (preserves manifest, resets commits)
rollback:
  #!/usr/bin/env bash
  set -euo pipefail
  git reset --hard test-base
  cp .release-please-manifest.json.bak .release-please-manifest.json || true
  rm -rf artifacts/
  echo "✅ Reset to test-base and restored manifest backup"

# 🏷️ Push tags to remote (optional, for real release testing)
push-tags:
  git push origin --tags

test-all:
  #!/usr/bin/env bash
  set -euo pipefail

  echo "💾 Backing up .release-please-manifest.json"
  cp .release-please-manifest.json .release-please-manifest.json.bak || true

  echo "🔖 Tagging pre-test baseline as 'test-base'"
  git tag -f test-base

  echo "🧼 Step 1: Reset (preserving manifest backup)"
  git reset --hard HEAD
  git tag -d $(git tag | grep -v test-base) 2>/dev/null || true
  find . -name '__test_commit*' -exec rm -f {} \;

  echo "🛠 Step 2: Generate conventional commits"
  just generate-commits

  echo "📦 Step 3: Run release-please dry-run"
  just release-pr dry-run

  echo "🧪 Step 4: Validate crate/chart version sync"
  just validate-all-versions

  echo "📦 Step 5: Package all Helm charts"
  just package-all-charts

  echo "📁 Step 6: Validate artifact presence"
  just test-artifacts

  echo "✅ All tests passed — end-to-end validation complete"


# 🎯 Do it all: init + generate commits + dry-run + live PR
all:
  just init
  just generate-commits
  just test-release-manifest
  just test-release-live

# 🐳 Local Docker build with tagging
build image_tag="":
  #!/usr/bin/env bash
  set -euo pipefail

  IMAGE_TAG="${image_tag:-$DOCKER_IMG_TAG}"
  echo docker buildx build --load \
    --file "$DOCKERFILE" \
    "$DOCKER_CTX" \
    --tag "$IMAGE_TAG" \
    --tag "$DOCKER_REPO/$IMAGE_TAG"


# 🚀 Remote Depot build
build-depot image_tag="":
  #!/usr/bin/env bash
  set -euo pipefail

  IMAGE_TAG="${image_tag:-$DOCKER_IMG_TAG}"

  echo depot build --load \
    --file ${DOCKERFILE} ${DOCKER_CTX} \
    --tag "$IMAGE_TAG" \
    --tag "$DOCKER_REPO/$IMAGE_TAG"

build-all image_tag="latest":
  docker buildx bake --file docker-bake.hcl \
    --set *.args.TAG={{image_tag}}

# 🧪 Run container with a name
run *args:
  docker run -it --rm \
    --name "${DOCKER_IMG_TAG//:/-}" \
    ${DOCKER_IMG_TAG} {{args}}

# 🧪 Run with bind-mount and working directory set
run_mount *args:
  docker run -it --rm \
    --name "${DOCKER_IMG_TAG//:/-}" \
    --mount type=bind,src=.,dst=/src \
    --workdir /src \
    ${DOCKER_IMG_TAG} {{args}}


package-chart chartDir:
  #!/usr/bin/env bash
  set -euo pipefail

  CHART_DIR="$chartDir"
  CHART_PATH="$CHART_DIR/Chart.yaml"
  CHART_NAME=$(yq e '.name' "$CHART_PATH")

  source .ci/manifest-utils.sh
  CHART_VERSION=$(get_manifest_version "$CHART_DIR")
  APP_VERSION=$(get_manifest_version "crates/$CHART_NAME")

  echo "📦 Packaging $CHART_NAME"
  echo "🔧 Updating $CHART_PATH: version=$CHART_VERSION, appVersion=$APP_VERSION"

  yq e -i ".version = \"$CHART_VERSION\"" "$CHART_PATH"
  yq e -i ".appVersion = \"$APP_VERSION\"" "$CHART_PATH"

  mkdir -p artifacts
  helm package "$CHART_DIR" -d ./artifacts

  PACKAGE_PATH=$(find ./artifacts -name "${CHART_NAME}-*.tgz" | head -n1)
  TARGET_PATH="./artifacts/${CHART_NAME}-${CHART_VERSION}.tgz"
  if [[ "$PACKAGE_PATH" != "$TARGET_PATH" ]]; then
    mv "$PACKAGE_PATH" "$TARGET_PATH"
  fi

  echo "✅ Chart written to: $TARGET_PATH"


package-all-charts:
  #!/usr/bin/env bash
  set -euo pipefail

  readarray -t CHART_DIRS < <(find . -name Chart.yaml -exec dirname {} \; | sed 's|^\./||')

  for dir in "${CHART_DIRS[@]}"; do
    just package-chart $dir
  done

  just generate-helm-index


# 📚 Generate Helm repo index for packaged charts
generate-helm-index:
    helm repo index artifacts --url https://example.com/charts
    echo "✅ index.yaml generated in ./artifacts"

validate-component-version chartDir:
  #!/usr/bin/env bash
  set -euo pipefail

  source .ci/manifest-utils.sh

  CHART_DIR="{{chartDir}}"
  CHART_PATH="$CHART_DIR/Chart.yaml"
  CHART_NAME=$(yq e '.name' "$CHART_PATH")

  CHART_VERSION=$(yq e '.version' "$CHART_PATH")
  APP_VERSION=$(yq e '.appVersion' "$CHART_PATH")

  MANIFEST_CHART_VERSION=$(get_manifest_version "$CHART_DIR")

  if [[ "$CHART_DIR" == "chart" ]]; then
    # Handle root package
    CRATE_PATH="."
    MANIFEST_CRATE_VERSION=$(get_manifest_version ".")
    CARGO_VERSION=$(grep '^version =' Cargo.toml | cut -d '"' -f2)
  else
    # Standard component
    CRATE_PATH="crates/$CHART_NAME"
    MANIFEST_CRATE_VERSION=$(get_manifest_version "$CRATE_PATH")
    CARGO_VERSION=$(grep '^version =' "$CRATE_PATH/Cargo.toml" | cut -d '"' -f2)
  fi

  # Compare Chart.yaml version vs manifest
  if [[ "$MANIFEST_CHART_VERSION" != "$CHART_VERSION" ]]; then
    echo "❌ MISMATCH: manifest($CHART_DIR)=$MANIFEST_CHART_VERSION vs Chart.yaml=$CHART_VERSION"
    exit 1
  fi

  # Compare Chart.yaml appVersion vs crate version
  if [[ "$MANIFEST_CRATE_VERSION" != "$APP_VERSION" ]]; then
    echo "❌ MISMATCH: manifest($CRATE_PATH)=$MANIFEST_CRATE_VERSION vs Chart.appVersion=$APP_VERSION"
    exit 1
  fi

  # Compare manifest vs Cargo.toml
  if [[ "$MANIFEST_CRATE_VERSION" != "$CARGO_VERSION" ]]; then
    echo "❌ MISMATCH: manifest($CRATE_PATH)=$MANIFEST_CRATE_VERSION vs Cargo.toml=$CARGO_VERSION"
    exit 1
  fi

  echo "✅ $CHART_NAME version check passed: $MANIFEST_CRATE_VERSION"


validate-all-versions:
  #!/usr/bin/env bash
  set -euo pipefail

  readarray -t CHART_DIRS < <(find . -name Chart.yaml -exec dirname {} \; | sed 's|^\./||')

  for dir in "${CHART_DIRS[@]}"; do
    just validate-component-version $dir
  done


test-artifacts:
  #!/usr/bin/env bash
  set -euo pipefail

  source .ci/manifest-utils.sh

  readarray -t CHART_DIRS < <(find . -name Chart.yaml -exec dirname {} \; | sed 's|^\./||')

  for dir in "${CHART_DIRS[@]}"; do
    CHART_PATH="$dir/Chart.yaml"
    CHART_NAME=$(yq e '.name' "$CHART_PATH")

    VERSION=$(get_manifest_version "$dir")
    EXPECTED_FILE="artifacts/${CHART_NAME}-${VERSION}.tgz"

    if [[ ! -f "$EXPECTED_FILE" ]]; then
      echo "❌ Missing artifact: $EXPECTED_FILE"
      exit 1
    else
      echo "✅ Found: $EXPECTED_FILE"
    fi
  done

  echo "✅ All expected artifacts are present."


release-pr mode="dry-run":
  #!/usr/bin/env bash
  set -euo pipefail

  MODE="{{mode}}"

  if [[ "$MODE" != "live" && "$MODE" != "dry-run" ]]; then
    echo "❌ Invalid mode: $MODE (expected 'live' or 'dry-run')"
    exit 1
  fi

  ARGS=(
    release-pr
    --token "$(cat $GITHUB_SECRET_FILE)"
    --repo-url "${GITHUB_REPO}"
    --target-branch main
    --config-file release-please-config.json
    --manifest-file .release-please-manifest.json
  )

  if [[ "$MODE" == "dry-run" ]]; then
    ARGS+=(--dry-run)
    echo "🔍 Running release-please in dry-run mode"
  else
    echo "🚀 Running release-please in live mode"
  fi

  release-please "${ARGS[@]}"


# release-please to open PRs on GitHub and bump versions for real
test-prod:
  #!/usr/bin/env bash
  set -euo pipefail

  echo "🚀 Running full release-please flow (live mode)"
  just release-pr live

  echo "✅ Release PR(s) created or updated successfully"

cleanup-remote-branches:
  #!/usr/bin/env bash
  set -euo pipefail

  echo "🔄 Cleaning up remote branches"
  gh api repos/:owner/:repo/branches --paginate --jq '.[].name | select(. != "main" and . != "gh-pages")' \
  | xargs -I {} git push origin --delete {}

  echo "✅ Remote branches cleaned up"

cleanup-release-tags:
  #!/usr/bin/env bash
  set -euo pipefail

  echo "🔄 Cleaning up releases and release-tags"
  gh release list --json tagName --jq '.[].tagName' \
  | xargs -I {} gh release delete {} --cleanup-tag \
  && \
  echo "🔄 Cleaning up remaining tags..."
  gh api repos/:owner/:repo/tags --paginate --jq '.[].name' \
  | xargs -I {} git push origin --delete {}

  echo "✅ Releases and tags cleaned up"

release-test:
  #!/usr/bin/env bash
  set -euo pipefail

  current_branch=$(git rev-parse --abbrev-ref HEAD)

  if [[ "$current_branch" != "main" ]]; then
    echo "Error: You must be on the 'main' branch. Current branch is '$current_branch'."
    exit 1
  fi


  BRANCH="branch-test-base"
  TAG="tag-test-base"
  git branch -D ${BRANCH} || true
  git checkout -b ${BRANCH}
  just cleanup-release-tags
  just cleanup-remote-branches

  echo "🔖 Tagging pre-test baseline as: ${TAG}"
  git tag -f ${TAG}
  git tag -d $(git tag | grep -v ${TAG}) 2>/dev/null || true
  find . -name '__test_commit*' -exec rm -f {} \;

  echo "🛠 Generate conventional commits"

  # just generate-commits simple src
  # just generate-commits simple crates/hello
  # just generate-commits simple crates/goodbye
  # just generate-commits simple crates/alright

  # just generate-commits full src
  # just generate-commits full crates/hello
  # just generate-commits full crates/goodbye
  # just generate-commits full crates/alright

  just generate-commits simple chart
  # just generate-commits simple charts/hello
  # just generate-commits simple charts/goodbye
  # just generate-commits simple charts/alright

  # just generate-commits full chart
  # just generate-commits full charts/hello
  # just generate-commits full charts/goodbye
  # just generate-commits full charts/alright

  git push origin ${BRANCH}

  echo "📦 Run release-please dry-run"
  just release-pr dry-run

  git push origin ${BRANCH}
  gh pr create --base "main" --title "chore(ci): release testing" --body "Adds conventional commits for testing" --head "${BRANCH}"

  PR_NUMBER=$(gh pr view --json number --jq .number)

  # gh pr review "${PR_NUMBER}" --approve --body "Looks good to me! 🚀"

  gh pr merge "${PR_NUMBER}" --merge --delete-branch

  echo "✅ Done"
