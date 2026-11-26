#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-${ROOT_DIR}/abyssc}"
export ABYSS_DEV="${ROOT_DIR}"
export ABYSS_COMPILER="${COMPILER}"

mkdir -p "${ROOT_DIR}/tmp"
BUILD_DIR=$(mktemp -d "${ROOT_DIR}/tmp/pod_test.XXXXXX")
SONAR_BIN="${BUILD_DIR}/sonar"
"${COMPILER}" --map json="${ROOT_DIR}/pods/json/json" b "${ROOT_DIR}/pods/sonar/main.a" "${BUILD_DIR}/sonar.c"
gcc -std=gnu99 -D_POSIX_C_SOURCE=200809L -O2 "${BUILD_DIR}/sonar.c" -o "${SONAR_BIN}"

run_pod_test() {
    local POD_NAME="$1"
    local POD_PATH="pods/${POD_NAME}"
    local T_START=$(date +%s%3N)
    local LOG_FILE="${ROOT_DIR}/tmp/test_pod_${POD_NAME}.log"
    mkdir -p "${ROOT_DIR}/tmp"

    if "${SONAR_BIN}" test "${POD_PATH}" > "${LOG_FILE}" 2>&1; then
        local T_END=$(date +%s%3N)
        local T_MS=$((T_END - T_START))
        printf "  \033[1;32m✔ PASS\033[0m  %-36s \033[0;90m[Pod: %s]\033[0m \033[0;90m(%sms)\033[0m\n" "${POD_NAME}_unit_tests" "${POD_NAME}" "${T_MS}"
    else
        printf "  \033[1;31m✘ FAIL\033[0m  %-36s \033[1;31m[Pod: %s]\033[0m\n" "${POD_NAME}_unit_tests" "${POD_NAME}"
        cat "${LOG_FILE}"
        exit 1
    fi
}

PODS=(core std test json simd fmt)
for POD_NAME in "${PODS[@]}"; do
    run_pod_test "${POD_NAME}"
done

if [[ "${ABYSS_TEST_OBJECT:-false}" == true ]]; then
    POD_MAPS=(
        --map "test=${ROOT_DIR}/pods/test"
        --map "json=${ROOT_DIR}/pods/json/json"
        --map "simd=${ROOT_DIR}/pods/simd"
        --map "fmt=${ROOT_DIR}/pods/fmt"
    )
    for POD_NAME in "${PODS[@]}"; do
        LOG_FILE="${ROOT_DIR}/tmp/test_pod_${POD_NAME}_elf.log"
        : > "${LOG_FILE}"
        for SUITE in "${ROOT_DIR}/pods/${POD_NAME}/tests/"test_*.a; do
            if ! {
                timeout 30s "${COMPILER}" "${POD_MAPS[@]}" b --emit-obj --hosted "${SUITE}" "${BUILD_DIR}/suite.o" &&
                bash "${ROOT_DIR}/scripts/link_object.sh" "${BUILD_DIR}/suite.o" -o "${BUILD_DIR}/suite" &&
                timeout 10s "${BUILD_DIR}/suite"
            } >> "${LOG_FILE}" 2>&1; then
                printf "  \033[1;31m✘ FAIL\033[0m  %-36s \033[1;31m[Pod: %s, ELF]\033[0m\n" "${SUITE##*/}" "${POD_NAME}"
                cat "${LOG_FILE}"
                exit 1
            fi
        done
        printf "  \033[1;32m✔ PASS\033[0m  %-36s \033[0;90m[Pod: %s, ELF]\033[0m\n" "${POD_NAME}_unit_tests_elf" "${POD_NAME}"
    done
fi

FMT_VM_LOG="${ROOT_DIR}/tmp/test_pod_fmt_vm.log"
: > "${FMT_VM_LOG}"
for SUITE in "${ROOT_DIR}"/pods/fmt/tests/test_*.a; do
    if ! timeout 10s "${COMPILER}" --map "fmt=${ROOT_DIR}/pods/fmt" --map "test=${ROOT_DIR}/pods/test" r "${SUITE}" >> "${FMT_VM_LOG}" 2>&1; then
        printf "  \033[1;31m✘ FAIL\033[0m  %-36s \033[1;31m[Pod: fmt, VM]\033[0m\n" "${SUITE##*/}"
        cat "${FMT_VM_LOG}"
        exit 1
    fi
done
printf "  \033[1;32m✔ PASS\033[0m  %-36s \033[0;90m[Pod: fmt, VM]\033[0m\n" "fmt_unit_tests_vm"
