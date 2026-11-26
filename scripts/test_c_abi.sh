#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
COMPILER="${1:-${ABYSS_COMPILER:-${ROOT_DIR}/abyssc}}"
FIXTURES=tests/extern
mkdir -p "${ROOT_DIR}/tmp"
WORK_DIR=$(mktemp -d "${ROOT_DIR}/tmp/extern_test.XXXXXX")
export ABYSS_DEV="${ROOT_DIR}"
CC="${ABYSS_FFI_CC:-gcc}"

trap 'if [[ $? -ne 0 ]]; then printf "C ABI test artifacts: %s\n" "${WORK_DIR}" >&2; fi' EXIT

timeout 30s "${COMPILER}" b "${FIXTURES}/interop.a" "${WORK_DIR}/interop.c"
timeout 30s "${COMPILER}" b --library "${FIXTURES}/fixture.a" "${WORK_DIR}/fixture.c"
"${CC}" -std=c99 -D_POSIX_C_SOURCE=200809L -Werror=implicit-function-declaration -Werror=incompatible-pointer-types \
    "${WORK_DIR}/interop.c" "${WORK_DIR}/fixture.c" -o "${WORK_DIR}/interop"
printf 'extern ABI verified\n' > "${WORK_DIR}/expected"
timeout 10s "${WORK_DIR}/interop" > "${WORK_DIR}/native.out"
diff -u "${WORK_DIR}/expected" "${WORK_DIR}/native.out"

timeout 30s "${COMPILER}" b "${FIXTURES}/headers.a" "${WORK_DIR}/headers.c"
[[ $(grep -c '^#include <limits.h>$' "${WORK_DIR}/headers.c") -eq 1 ]]
if grep -Fq 'unused_abyss_test.h' "${WORK_DIR}/headers.c"; then
    printf 'Unused C header was emitted\n' >&2
    exit 1
fi
"${CC}" -std=c99 -D_POSIX_C_SOURCE=200809L -Werror=implicit-function-declaration -Werror=incompatible-pointer-types \
    "${WORK_DIR}/headers.c" -o "${WORK_DIR}/headers"
timeout 10s "${WORK_DIR}/headers"
if [[ "${ABYSS_TEST_OBJECT:-false}" == true ]]; then
    timeout 30s "${COMPILER}" b --emit-obj --hosted "${FIXTURES}/interop.a" "${WORK_DIR}/interop.o"
    timeout 30s "${COMPILER}" b --emit-obj --library "${FIXTURES}/fixture.a" "${WORK_DIR}/fixture.o"
    bash scripts/link_object.sh "${WORK_DIR}/interop.o" "${WORK_DIR}/fixture.o" -o "${WORK_DIR}/interop-elf"
    timeout 10s "${WORK_DIR}/interop-elf" > "${WORK_DIR}/object.out"
    diff -u "${WORK_DIR}/expected" "${WORK_DIR}/object.out"
    timeout 30s "${COMPILER}" b --emit-obj --hosted "${FIXTURES}/headers.a" "${WORK_DIR}/headers.o"
    bash scripts/link_object.sh "${WORK_DIR}/headers.o" -o "${WORK_DIR}/headers-elf"
    timeout 10s "${WORK_DIR}/headers-elf"
fi

for mode in r wasi freestanding; do
    args=(b --target "${mode}")
    if [[ "${mode}" == r ]]; then args=(r); fi
    for source in \
        'f :: extern ["stdlib.h"] "abs" fn(i32) i32|probe :: extern fn() u64 { f(1) as u64 }' \
        'T :: extern ["stdio.h"] "FILE" struct {}|probe :: extern fn() u64 { @sizeof(T) }' \
        'probe :: extern fn() u64 { @c_value("limits.h", "CHAR_BIT", u64) }'; do
        source+="|main :: fn() { probe() }"
        printf '%s\n' "${source//|/$'\n'}" > "${WORK_DIR}/unsupported.a"
        if "${COMPILER}" "${args[@]}" "${WORK_DIR}/unsupported.a" "${WORK_DIR}/unsupported.c" > "${WORK_DIR}/unsupported.log" 2>&1 ||
            ! grep -Fq 'C headers require a hosted native target' "${WORK_DIR}/unsupported.log"; then
            cat "${WORK_DIR}/unsupported.log" >&2
            exit 1
        fi
        [[ ! -e "${WORK_DIR}/unsupported.c" ]]
    done
