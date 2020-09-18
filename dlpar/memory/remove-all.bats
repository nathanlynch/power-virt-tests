#!/usr/bin/env bats

load ../../testlib.bash

# Attempt to set the partition memory to 256MB - on most systems this
# removes all but one LMB. We expect the HMC to accept this as a valid
# operation and attempt it, but Linux generally won't be able to
# satisfy the request. This test verifies that Linux fails the
# operation in the expected manner without crashing or warning.
#
# The expected full output from the HMC looks like:
# HSCL2932 The dynamic removal of memory resources failed:
#   The operating system prevented all of the requested memory from being removed.
#   Amount of memory removed: 0 MB of 261376 MB.
#   The detailed output of the OS operation follows:
# Sep 17 20:16:09 caDlparCommand:execv to drmgr
# Validating Memory DLPAR capability...yes.
# Failed to write to /sys/kernel/dlpar: Invalid argument
#
# The OS return code is 255.

@test "attempt to set memory to 256MB (failure expected)" {
    run testlib_set_mem 256
    [ "$status" -eq 1 ]
    [[ "${lines[0]}" =~ ^"HSCL2932 " ]]
}
