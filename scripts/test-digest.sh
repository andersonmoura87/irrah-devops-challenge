#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
printf -v hex '%064d' 0
valid="sha256:$hex"
passed=0
failed=0

check() {
  local name=$1 expected=$2 value=$3 actual
  if bash "$script_dir/validate-digest.sh" "$value" >/dev/null 2>&1; then
    actual=0
  else
    actual=$?
  fi
  if [[ "$actual" -eq "$expected" ]]; then
    printf 'PASS %s\n' "$name"
    passed=$((passed + 1))
  else
    printf 'FAIL %s: expected=%s actual=%s\n' "$name" "$expected" "$actual" >&2
    failed=$((failed + 1))
  fi
}

check valid 0 "$valid"
check valid_hex_letters 0 "sha256:${hex//0/a}"
check invalid_prefix 1 "prefix-$valid"
check invalid_suffix 1 "$valid-suffix"
check newline_before 1 $'\n'"$valid"
check newline_after 1 "$valid"$'\n'
check original_multiline_regression 1 $'prefix-invalid\n'"$valid"
check carriage_return_before 1 $'\r'"$valid"
check carriage_return_after 1 "$valid"$'\r'
check crlf_after 1 "$valid"$'\r\n'
check leading_space 1 " $valid"
check trailing_space 1 "$valid "
check embedded_space 1 "sha256: ${hex:1}"
check short 1 "sha256:${hex:1}"
check long 1 "${valid}0"
check uppercase 1 "sha256:${hex//0/A}"
check non_hex 1 "sha256:g${hex:1}"
check empty 1 ''

printf '%s passed; %s failed\n' "$passed" "$failed"
[[ "$failed" -eq 0 ]]
