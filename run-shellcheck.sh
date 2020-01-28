#!/bin/bash

VERBOSE_OUTPUT=0

usage() {
  echo "Usage: $(basename "$0") [ -v|--verbose ]  <dir|file> [ <dir|file> ... ]"
}

verbose() {
  if [ "${VERBOSE_OUTPUT}" -eq 1 ] ; then
	  echo "$@" >&2
	fi
}

if [ $# -eq 0 ] ; then
  echo "ERROR: No arguments given."
  usage
  exit 1
fi

case $1 in
	-v|--verbose) VERBOSE_OUTPUT=1; shift ;;
esac

filter_files() {
  while read -r file ; do
    if [ -L "$file" ] ; then
			verbose "Ignoring symlink $file."
			continue
    fi
    verbose "Will scan $file"
		echo "$file"
  done
}

detect_shell_files() {
  find -H "$@" -type f -not -path '*/\.git/*' -exec grep -l '^#!/bin/\(bash\|sh\)' {} +
  find -H "$@" -name '*.sh' -not -path '*/\.git/*'
}

# Run shellcheck on all files (we should also ignore symlinks)
detect_shell_files "$@" | filter_files | sort -u | xargs shellcheck

# vim: set tabstop=2:shiftwidth=2:expandtab:
