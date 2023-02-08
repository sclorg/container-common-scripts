#!/bin/bash

# This script is used to build the OpenShift Docker images.
#
# OS - Specifies distribution - "rhel7", "rhel8", "rhel9", "centos7", "c8s", "c9s" or "fedora"
# VERSION - Specifies the image version - (must match with subdirectory in repo)
# VERSIONS - Must be set to a list with possible versions (subdirectories)

set -e
[ -n "${DEBUG:-}" ] && set -x

OS=${1-$OS}
VERSION=${2-$VERSION}

error() { echo "ERROR: $*" ; false ; }


# _parse_output_inner
# -------------------
# Helper function for 'parse_output'.
# We need to avoid case statements in $() for older Bash versions (per issue
# postgresql-container#35, mac ships with 3.2).
# Example of problematic statement: echo $(case i in i) echo i;; esac)
_parse_output_inner ()
{
    set -o pipefail
    {
        case $stream in
        stdout|1|"")
            eval "$command" | tee >(cat - >&"$stdout_fd")
            ;;
        stderr|2)
            set +x # avoid stderr pollution
            eval "$command" {free_fd}>&1 1>&"$stdout_fd" 2>&"$free_fd" | tee >(cat - >&"$stderr_fd")
            ;;
        esac
        # Inherit correct exit status.
        (exit "${PIPESTATUS[0]}")
    } | eval "$filter"
}


# parse_output COMMAND FILTER_COMMAND OUTVAR [STREAM={stderr|stdout}]
# -------------------------------------------------------------------
# Parse standard (error) output of COMMAND with FILTER_COMMAND and store the
# output into variable named OUTVAR.  STREAM might be 'stdout' or 'stderr',
# defaults to 'stdout'.  The filtered output stays (live) printed to terminal.
# This method doesn't create any explicit temporary files.
# Defines:
#   ${$OUTVAR}: Set to FILTER_COMMAND output.
parse_output ()
{
  local command=$1 filter=$2 var=$3 stream=$4
  echo "-> building using $command"
  local raw_output='' rc=0
  {
      # shellcheck disable=SC2034
      raw_output=$(_parse_output_inner)
  } {stdout_fd}>&1 {stderr_fd}>&2
  rc=$?
  eval "$var=\$raw_output"
  (exit $rc)
}

# "best-effort" cleanup of image
function clean_image {
  for id_file in .image-id .image-id-from; do
    if test -f $id_file; then
        local id
        id=$(cat $id_file)
        test -n "$id" || continue
        docker rmi --force "$id" || :
        rm -f "$id_file" || :
    fi
  done
}

# Pull image based on FROM, before we build our own.
function pull_image {
  local dockerfile="$1"
  local loops=10
  local loop=0

  # Get image_name from Dockerfile before pulling.
  while read -r line; do
    if ! grep -q "^FROM" <<< "$line"; then
      continue
    fi

    image_name=$(echo "$line" | cut -d ' ' -f2)

    # In case FROM scratch is defined, skip it
    if [[ "$image_name" == "scratch" ]]; then
      continue
    fi
    echo "-> Pulling image $image_name before building image from $dockerfile."
    # Sometimes in Fedora case it fails with HTTP 50X
    # Check if the image is available locally and try to pull it if it is not
    if [[ "$(docker images -q "$image_name" 2>/dev/null)" != "" ]]; then
      echo "The image $image_name is already pulled."
      continue
    fi

    # Try pulling the image to see if it is accessible
    # WORKAROUND: Since Fedora registry sometimes fails randomly, let's try it more times
    while ! docker pull "$image_name" > .image-id-from; do
      ((loop++)) || :
      echo "Pulling image $image_name failed."
      [ "$loop" -gt "$loops" ] && { echo "It happened $loops times. Giving up." ; return 1; }
      echo "Let's wait $((loop*5)) seconds and try again."
      sleep "$((loop*5))"
    done

  done < "$dockerfile"
}

