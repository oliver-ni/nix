typeset -ga _tmp_dirs _tmp_origins

tmp() {
  local dir origin=$PWD
  dir=$(mktemp -d) || return
  if ! builtin cd -- "$dir"; then
    rmdir -- "$dir"
    return 1
  fi
  _tmp_dirs+=("$dir")
  _tmp_origins+=("$origin")
}

leave() {
  if (( ! ${#_tmp_dirs} )); then
    print -u2 -- "No temporary directory to leave."
    return 1
  fi
  local dir=$_tmp_dirs[-1]
  builtin cd -- "$_tmp_origins[-1]" || return
  command rm -rf -- "$dir" || return
  _tmp_dirs[-1]=()
  _tmp_origins[-1]=()
}
