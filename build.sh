#!/bin/bash
#
# Copyright (c) 2018, Fyde, Inc.
# All rights reserved.
#
# Create image

# Only setup error handling if we're not running in an interactive shell
if [[ ! $- =~ .*i.* ]] ; then
    set -e
fi

# Check for required vars
if [ -n "$CI" ]; then
    DOCKER_REGISTRY_PASS="${DOCKER_REGISTRY_PASS:?"DOCKER_REGISTRY_PASS not set"}"
    DOCKER_REGISTRY_URL="${DOCKER_REGISTRY_URL:?"DOCKER_REGISTRY_URL not set"}"
    DOCKER_REGISTRY_USER="${DOCKER_REGISTRY_USER:?"DOCKER_REGISTRY_USER not set"}"
    DOCKER_TAG="${DOCKER_TAG:?"DOCKER_TAG not set"}"
else
    DOCKER_TAG=fydeinc/pyinstaller
fi

if [ -z "$CI_COMMIT_REF_SLUG" ]; then
    CI_COMMIT_REF_SLUG="$(git symbolic-ref -q --short HEAD || git describe --tags --exact-match)"
fi

if [[ "$CI_COMMIT_REF_SLUG" = "main" ]]; then
    DOCKER_TAG="$DOCKER_TAG:latest"
    NO_CACHE="--no-cache"
else
    NO_CACHE=""
    DOCKER_TAG_LATEST="$DOCKER_TAG:latest"
    DOCKER_TAG="$DOCKER_TAG:$CI_COMMIT_REF_SLUG"
fi
echo "$DOCKER_TAG"

echo "Building docker with tag $DOCKER_TAG"

if [ -n "$DOCKER_REGISTRY_USER" ]; then
    echo "Docker Login"
    echo "$DOCKER_REGISTRY_PASS" | docker login --username "$DOCKER_REGISTRY_USER" --password-stdin "$DOCKER_REGISTRY_URL"
fi

if [ -n "$DOCKER_REGISTRY_URL" ]; then
    DOCKER_TAG="$DOCKER_REGISTRY_URL/$DOCKER_TAG"
fi

if [ -n "$DOCKER_REGISTRY_USER" ]; then
    echo "Pull Image"
    docker pull "$DOCKER_TAG" || true
fi

# Get latest base images for manylinux
docker pull quay.io/pypa/manylinux2010_x86_64

echo "Build Image"
docker build --rm $NO_CACHE -t "$DOCKER_TAG" .

echo "Image info"
docker images "$DOCKER_TAG"

if [ -n "$DOCKER_REGISTRY_USER" ]; then
    echo "Send Image to Registry"
    docker push "$DOCKER_TAG"

    # Also push latest in dev
    if [[ -n "$DOCKER_TAG_LATEST" ]]; then
        DOCKER_TAG_LATEST="$DOCKER_REGISTRY_URL/$DOCKER_TAG_LATEST"
        docker tag "$DOCKER_TAG" "$DOCKER_TAG_LATEST"
        docker push "$DOCKER_TAG_LATEST"
    fi
fi
