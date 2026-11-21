set -euo pipefail

COMPILER="$1"
CC="$2"
WORK_DIR="$3"
HOST="$(uname -s)"
STRICT=(-Werror=implicit-function-declaration -Werror=incompatible-pointer-types)
mkdir -p "${WORK_DIR}"

"${COMPILER}" b tests/native/thread.a "${WORK_DIR}/thread.c"
if [[ "${HOST}" == MINGW* || "${HOST}" == MSYS* ]]; then
    "${CC}" -std=gnu99 -O2 "${STRICT[@]}" "${WORK_DIR}/thread.c" -o "${WORK_DIR}/thread"
elif [[ "${CC}" == *tcc* ]]; then
    "${CC}" -std=c99 -D_POSIX_C_SOURCE=200809L -lpthread "${WORK_DIR}/thread.c" -o "${WORK_DIR}/thread"
else
    "${CC}" -std=gnu99 -D_POSIX_C_SOURCE=200809L -O2 -pthread "${STRICT[@]}" "${WORK_DIR}/thread.c" -o "${WORK_DIR}/thread"
fi

for _ in {1..5}; do
    timeout 15s "${WORK_DIR}/thread"
done

if [[ "${HOST}" == Linux ]] && command -v gcc >/dev/null; then
    "${COMPILER}" b tests/native/thread_failures.a "${WORK_DIR}/failures.c"
    gcc -std=gnu11 -pthread -O2 "${STRICT[@]}" "${WORK_DIR}/failures.c" tests/native/thread_faults.c \
        -Wl,--wrap=malloc,--wrap=free,--wrap=pthread_create,--wrap=pthread_join,--wrap=pthread_mutex_init \
        -Wl,--wrap=nanosleep \
        -o "${WORK_DIR}/failures"
    timeout 15s "${WORK_DIR}/failures"
fi

if command -v x86_64-w64-mingw32-gcc >/dev/null; then
    "${COMPILER}" b --target windows --arch x86_64 tests/native/thread.a "${WORK_DIR}/windows.c"
    x86_64-w64-mingw32-gcc -std=gnu99 -O2 "${STRICT[@]}" "${WORK_DIR}/windows.c" -o "${WORK_DIR}/thread.exe"
fi

cat > "${WORK_DIR}/unsupported.a" <<'ABYSS'
thread :: @import("std/thread")
answer :: fn() i32 { 42 }
start :: extern fn() { thread.spawn(answer) }
main :: fn() { start() }
ABYSS

reject() {
    local status=0
    timeout 15s "${COMPILER}" "$@" > "${WORK_DIR}/unsupported.log" 2>&1 || status=$?
    if [[ "${status}" != 1 ]] || ! rg -qF "threads require a hosted native target" "${WORK_DIR}/unsupported.log"; then
        cat "${WORK_DIR}/unsupported.log" >&2
        return 1
    fi
}

reject r "${WORK_DIR}/unsupported.a"
reject b --target wasi "${WORK_DIR}/unsupported.a" "${WORK_DIR}/wasi.c"
reject b --target freestanding "${WORK_DIR}/unsupported.a" "${WORK_DIR}/free.c"
[[ ! -e "${WORK_DIR}/wasi.c" && ! -e "${WORK_DIR}/free.c" ]]

cat > "${WORK_DIR}/sleep.a" <<'ABYSS'
thread :: @import("std/thread")
main :: fn() { thread.sleep(1).unwrap() }
ABYSS

reject r "${WORK_DIR}/sleep.a"

cat > "${WORK_DIR}/availability.a" <<'ABYSS'
thread :: @import("std/thread")
main :: fn() { print(thread.supported) }
ABYSS

[[ "$(timeout 15s "${COMPILER}" r "${WORK_DIR}/availability.a")" == false ]]
"${COMPILER}" b "${WORK_DIR}/availability.a" "${WORK_DIR}/availability.c"
if rg -q "abyss_native_thread_|pthread.h" "${WORK_DIR}/availability.c"; then
    printf 'Unused thread runtime was emitted\n' >&2
    exit 1
fi
