# Copy local SDK sources out of cloud-synced folders before compiling.
# Coordinated source builds expect the matching Notchwork checkout beside Portkeeper.
prepare_notchwork() {
  local task_build="$1"
  local task_sdk="${NOTCHWORK_PACKAGE_PATH:-$PWD/../notchwork}"
  if [[ -n "$task_sdk" ]]; then
    [[ -f "$task_sdk/Package.swift" && -f "$task_sdk/LICENSE" ]] || { print -u2 'Invalid NOTCHWORK_PACKAGE_PATH'; return 1; }
    mkdir -p "$task_build/Notchwork"
    cp "$task_sdk/Package.swift" "$task_sdk/LICENSE" "$task_sdk/NOTICE" "$task_build/Notchwork/"
    ditto --norsrc "$task_sdk/Sources" "$task_build/Notchwork/Sources"
    ditto --norsrc "$task_sdk/Tests" "$task_build/Notchwork/Tests"
    export NOTCHWORK_PACKAGE_PATH="$task_build/Notchwork"
  fi
}
