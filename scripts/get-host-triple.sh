rustc -vV | awk '/^host/{ print $2 }' | tr -d '[[:space:]]'
