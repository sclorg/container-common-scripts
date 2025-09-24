# Common function for build.sh, tag.sh, and test.sh

# shellcheck disable=SC2148
if [ -z "${sourced_common_lib:-}" ]; then
  sourced_common_lib=1
else
  return 0
fi

analyze_logs_by_logdetective() {
  # logdetective should not break the test functionality
  # Therefore `set +e` is setup
  local log_file_name="$1"
  echo "Sending failed log by fpaste command to paste bin."
  paste_bin_link=$(fpaste "$log_file_name")
  # shellcheck disable=SC2181
  if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to send log file to private bin: ${log_file_name}"
    return
  fi
  # pastebin link is "https://paste.centos.org/view/ee98ba05"
  # We need a raw link that is "https://paste.centos.org/view/raw/ee98ba05"
  raw_paste_bin_link="${paste_bin_link//view/view\/raw}"
  echo "Sending log file to logdetective server: ${raw_paste_bin_link}"
  echo "-------- LOGDETECTIVE TEST LOG ANALYSIS START --------"
  logdetective_test_file=$(mktemp "/tmp/logdetective_test.XXXXXX")
  # shellcheck disable=SC2181
  if ! curl -k --insecure --header "Content-Type: application/json" --request POST --data "{\"url\":\"${raw_paste_bin_link}\"}" "$LOGDETECTIVE_SERVER/analyze" >> "${logdetective_test_file}"; then
    echo "ERROR: Failed to analyze log file by logdetective server."
    cat "${logdetective_test_file}"
    echo "-------- LOGDETECTIVE TEST LOG ANALYSIS FAILED --------"
    return
  fi
  jq -rC '.explanation.text' < "${logdetective_test_file}"
  # This part of code is from https://github.com/teemtee/tmt/blob/main/tmt/steps/scripts/tmt-file-submit
  if [ -z "$TMT_TEST_PIDFILE" ]; then
    echo "File submit to data dir can be used only in the context of a running test."
    return
  fi
  # This variable is set by tmt
  [ -d "$TMT_TEST_DATA" ] || mkdir -p "$TMT_TEST_DATA"
  cp -f "${logdetective_test_file}" "$TMT_TEST_DATA"
  echo "File '${logdetective_test_file}' stored to '$TMT_TEST_DATA'."
  echo "-------- LOGDETECTIVE TEST LOG ANALYSIS FINISHED --------"
}
