#!/usr/bin/env bash
set -euo pipefail

: "${GITOPS_REPO:?GITOPS_REPO must be set}"
: "${IMAGE_NAME:?IMAGE_NAME must be set}"
: "${IMAGE_TAG:?IMAGE_TAG must be set}"
: "${TARGET_ENVIRONMENT:=staging}"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

git clone --depth 1 "$GITOPS_REPO" "$TMP_DIR"
cd "$TMP_DIR"

KUSTOMIZATION_PATH="overlays/${TARGET_ENVIRONMENT}/kustomization.yaml"
if [[ ! -f "$KUSTOMIZATION_PATH" ]]; then
  echo "Kustomization file not found: $KUSTOMIZATION_PATH" >&2
  exit 1
fi

TARGET_ENVIRONMENT="$TARGET_ENVIRONMENT" IMAGE_NAME="$IMAGE_NAME" IMAGE_TAG="$IMAGE_TAG" python3 - <<'PY'
import os
from pathlib import Path

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"PyYAML is required for this script: {exc}")

path = Path("overlays") / os.environ["TARGET_ENVIRONMENT"] / "kustomization.yaml"
content = yaml.safe_load(path.read_text()) or {}
images = content.setdefault("images", [])
image_name = os.environ["IMAGE_NAME"]
image_tag = os.environ["IMAGE_TAG"]

matched = False
for image in images:
    if image.get("name") == image_name:
        image["newTag"] = image_tag
        matched = True
        break

if not matched:
    images.append({"name": image_name, "newTag": image_tag})

path.write_text(yaml.safe_dump(content, sort_keys=False), encoding="utf-8")
PY

git config user.name "GitHub Actions Bot"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add "$KUSTOMIZATION_PATH"
if git diff --cached --quiet; then
  echo "No change to commit."
  exit 0
fi

git commit -m "chore: update ${TARGET_ENVIRONMENT} image to ${IMAGE_TAG}"
git push origin HEAD:main
