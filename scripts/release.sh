#!/bin/zsh
# Tags main and pushes the tag, which starts the Release workflow.
#
#   zsh scripts/release.sh 0.2.0
set -euo pipefail
cd "${0:A:h:h}"

version=${1:?usage: release.sh <version>}
version=${version#v}
tag="v$version"
if [[ ! $version =~ '^[0-9]+(\.[0-9]+){1,3}(-[0-9A-Za-z.]+)?$' ]]; then
  print -u2 "Version must look like 1.2.3 (got $version)."
  exit 1
fi
[[ $(git branch --show-current) == main ]] || { print -u2 "Switch to main first."; exit 1; }
[[ -z $(git status --porcelain) ]] || { print -u2 "Commit or stash your changes first."; exit 1; }
git fetch --quiet origin main --tags
[[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || { print -u2 "Local main differs from origin/main. Pull or push first."; exit 1; }
if git rev-parse --quiet --verify "refs/tags/$tag" >/dev/null; then
  print -u2 "$tag already exists."
  exit 1
fi
latest=$(git tag --list 'v*' --sort=-version:refname | sed -n 1p)
print "Releasing $tag (previous: ${latest:-none})."

git tag -a "$tag" -m "Still $version"
git push origin "$tag"
print "Pushed $tag. Follow the build with: gh run watch \$(gh run list --workflow Release --limit 1 --json databaseId --jq '.[0].databaseId')"
