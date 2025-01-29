#!/usr/bin/env bash

tmpfile=$(mktemp)
wasmer run --verbose --enable-all ./main >$tmpfile
RESULT=$?
if [ "$RESULT" != "0" ]; then
    echo "Test failed: different exit code ($RESULT vs. 0)" >/dev/stderr
    exit 1
fi

echo "c_pthreads test passed"
