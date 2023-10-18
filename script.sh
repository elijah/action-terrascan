#!/bin/bash

# Print commands for debugging
if [[ "$RUNNER_DEBUG" == "1" ]]; then
  set -x
fi

# Fail fast on errors, unset variables, and failures in piped commands
set -Eeuo pipefail

# shellcheck disable=SC2001
WORKING_DIRECTORY="$(echo "$WORKING_DIRECTORY" | sed -e 's:\/$::')"
cd "${WORKING_DIRECTORY}" || exit

# Install terrascan
echo '::group::Installing terrascan ...'
# Download and install terrascan
version="${TERRASCAN_VERSION:?}"
platform="${TERRASCAN_PLATFORM:?}"
curl -L "$(curl -s https://api.github.com/repos/tenable/terrascan/releases/"${version}" | grep -o -E "https://.+?_${platform}.tar.gz")" >terrascan.tar.gz
tar -xf terrascan.tar.gz terrascan && rm terrascan.tar.gz
install terrascan /usr/local/bin && rm terrascan
echo "terrascan is installed at $(which terrascan)."
echo '::endgroup::'

# Scan
echo '::group::Scan ...'
# Allow failures now, as reviewdog handles them
set +Eeuo pipefail

scan_results="terrascan-results.json"
# shellcheck disable=SC2046
terrascan scan \
  --output json \
  $(if [[ "x${TERRASCAN_CONFIG_PATH}" != "x" ]]; then echo "--config-path ${TERRASCAN_CONFIG_PATH}"; fi) \
  $(if [[ "x${TERRASCAN_LOG_LEVEL}" != "x" ]]; then echo "--log-level ${TERRASCAN_LOG_LEVEL}"; fi) \
  $(if [[ "x${TERRASCAN_IAC_DIR}" != "x" ]]; then echo "--iac-dir ${TERRASCAN_IAC_DIR}"; fi) \
  $(if [[ "x${TERRASCAN_IAC_TYPE}" != "x" ]]; then echo "--iac-type ${TERRASCAN_IAC_TYPE}"; fi) \
  $(if [[ "x${TERRASCAN_POLICY_PATH}" != "x" ]]; then echo "--policy-path ${TERRASCAN_POLICY_PATH}"; fi) \
  $(if [[ "x${TERRASCAN_POLICY_TYPE}" != "x" ]]; then echo "--policy-type ${TERRASCAN_POLICY_TYPE}"; fi) \
  $(if [[ "x${TERRASCAN_REMOTE_TYPE}" != "x" ]]; then echo "--remote-type ${TERRASCAN_REMOTE_TYPE}"; fi) \
  $(if [[ "x${TERRASCAN_REMOTE_URL}" != "x" ]]; then echo "--remote-url ${TERRASCAN_REMOTE_URL}"; fi) \
  $(if [[ "x${TERRASCAN_SCAN_RULES}" != "x" ]]; then echo "--scan-rules ${TERRASCAN_SCAN_RULES}"; fi) \
  $(if [[ "x${TERRASCAN_SEVERITY}" != "x" ]]; then echo "--severity ${TERRASCAN_SEVERITY}"; fi) \
  $(if [[ "x${TERRASCAN_SKIP_RULES}" != "x" ]]; then echo "--skip-rules ${TERRASCAN_SKIP_RULES}"; fi) \
  $(if [[ "x${TERRASCAN_USE_COLORS}" != "x" ]]; then echo "--use-colors ${TERRASCAN_USE_COLORS}"; fi) \
  $(if [[ "x${TERRASCAN_VERBOSE}" != "x" ]]; then echo "--verbose"; fi) |
  tee "$scan_results"
terrascan_exit_code="${PIPESTATUS[0]}"

# Convert to a single line
echo "terrascan-results=$(cat <"$scan_results" | jq -r -c '.')" >> "$GITHUB_OUTPUT"
# The number of violations
violations_count="$(cat <"$scan_results" | jq -r '.results.violations | length')"
echo "terrascan-violations-count=${violations_count}" >> "$GITHUB_OUTPUT"
# Terrascan exit code
echo "terrascan-exit-code=${terrascan_exit_code}" >> "$GITHUB_OUTPUT"

set -Eeuo pipefail
echo '::endgroup::'

# reviewdog
echo '::group::reviewdog...'
# Allow failures now, as reviewdog handles them
set +Eeuo pipefail

scan_results_rdjson="terrascan-results.rdjson"
cat <"$scan_results" |
  jq -r -f "${GITHUB_ACTION_PATH}/to-rdjson.jq" |
  tee >"$scan_results_rdjson"

cat <"$scan_results_rdjson" |
  reviewdog -f=rdjson \
    -name="terrascan" \
    -reporter="${REVIEWDOG_REPORTER}" \
    -level="${REVIEWDOG_LEVEL}" \
    -fail-on-error="${REVIEWDOG_FAIL_ON_ERROR}" \
    -filter-mode="${REVIEWDOG_FILTER_MODE}"

reviewdog_return_code="${PIPESTATUS[1]}"
echo "terrascan-results-rdjson=$(cat <"$scan_results_rdjson" | jq -r -c '.')" >> "$GITHUB_OUTPUT"  # Convert to a single line
echo "reviewdog-return-code=${reviewdog_return_code}" >> "$GITHUB_OUTPUT"

set -Eeuo pipefail
echo '::endgroup::'

# exit
if [[ "x${ONLY_WARN}" == "x" && "${violations_count}" != "0" ]]; then
  exit 1
fi
