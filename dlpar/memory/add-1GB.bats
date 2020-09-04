#!/usr/bin/env bats

load testlib.bash

add_1GB() {
    testlib_add_mem 1024
}

remove_1GB() {
    testlib_remove_mem 1024
}

@test "add 1GB memory" {
    testlib_run add_1GB
}

@test "remove 1GB memory" {
    testlib_run remove_1GB
}
