#
# Copyright (c) 2019 Intel Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: EPL-2.0
#

# Bash script to build tensorflow serving image
# Setup proxy on your terminal before running the script.

# To build image separately
# VERSION=1.13.0
# TAG=intel-mkl-${VERSION}
# DOCKER_URL=docker.io/karthikvadla/kfserving
# MKL_IMAGE_TAG=${DOCKER_URL}:${TAG}
#
# TF_SERVING_VERSION=${VERSION} MKL_IMAGE_TAG=${MKL_IMAGE_TAG} bash build_mkl_tfserving_image.sh

#!/usr/bin/env bash
set -e
set -x

WORKDIR=serving_workspace

if [ -d ${WORKDIR} ]; then
    rm -rf ${WORKDIR}
fi

pushd $(pwd)

mkdir -p ${WORKDIR}
cd ${WORKDIR}

# Build Tensorflow Serving image
TF_SERVING_VERSION=${TF_SERVING_VERSION:-"master"}
echo "Using TF_SERVING_VERSION=${TF_SERVING_VERSION} to build docker image"

# Clone official tensorflow serving repo
git clone https://github.com/tensorflow/serving.git

TF_SERVING_ROOT=$(pwd)/serving
cd ${TF_SERVING_ROOT}/tensorflow_serving/tools/docker/

# Build Dockerfile.devel-mkl
docker build --no-cache \
    --build-arg TF_SERVING_BAZEL_OPTIONS="--incompatible_disallow_data_transition=false --incompatible_disallow_filetype=false" \
    --build-arg TF_SERVING_VERSION_GIT_BRANCH=${TF_SERVING_VERSION} \
    --build-arg HTTP_PROXY=${HTTP_PROXY} \
    --build-arg HTTPS_PROXY=${HTTPS_PROXY} \
    --build-arg http_proxy=${http_proxy} \
    --build-arg https_proxy=${https_proxy} \
    -f Dockerfile.devel-mkl -t tensorflow/serving:latest-devel-mkl .

# Build Dockerfile.mkl, which uses above image as base_image
docker build --no-cache \
    --build-arg TF_SERVING_VERSION_GIT_BRANCH=${TF_SERVING_VERSION} \
    --build-arg HTTP_PROXY=${HTTP_PROXY} \
    --build-arg HTTPS_PROXY=${HTTPS_PROXY} \
    --build-arg http_proxy=${http_proxy} \
    --build-arg https_proxy=${https_proxy} \
    -f Dockerfile.mkl -t ${MKL_IMAGE_TAG} .

popd

rm -rf ${WORKDIR}

echo "Image built with tag: ${MKL_IMAGE_TAG}"
