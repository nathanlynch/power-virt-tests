#!/usr/bin/env bats

load testlib.bash

@test "addition using bc" {
  result="$(echo 2+2 | bc)"
  [ "$result" -eq 4 ]
}

@test "addition using dc" {
  result="$(echo 2 2+p | dc)"
  [ "$result" -eq 4 ]
}

@test "expected failure" {
    false
}

@test "expected skip" {
    skip
}

fn() {
    ssh "$sut_user"@"$sut" true
}

@test "Use testlib_run" {
    testlib_run fn
}
