#!/bin/bash

set -x

apt-get update
apt-get -y install jq git file pkg-config zip g++ zlib1g-dev unzip python

function getattr() {
  curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/$2/attributes/$1
}

GITHUB_TOKEN=$(getattr "github_token" "project")
RELEASE_TAG=$(getattr "release_tag" "instance")
PRERELEASE=$(getattr "prerelease" "instance")
DOCKER_HUB_KEY=$(getattr "docker_hub_key" "project")
SIGN_KEY_PATH=$(getattr "sign_key_path" "project")
SIGN_KEY_PASS=$(getattr "sign_key_pass" "project")
VUSER=$(getattr "b_user" "project")

mkdir -p /v2/build

pushd /v2/build
BAZEL_VER=0.17.2
curl -L -O https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VER}/bazel-${BAZEL_VER}-installer-linux-x86_64.sh
chmod +x bazel-${BAZEL_VER}-installer-linux-x86_64.sh
./bazel-${BAZEL_VER}-installer-linux-x86_64.sh
popd

gsutil cp ${SIGN_KEY_PATH} /v2ray/build/sign_key.asc
echo ${SIGN_KEY_PASS} | gpg --passphrase-fd 0 --batch --import /v2ray/build/sign_key.asc

curl -L -o /v2ray/build/releases https://api.github.com/repos/v2ray/v2ray-core/releases

GO_INSTALL=golang.tar.gz
curl -L -o ${GO_INSTALL} https://storage.googleapis.com/golang/go1.11.1.linux-amd64.tar.gz
tar -C /usr/local -xzf ${GO_INSTALL}
export PATH=$PATH:/usr/local/go/bin

mkdir -p /v2/src
export GOPATH=/v2

go get v2ray.com/core/...
go get v2ray.com/ext/...

pushd $GOPATH/src/v2ray.com/core/
git checkout tags/${RELEASE_TAG}

VERN=${RELEASE_TAG:1}
BUILDN=`date +%Y%m%d`
sed -i "s/\(version *= *\"\).*\(\"\)/\1$VERN\2/g" core.go
sed -i "s/\(build *= *\"\).*\(\"\)/\1$BUILDN\2/g" core.go

bazel build --action_env=GOPATH=$GOPATH --action_env=PATH=$PATH --action_env=GPG_PASS=${SIGN_KEY_PASS} //release:all
popd

RELBODY="https://www.v2ray.com/chapter_00/01_versions.html"
JSON_DATA=$(echo "{}" | jq -c ".tag_name=\"${RELEASE_TAG}\"")
JSON_DATA=$(echo ${JSON_DATA} | jq -c ".prerelease=${PRERELEASE}")
JSON_DATA=$(echo ${JSON_DATA} | jq -c ".body=\"${RELBODY}\"")
RELEASE_ID=$(curl --data "${JSON_DATA}" -H "Authorization: token ${GITHUB_TOKEN}" -X POST https://api.github.com/repos/v2ray/v2ray-core/releases | jq ".id")

function upload() {
  FILE=$1
  CTYPE=$(file -b --mime-type $FILE)
  curl -H "Authorization: token ${GITHUB_TOKEN}" -H "Content-Type: ${CTYPE}" --data-binary @$FILE "https://uploads.github.com/repos/v2ray/v2ray-core/releases/${RELEASE_ID}/assets?name=$(basename $FILE)"
}

ART_ROOT=$GOPATH/src/v2ray/bazel-bin/release
upload ${ART_ROOT}/v2ray-macos.zip
upload ${ART_ROOT}/v2ray-windows-64.zip
upload ${ART_ROOT}/v2ray-windows-32.zip
upload ${ART_ROOT}/v2ray-linux-64.zip
upload ${ART_ROOT}/v2ray-linux-32.zip
upload ${ART_ROOT}/v2ray-linux-arm.zip
upload ${ART_ROOT}/v2ray-linux-arm64.zip
upload ${ART_ROOT}/v2ray-linux-mips64.zip
upload ${ART_ROOT}/v2ray-linux-mips64le.zip
upload ${ART_ROOT}/v2ray-linux-mips.zip
upload ${ART_ROOT}/v2ray-linux-mipsle.zip
upload ${ART_ROOT}/v2ray-linux-s390x.zip
upload ${ART_ROOT}/v2ray-freebsd-64.zip
upload ${ART_ROOT}/v2ray-freebsd-32.zip
upload ${ART_ROOT}/v2ray-openbsd-64.zip
upload ${ART_ROOT}/v2ray-openbsd-32.zip
upload ${ART_ROOT}/v2ray-dragonfly-64.zip
upload ${ART_ROOT}/metadata.txt

if [[ "${PRERELEASE}" == "false" ]]; then

DOCKER_HUB_API=https://cloud.docker.com/api/build/v1/source/62bfa37d-18ef-4b66-8f1a-35f9f3d4438b/trigger/65027872-e73e-4177-8c6c-6448d2f00d5b/call/
curl -H "Content-Type: application/json" --data '{"build": true}' -X POST "${DOCKER_HUB_API}"

fi

shutdown -h now