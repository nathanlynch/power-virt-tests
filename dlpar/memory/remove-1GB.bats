#!/usr/bin/env bats

load ../../testlib.bash

add_1GB() {
    testlib_add_mem 1024
}

remove_1GB() {
    testlib_remove_mem 1024
}

@test "remove 1GB memory after boot" {
    remove_1GB
}

@test "add 1GB memory back" {
    add_1GB
}

@test "remove 1GB memory once again" {
    remove_1GB
}

@test "add 1GB memory back again" {
    add_1GB
}
