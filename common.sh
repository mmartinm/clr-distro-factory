#!/usr/bin/env bash
# Copyright (c) 2017 Intel Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

curl() {
    command curl --silent --fail $@
}

koji_cmd() {
    # Downloads fail sometime, try harder!
    local result=""
    local ret=1
    for (( i=0; $i < 10; i++ )); do
        result=$(koji ${@} 2> /dev/null) \
            || continue

        ret=0
        break
    done

    [[ -n ${result} ]] && echo "${result}"
    return ${ret}
}

assert_dep () {
    command -v $1 > /dev/null 2>&1 || { echo >&2 "Error: command '$1' not found"; exit 1; }
}

assert_dir () {
    [ -d $1 ] > /dev/null 2>&1 || { echo >&2 "Error: directory '$1' not found"; exit 1; }
}

assert_file() {
    [ -f $1 ] > /dev/null 2>&1 || { echo >&2 "Error: file '$1' not found"; exit 1; }
}

silentkill () {
    if [ ! -z $2 ]; then
        kill $2 $1 > /dev/null 2>&1 || true
    else
        kill -KILL $1 > /dev/null 2>&1 || true
    fi
}

run_and_log() {
    cmd=$1
    log_out="${2}.log"
    log_err="${2}_err.log"

    # Log to file
    if [ "$VERBOSE_LEVEL" -eq 0 ]; then
        $cmd > "${LOGDIR}/${log_out}" 2> "${LOGDIR}/${log_err}" &
    # Log to file and stdout
    elif [ "$VERBOSE_LEVEL" -eq 1 ]; then
        $cmd > >(tee "${LOGDIR}/${log_out}") 2> >(tee "${LOGDIR}/${log_err}") &
    # Log to stdout only
    elif [ "$VERBOSE_LEVEL" -eq 2 ]; then
        $cmd &
    # No output
    else
        $cmd > /dev/null 2> /dev/null &
    fi
}

fetch_config_repo() {
    echo "Config Repository:"

    if [[ ! -d ./config ]]; then
        local REPO_HOST=${CONFIG_REPO_HOST:?"CONFIG_REPO_HOST cannot be Null/Unset"}
        local REPO_NAME=${NAMESPACE:?"NAMESPACE cannot be Null/Unset"}
        echo -n "    Cloning..."
        git clone --quiet ${REPO_HOST}${REPO_NAME} config
        echo "OK!"
    else
        echo -n "    Updating..."
        pushd ./config > /dev/null
        git fetch --prune -P --quiet origin
        git reset --hard --quiet origin/master
        popd > /dev/null
        echo "OK!"
    fi

    pushd ./config > /dev/null
    echo "    $(git remote get-url origin) ($(git rev-parse --short HEAD))"
    echo -n "    Checking for the required files..."
    assert_file ./config.sh
    assert_file ./release-image-config.json
    popd > /dev/null
    echo "OK!"
    echo
}

var_save() {
    local VARS_DIR=${VARS_DIR:?"VARS_DIR Cannot be Null/Unset"}

    if (( $# != 1 )); then
        echo "[ERROR] 'var_save' requires a single argument!"
        return 1
    fi

    # "unsave"
    if [[ ! -v ${1} ]]; then
        rm -f ${VARS_DIR}/${1}
        return 0
    fi

    [[ -d ${VARS_DIR} ]] || mkdir -p ${VARS_DIR}

    echo "${!1}" > ${VARS_DIR}/${1}
}

var_load() {
    if (( $# != 1 )); then
        echo "[ERROR] 'var_load' requires a single argument!"
        return 1
    fi

    [[ -f ${VARS_DIR}/${1} ]] && declare -g ${1}="$(cat ${VARS_DIR}/${1})" || true
}