done

if [[ "${ABYSS_TEST_WINE:-false}" != true ]]; then
    timeout 30s "${COMPILER}" b --library "${FIXTURES}/interop.a" "${WORK_DIR}/exports.c"
    "${CC}" -std=c99 -D_POSIX_C_SOURCE=200809L -fPIC -shared "${WORK_DIR}/exports.c" -o "${WORK_DIR}/exports.so"
    "${CC}" -std=c99 -D_POSIX_C_SOURCE=200809L -fPIC -shared "${WORK_DIR}/fixture.c" -o "${WORK_DIR}/fixture.so"
    python3 "${FIXTURES}/check_native.py" "${WORK_DIR}/exports.so" "${WORK_DIR}/fixture.so"
    timeout 10s env LD_PRELOAD="${WORK_DIR}/fixture.so" "${COMPILER}" r "${FIXTURES}/interop.a" > "${WORK_DIR}/vm.out"
    diff -u "${WORK_DIR}/expected" "${WORK_DIR}/vm.out"
fi

count=0
while IFS=$'\t' read -r name line message source; do
    case_file="${WORK_DIR}/${name}.a"
    output="${WORK_DIR}/${name}.c"
    printf '%s\n' "${source//|/$'\n'}" > "${case_file}"
    modes=(b r)
    if [[ "${ABYSS_TEST_OBJECT:-false}" == true ]]; then modes+=(elf); fi
    for mode in "${modes[@]}"; do
        args=("${mode}")
        if [[ "${mode}" == elf ]]; then args=(b --emit-obj --hosted); fi
        log="${WORK_DIR}/${name}.${mode}.log"
        status=0
        timeout 10s "${COMPILER}" "${args[@]}" "${case_file}" "${output}" > "${log}" 2>&1 || status=$?
        if [[ ${status} -ne 1 || -e "${output}" ]] ||
            ! grep -Fq -- "${message}" "${log}" ||
            ! grep -Fq -- "${name}.a:${line}:" "${log}"; then
            printf 'FAIL extern/%s (%s, exit %s)\n' "${name}" "${mode}" "${status}" >&2
            cat "${log}" >&2
            exit 1
        fi
    done
    count=$((count + 1))
done < "${FIXTURES}/diagnostics.tsv"

if [[ "${ABYSS_TEST_WINE:-false}" == true ]]; then
    printf '  ✔ PASS  %-36s [C; %s compile diagnostics per backend; VM shared fixture skipped under Wine]\n' "extern_abi" "${count}"
    exit 0
fi

printf '%s\n' 'missing :: extern "abyss_no_such_test_symbol" fn()' 'main :: fn() { missing() }' > "${WORK_DIR}/missing.a"
status=0
timeout 10s "${COMPILER}" r "${WORK_DIR}/missing.a" > "${WORK_DIR}/missing.log" 2>&1 || status=$?
if [[ ${status} -ne 1 ]] || ! grep -Fq 'undefined external symbol: abyss_no_such_test_symbol' "${WORK_DIR}/missing.log"; then
    cat "${WORK_DIR}/missing.log" >&2
    exit 1
fi

backends=C+VM
if [[ "${ABYSS_TEST_OBJECT:-false}" == true ]]; then backends+=+ELF; fi
printf '  ✔ PASS  %-36s [%s; %s compile diagnostics per backend and one VM runtime diagnostic]\n' "extern_abi" "${backends}" "${count}"
