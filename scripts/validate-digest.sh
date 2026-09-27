#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

# Validate the whole input; never echo an untrusted value into the job log.
digest=${1-}
if [[ $# -ne 1 || ${#digest} -ne 71 || "$digest" == *$'\r'* || "$digest" == *$'\n'* || ! "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo 'Digest invalido: use sha256: seguido de 64 caracteres hexadecimais minusculos.' >&2
  exit 1
fi
