cd "$(dirname "$(git rev-parse --git-dir)")"

executable_name="shonion-$(./scripts/get-host-triple.sh)"
executable_path="bin/$executable_name"

cp target/release/shonion "$executable_path"
git add "$executable_path"
current_commitish=$(git rev-parse HEAD | cut -c-8)
git commit -m '[bin] update `'"$executable_name"'` (built from '"$current_commitish"')'
