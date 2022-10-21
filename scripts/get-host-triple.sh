host_triple="$(rustc -vV | awk '/^host/{ print $2 }' | tr -d '[[:space:]]')"

if test -z "$host_triple" ; then
  >&2 echo "Error: failed to parse host_triple from system"
  >&2 echo "Set it explicitly with export HOST_TRIPLE=\"...\""
  exit 2
fi


echo -n "$host_triple"
