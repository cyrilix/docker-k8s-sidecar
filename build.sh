#! /bin/bash

IMG_NAME=cyrilix/k8s-sidecar
VERSION=0.1.144
MAJOR_VERSION=0.1
export DOCKER_CLI_EXPERIMENTAL=enabled

set -e

init_qemu() {
    local qemu_url='https://github.com/multiarch/qemu-user-static/releases/download/v2.9.1-1'

    docker run --rm --privileged multiarch/qemu-user-static:register --reset

    for target_arch in aarch64 arm x86_64; do
        wget "${qemu_url}/x86_64_qemu-${target_arch}-static.tar.gz";
        tar -xvf "x86_64_qemu-${target_arch}-static.tar.gz";
    done
}

fetch_sources() {
    if [[ ! -d  prometheus ]] ;
    then
        git clone https://github.com/kiwigrid/k8s-sidecar
    fi
    cd k8s-sidecar
    git checkout ${VERSION}
}

build_and_push_images() {
    local arch="$1"
    local dockerfile="$2"

    docker build --file "${dockerfile}" --tag "${IMG_NAME}:${arch}-latest" .
    docker tag "${IMG_NAME}:${arch}-latest" "${IMG_NAME}:${arch}-${VERSION}"
    docker tag "${IMG_NAME}:${arch}-latest" "${IMG_NAME}:${arch}-${MAJOR_VERSION}"
    docker push "${IMG_NAME}:${arch}-latest"
    docker push "${IMG_NAME}:${arch}-${VERSION}"
    docker push "${IMG_NAME}:${arch}-${MAJOR_VERSION}"
}


build_manifests() {
    docker -D manifest create "${IMG_NAME}:${VERSION}" "${IMG_NAME}:amd64-${VERSION}" "${IMG_NAME}:arm-${VERSION}" "${IMG_NAME}:arm64-${VERSION}" --amend
    docker -D manifest annotate "${IMG_NAME}:${VERSION}" "${IMG_NAME}:arm-${VERSION}" --os=linux --arch=arm --variant=v6
    docker -D manifest annotate "${IMG_NAME}:${VERSION}" "${IMG_NAME}:arm64-${VERSION}" --os=linux --arch=arm64 --variant=v8
    docker -D manifest push "${IMG_NAME}:${VERSION}"

    docker -D manifest create "${IMG_NAME}:latest" "${IMG_NAME}:amd64-latest" "${IMG_NAME}:arm-latest" "${IMG_NAME}:arm64-latest" --amend
    docker -D manifest annotate "${IMG_NAME}:latest" "${IMG_NAME}:arm-latest" --os=linux --arch=arm --variant=v6
    docker -D manifest annotate "${IMG_NAME}:latest" "${IMG_NAME}:arm64-latest" --os=linux --arch=arm64 --variant=v8
    docker -D manifest push "${IMG_NAME}:latest"

    docker -D manifest create "${IMG_NAME}:${MAJOR_VERSION}" "${IMG_NAME}:amd64-${MAJOR_VERSION}" "${IMG_NAME}:arm-${MAJOR_VERSION}" "${IMG_NAME}:arm64-${MAJOR_VERSION}"  --amend
    docker -D manifest annotate "${IMG_NAME}:${MAJOR_VERSION}" "${IMG_NAME}:arm-${MAJOR_VERSION}" --os=linux --arch=arm --variant=v6
    docker -D manifest annotate "${IMG_NAME}:${MAJOR_VERSION}" "${IMG_NAME}:arm64-${MAJOR_VERSION}" --os=linux --arch=arm64 --variant=v8
    docker -D manifest push "${IMG_NAME}:${MAJOR_VERSION}"
}

patch_dockerfile() {
    local dockerfile_orig=$1
    local dockerfile_dest=$2
    local docker_arch=$3
    local qemu_arch=$4

    sed "s#\(FROM \)\(node:.*\)#\1${docker_arch}/\2\n\nCOPY qemu-${qemu_arch}-static /usr/bin/\n#" ${dockerfile_orig} > ${dockerfile_dest}
    sed -i "s#FROM .*node:.*-alpine#FROM ${docker_arch}/node:6#" ${dockerfile_dest}

    sed "s#\(FROM.*\)#\1\nCOPY qemu-${qemu_arch}-static /usr/bin/\n#" ${dockerfile_orig} > ${dockerfile_dest}
    sed -i "s#FROM\( \+\)python:\(.*\)#FROM\1${docker_arch}/python:\2\n#" ${dockerfile_dest}
}
fetch_sources
init_qemu

# Patch python dependencies
echo "urllib3<1.25,>=1.21.1" >> requirements.txt

echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin

build_and_push_images amd64 ./Dockerfile

patch_dockerfile Dockerfile Dockerfile.arm arm32v7 arm
build_and_push_images arm ./Dockerfile.arm

patch_dockerfile Dockerfile Dockerfile.arm64 arm64v8 aarch64
build_and_push_images arm64 ./Dockerfile.arm64

build_manifests
