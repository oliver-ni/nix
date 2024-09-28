tmp() {
  dir=$(mktemp -d)
  alias leave="cd $(printf %q "$PWD"); rm -rf $(printf %q "$dir"); unalias leave"
  cd "$dir"
}
