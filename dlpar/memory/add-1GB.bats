#!/usr/bin/env bats

load ../../testlib.bash

@test "add 1GB memory after boot" {
    testlib_add_mem 1024
}

@test "remove just-added 1GB memory" {
    testlib_remove_mem 1024
}

@test "add 1GB memory back again" {
    testlib_add_mem 1024
}

@test "remove 1GB memory once again" {
    testlib_remove_mem 1024
}
