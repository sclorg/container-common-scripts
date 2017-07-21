#
# Test a container image.
#
# Always use sourced from a specific container testfile 
#
# reguires definition of CID_FILE_DIR
# CID_FILE_DIR=$(mktemp --suffix=<container>_test_cidfiles -d)
# reguires definition of TEST_LIST 
# TEST_LIST="\
# run_container_creation_tests
# run_doc_test <words_to_look_for_in_the_doc>"

# may be redefined in the specific container testfile
EXPECTED_EXIT_CODE=0

function cleanup() {
  for cid_file in $CID_FILE_DIR/* ; do
    CONTAINER=$(cat $cid_file)

    : "Stopping and removing container $CONTAINER..."
    docker stop $CONTAINER
    exit_status=$(docker inspect -f '{{.State.ExitCode}}' $CONTAINER)
    if [ "$exit_status" != "$EXPECTED_EXIT_CODE" ]; then
      : "Dumping logs for $CONTAINER"
      docker logs $CONTAINER
    fi
    docker rm $CONTAINER
    rm $cid_file
  done
  rmdir $CID_FILE_DIR
  : "Done."
}
trap cleanup EXIT SIGINT

function get_cid() {
  local name="$1" ; shift || return 1
  echo $(cat "$CID_FILE_DIR/$name")
}

function get_container_ip() {
  local id="$1" ; shift
  docker inspect --format='{{.NetworkSettings.IPAddress}}' $(get_cid "$id")
}

function wait_for_cid() {
  local max_attempts=10
  local sleep_time=1
  local attempt=1
  local result=1
  while [ $attempt -le $max_attempts ]; do
    [ -f $cid_file ] && [ -s $cid_file ] && break
    : "Waiting for container start..."
    attempt=$(( $attempt + 1 ))
    sleep $sleep_time
  done
}

# Make sure the invocation of docker run fails.
function assert_container_creation_fails() {

  # Time the docker run command. It should fail. If it doesn't fail,
  # container will keep running so we kill it with SIGKILL to make sure
  # timeout returns a non-zero value.
  set +e
  timeout -s SIGTERM --preserve-status 10s docker run --rm "$@" $IMAGE_NAME
  ret=$?
  set -e

  # Timeout will exit with a high number.
  if [ $ret -gt 128 ]; then
    return 1
  fi
}

# to pass some arguments you need to specify CONTAINER_ARGS variable
function create_container() {
  cid_file="$CID_FILE_DIR/$1" ; shift
  # create container with a cidfile in a directory for cleanup
  docker run ${CONTAINER_ARGS:-} --cidfile="$cid_file" -d $IMAGE_NAME "$@"
  : "Created container $(cat $cid_file)"
  wait_for_cid
}

function run_doc_test() {
  local tmpdir=$(mktemp -d)
  local f
  : "  Testing documentation in the container image"
  # Extract the help files from the container
  for f in help.1 ; do
    docker run --rm ${IMAGE_NAME} /bin/bash -c "cat /${f}" >${tmpdir}/$(basename ${f})
    # Check whether the files contain some important information
    for term in $@ ; do
      if ! cat ${tmpdir}/$(basename ${f}) | grep -F -q -e "${term}" ; then
        echo "ERROR: File /${f} does not include '${term}'."
        return 1
      fi
    done
  done
  # Check whether the files use the correct format
  if ! file ${tmpdir}/help.1 | grep -q roff ; then
    echo "ERROR: /help.1 is not in troff or groff format"
    return 1
  fi
  : "  Success!"
}

function run_all_tests() {
  for test_case in $TEST_LIST; do
    : "Running test $test_case"
    $test_case
  done;
}

