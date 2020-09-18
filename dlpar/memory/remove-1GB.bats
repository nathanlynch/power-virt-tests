#!/usr/bin/env bats

load ../../testlib.bash

@test "remove 1GB memory after boot" {
    testlib_remove_mem 1024
}

@test "add 1GB memory back" {
    testlib_add_mem 1024
}

@test "remove 1GB memory once again" {
    testlib_remove_mem 1024
}

@test "add 1GB memory back again" {
    testlib_add_mem 1024
}
