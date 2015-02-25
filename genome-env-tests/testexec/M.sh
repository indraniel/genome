#!/bin/bash

type -p genome-env-next

if test -z "$WORKSPACE"
then
    echo "WORKSPACE is not set" >&2
    exit 1
fi

source "$BATS_TEST_DIRNAME/test_helper.bash"

for M in sqitch/genome ur workflow ; do
    submodule_is_clean $M
done
submodule_is_not_initialized sqitch/genome
apipe_test_db_is_not_used