# Perform docker build but append the LABEL with GIT commit id at the end
function docker_build_with_version {
  local dockerfile="$1"
  local exclude=.exclude-${OS}
  local devel_repo_file=.devel-repo-${OS}
  local devel_repo_var="DEVEL_REPO_$OS"
  local is_podman
  if [ -e "$exclude" ]; then
    echo "-> $exclude file exists for version $dir, skipping build."
    clean_image
    return
  fi
  if [ ! -e "$dockerfile" ]; then
    echo "-> $dockerfile for version $dir does not exist, skipping build."
    clean_image
    return
  fi
  echo "-> Version ${dir}: building image from '${dockerfile}' ..."

  if [ "${NO_GIT_COMMAND:-"false"}" == "false" ] ; then
    git_version=$(git rev-parse --short HEAD)
    BUILD_OPTIONS+=" --label io.openshift.builder-version=\"${git_version}\""
  fi

  # Add possibility to use a development repo
  #
  # This is useful if we want to work with RPMs that are not available publically yet.
  #
  # How to use it:
  # First, we create a file that only tells the scripts to use the development repository,
  # e.g. .devel-repo-rhel8, similarly as we use .exclude-rhel8 for excluding particular
  # variant of the Dockerfile. Content of the file is not important at this point.
  #
  # If such a file exists in the repository, then the building scripts will take a look
  # at a correspondent variable, e.g.  DEVEL_REPO_rhel8, and will use the repository file
  # defined by that variable.
  #
  # That means that definition of the DEVEL_REPO_rhel8 variable is a responsibility of
  # the test/CI environment.
  if [ -f "$devel_repo_file" ] && [[ -v "$devel_repo_var" ]] ; then
    CUSTOM_REPO=$(mktemp)
    curl -Lk "${!devel_repo_var}" >"${CUSTOM_REPO}"
    echo "-> $devel_repo_file file exists for version $dir, so using ${!devel_repo_var}."
  fi

  if [ -n "$CUSTOM_REPO" ]; then
    if [ -f "$CUSTOM_REPO" ]; then
      BUILD_OPTIONS+=" -v $CUSTOM_REPO:/etc/yum.repos.d/sclorg_custom.repo:Z"
    elif [ -d "$CUSTOM_REPO" ]; then
      BUILD_OPTIONS+=" -v $CUSTOM_REPO:/etc/yum.repos.d/:Z"
    else
      echo "ERROR: file type not known: $CUSTOM_REPO" >&2
    fi
  fi

  pull_image "$dockerfile"

  docker info 2>/dev/null | grep podman 1>/dev/null && is_podman=1 || is_podman=0

  # squash is possible only for podman. In docker it is usable only in experimental mode.
  if [[ "$SKIP_SQUASH" -eq 0 ]] && [[ "$is_podman" -eq 1 ]]; then
    BUILD_OPTIONS+=" --squash"
  fi
  # shellcheck disable=SC2016
  parse_output 'docker build '"$BUILD_OPTIONS"' -f "$dockerfile" "${DOCKER_BUILD_CONTEXT}"' \
               "tail -n 1 | awk '/Successfully built|(^--> )?(Using cache )?[a-fA-F0-9]+$/{print \$NF}'" \
               IMAGE_ID
  echo "$IMAGE_ID" > .image-id
}

# Versions are stored in subdirectories. You can specify VERSION variable
# to build just one single version. By default we build all versions
dirs=${VERSION:-$VERSIONS}

for dir in ${dirs}; do
  pushd "${dir}" > /dev/null
  if [ "$OS" == "rhel8" ] || [ "$OS" == "rhel8-candidate" ]; then
    docker_build_with_version Dockerfile.rhel8
  elif [ "$OS" == "rhel9" ] || [ "$OS" == "rhel9-candidate" ]; then
    docker_build_with_version Dockerfile.rhel9
  elif [ "$OS" == "rhel7" ] || [ "$OS" == "rhel7-candidate" ]; then
    docker_build_with_version Dockerfile.rhel7
  elif [ "$OS" == "fedora" ] || [ "$OS" == "fedora-candidate" ]; then
    docker_build_with_version Dockerfile.fedora
  elif [ "$OS" == "centos6" ] || [ "$OS" == "centos6-candidate" ]; then
    docker_build_with_version Dockerfile.centos6
  elif [ "$OS" == "c8s" ] || [ "$OS" == "c8s-candidate" ]; then
    docker_build_with_version Dockerfile.c8s
  elif [ "$OS" == "c9s" ] || [ "$OS" == "c9s-candidate" ]; then
    docker_build_with_version Dockerfile.c9s
  else
    docker_build_with_version Dockerfile
  fi

  popd > /dev/null
done
