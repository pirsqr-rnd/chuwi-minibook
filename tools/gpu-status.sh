#!/bin/bash
# SPDX-License-Identifier: 0BSD
set -euo pipefail

readonly EXPECTED_GPU="ADL-N"

has_cmd() { command -v "$1" &>/dev/null; }

print_field() {
  printf "%-24s%s\n" "$1" "$2"
}

WARNINGS=()

add_warning() {
  WARNINGS+=("$1")
}

print_warn() {
  printf "%-24s\033[33mWARN\033[0m  %s\n" "$1" "$2"
  add_warning "${1}: ${2}"
}

require_not_root() {
  if (( EUID == 0 )); then
    echo "Do not run this script as root -- Vulkan and OpenCL" >&2
    echo "queries fail under sudo." >&2
    exit 1
  fi
}

# --- vulkan ---

vulkaninfo_field() {
  local output="$1"
  local field="$2"
  local line
  line="$(grep -m1 "${field}" <<< "${output}" || true)"
  echo "${line#*= }"
}

vulkan_video_codecs() {
  local direction="$1"
  local output="$2"
  local codecs=""

  local codec
  for codec in h264 h265 av1 vp9; do
    if grep -q "VK_KHR_video_${direction}_${codec}" <<< "${output}"; then
      codecs="${codecs:+${codecs} }${codec}"
    fi
  done
  echo "${codecs}"
}

check_vulkan() {
  echo "--- vulkan ---"
  echo ""

  if ! has_cmd vulkaninfo; then
    print_warn "vulkaninfo" "not found (install vulkan-tools)"
    return
  fi

  local vk_output
  vk_output="$(vulkaninfo 2>/dev/null \
    | grep -E '(deviceName|driverName|driverInfo|VK_KHR_video)' \
    || true)"

  if [[ -z "${vk_output}" ]]; then
    print_warn "vulkan" "vulkaninfo returned no output"
    return
  fi

  local name
  name="$(vulkaninfo_field "${vk_output}" "deviceName")"
  if [[ -z "${name}" ]]; then
    print_warn "gpu" "not found in vulkaninfo output"
  elif [[ "${name}" == *"${EXPECTED_GPU}"* ]]; then
    print_field "gpu" "${name}"
  else
    print_warn "gpu" "${name} (expected *${EXPECTED_GPU}*)"
  fi

  local driver_name driver_info
  driver_name="$(vulkaninfo_field "${vk_output}" "driverName")"
  driver_info="$(vulkaninfo_field "${vk_output}" "driverInfo")"
  if [[ -n "${driver_name}" ]]; then
    print_field "driver" \
      "${driver_name}${driver_info:+ (${driver_info})}"
  else
    print_warn "driver" "not found"
  fi

  local decode encode
  decode="$(vulkan_video_codecs "decode" "${vk_output}")"
  encode="$(vulkan_video_codecs "encode" "${vk_output}")"

  if [[ -n "${decode}" ]]; then
    print_field "decode" "${decode}"
  else
    print_field "decode" "<none>"
    add_warning "vulkan decode not enabled -- see GUIDE-ADVANCED.md"
  fi

  if [[ -n "${encode}" ]]; then
    print_field "encode" "${encode}"
  else
    print_field "encode" "<none>"
    add_warning "vulkan encode not enabled -- see GUIDE-ADVANCED.md"
  fi
}

# --- va-api ---

vaapi_codecs() {
  local direction="$1"
  local output="$2"
  local codecs=""

  local entrypoint
  if [[ "${direction}" == "decode" ]]; then
    entrypoint="VLD"
  else
    entrypoint="Enc"
  fi

  local pair
  for pair in H264:h264 HEVC:h265 VP9:vp9 AV1:av1; do
    local profile="${pair%%:*}"
    local label="${pair#*:}"
    if grep -q "VAProfile${profile}.*VAEntrypoint${entrypoint}" \
        <<< "${output}"; then
      codecs="${codecs:+${codecs} }${label}"
    fi
  done
  echo "${codecs}"
}

check_vaapi() {
  echo ""
  echo "--- va-api ---"
  echo ""

  if ! has_cmd vainfo; then
    print_warn "vainfo" "not found (install libva-utils)"
    return
  fi

  local va_output
  va_output="$(vainfo 2>&1 || true)"

  local driver
  driver="$(grep -m1 'Driver version' <<< "${va_output}" \
    | sed 's/.*Driver version: *//' || true)"

  if [[ -z "${driver}" ]]; then
    print_field "driver" "NOT AVAILABLE"
    add_warning "va-api driver not found -- see GUIDE-ADVANCED.md"
    return
  fi

  print_field "driver" "${driver}"

  local decode encode
  decode="$(vaapi_codecs "decode" "${va_output}")"
  encode="$(vaapi_codecs "encode" "${va_output}")"

  if [[ -n "${decode}" ]]; then
    print_field "decode" "${decode}"
  else
    print_field "decode" "<none>"
  fi

  if [[ -n "${encode}" ]]; then
    print_field "encode" "${encode}"
  else
    print_field "encode" "<none>"
  fi
}

# --- opencl ---

check_opencl() {
  echo ""
  echo "--- opencl ---"
  echo ""

  if ! has_cmd clinfo; then
    print_warn "clinfo" "not found (install clinfo)"
    return
  fi

  local devices
  devices="$(clinfo -l 2>/dev/null \
    | grep 'Device #' \
    | sed 's/.*Device #[0-9]*: *//' || true)"

  if [[ -n "${devices}" ]]; then
    print_field "device" "${devices//$'\n'/, }"
  else
    print_field "device" "NOT AVAILABLE"
    add_warning "opencl not available -- see GUIDE-ADVANCED.md"
  fi
}

# --- output ---

print_warnings() {
  if (( ${#WARNINGS[@]} == 0 )); then
    return
  fi

  echo ""
  echo "--- warnings ---"
  echo ""
  local warning
  for warning in "${WARNINGS[@]}"; do
    echo "${warning}"
  done
}

main() {
  require_not_root
  check_vulkan
  check_vaapi
  check_opencl
  print_warnings
}

main "$@"
