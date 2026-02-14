#!/usr/bin/env bash
set -euo pipefail

# SLM-Copilot QCOW2 Build Wrapper
# Checks dependencies, downloads base image, runs Packer, compresses, checksums.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INPUT_DIR="${INPUT_DIR:-${SCRIPT_DIR}/build/images}"
OUTPUT_DIR="${OUTPUT_DIR:-${SCRIPT_DIR}/build/export}"
ONE_APPS_DIR="${ONE_APPS_DIR:-${SCRIPT_DIR}/build/one-apps}"
PACKER_DIR="${SCRIPT_DIR}/build/packer"
HEADLESS="${HEADLESS:-true}"
VERSION="${VERSION:-1.0.0}"
APPLIANCE_NAME="slm-copilot"
IMAGE_NAME="${APPLIANCE_NAME}-${VERSION}.qcow2"

UBUNTU_IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
ONE_APPS_GIT_URL="https://github.com/OpenNebula/one-apps.git"

check_dependencies() {
    local _missing=0

    for cmd in packer qemu-img cloud-localds qemu-system-x86_64; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            echo "ERROR: Required command '${cmd}' not found in PATH"
            _missing=$((_missing + 1))
        fi
    done

    if [ ! -e /dev/kvm ]; then
        echo "ERROR: /dev/kvm not found -- KVM acceleration is required"
        _missing=$((_missing + 1))
    elif [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
        echo "ERROR: /dev/kvm is not accessible -- check permissions (add user to kvm group)"
        _missing=$((_missing + 1))
    fi

    if [ "${_missing}" -gt 0 ]; then
        echo "ERROR: ${_missing} missing dependency(ies). Install them and retry."
        exit 1
    fi

    echo "==> All dependencies found."
}

download_base_image() {
    if [ -f "${INPUT_DIR}/ubuntu2404.qcow2" ]; then
        echo "==> Base image found, skipping download."
        return
    fi

    echo "==> Downloading Ubuntu 24.04 cloud image..."
    mkdir -p "${INPUT_DIR}"
    curl -fSL -o "${INPUT_DIR}/ubuntu2404.qcow2" "${UBUNTU_IMAGE_URL}"
    echo "==> Base image downloaded to ${INPUT_DIR}/ubuntu2404.qcow2"
}

setup_one_apps() {
    if [ -d "${ONE_APPS_DIR}" ]; then
        echo "==> one-apps found at ${ONE_APPS_DIR}"
    else
        echo "==> Cloning one-apps from ${ONE_APPS_GIT_URL}..."
        git clone --depth 1 "${ONE_APPS_GIT_URL}" "${ONE_APPS_DIR}"
    fi

    if [ ! -f "${ONE_APPS_DIR}/appliances/service.sh" ]; then
        echo "ERROR: ${ONE_APPS_DIR}/appliances/service.sh not found."
        echo "       Ensure ONE_APPS_DIR points to a valid one-apps checkout."
        exit 1
    fi

    echo "==> one-apps framework verified."
}

run_packer() {
    echo "==> Running Packer build..."
    cd "${PACKER_DIR}"
    packer init .
    packer build \
        -var "input_dir=${INPUT_DIR}" \
        -var "output_dir=${OUTPUT_DIR}" \
        -var "headless=${HEADLESS}" \
        -var "version=${VERSION}" \
        -var "one_apps_dir=${ONE_APPS_DIR}" \
        .
    cd "${SCRIPT_DIR}"
}

compress_image() {
    echo "==> Compressing QCOW2 image..."
    qemu-img convert -c -O qcow2 \
        "${OUTPUT_DIR}/${APPLIANCE_NAME}.qcow2" \
        "${OUTPUT_DIR}/${IMAGE_NAME}"
    rm -f "${OUTPUT_DIR}/${APPLIANCE_NAME}.qcow2"
    echo "==> Compressed image: $(du -h "${OUTPUT_DIR}/${IMAGE_NAME}" | cut -f1)"
}

generate_checksums() {
    echo "==> Generating checksums..."
    cd "${OUTPUT_DIR}"
    sha256sum "${IMAGE_NAME}" > "${IMAGE_NAME}.sha256"
    md5sum "${IMAGE_NAME}" > "${IMAGE_NAME}.md5"
    echo "SHA256: $(cat "${IMAGE_NAME}.sha256")"
    echo "MD5:    $(cat "${IMAGE_NAME}.md5")"
    cd "${SCRIPT_DIR}"
}

main() {
    echo "==> SLM-Copilot Build (v${VERSION})"
    echo ""

    check_dependencies
    download_base_image
    setup_one_apps
    run_packer
    compress_image
    generate_checksums

    echo ""
    echo "==> Build complete: ${OUTPUT_DIR}/${IMAGE_NAME}"
}

main "$@"
