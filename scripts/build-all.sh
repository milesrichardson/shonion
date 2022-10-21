cd "$(dirname "$(git rev-parse --git-dir)")"

BUILD_DYNAMIC=1 exec ./scripts/build.sh "$@"
