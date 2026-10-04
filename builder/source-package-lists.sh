#!/bin/bash

select_source_package_lists() {
  local source_dir="$1"

  if [[ -f $source_dir/install/unbloarchy-base.packages &&
    -f $source_dir/install/unbloarchy-other.packages ]]; then
    base_pkg_lists=(
      "$source_dir/install/unbloarchy-base.packages"
      "$source_dir/install/unbloarchy-other.packages"
    )
  elif [[ -f $source_dir/install/omarchy-base.packages &&
    -f $source_dir/install/omarchy-other.packages ]]; then
    base_pkg_lists=(
      "$source_dir/install/omarchy-base.packages"
      "$source_dir/install/omarchy-other.packages"
    )
  else
    return 1
  fi
}
