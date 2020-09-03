#!/bin/bash

ANSIBLE_CONFIG="config/ansible.cfg"
export ANSIBLE_CONFIG

kbadpatterns="kernel-badpatterns"
sut=$(ansible-inventory --host victim --toml | \
	  awk -F'"' /^ansible_host/'{print $2}')
sut_user=$(ansible-inventory --host victim --toml | \
	       awk -F'"' /^ansible_user/'{print $2}')
machine=$(ansible-inventory --host victim --toml | \
	      awk -F'"' /^machine/'{print $2}')
lpar_name=$(ansible-inventory --host victim --toml | \
		awk -F'"' /^lpar_name/'{print $2}')

# Check the given kernel log against a list of known patterns that
# indicate an assertion failure, warning condition, etc. Patterns
# lifted from the output of 'abrt-dump-oops -m'.
#
# Returns 0 if no matches, 1 otherwise.
testlib_kernel_log_good() {
    local ret=0
    local klog="$BATS_TMPDIR"/klog."$BATS_TEST_NUMBER"

    ssh "$sut_user"@"$sut" dmesg > "$klog"

    grep -q -F -f "$kbadpatterns" "$klog" && {
	local count

	ret=1
	count="$(grep -c -F -f "$kbadpatterns" "$klog")"
	echo "Kernel badness found ($count total instances), printing first 3:"
	grep -F -f "$kbadpatterns" "$klog" | head -n 3
	echo "See $klog for details."
    }
    
    return $ret
}

# Verify that SUT is accessible by doing an ansible ping.
testlib_sut_reachable() {
    ansible -m ping victim
}

testlib_add_mem() {
    local mem_mb="$1"

    ansible -m raw \
	    -a "chhwres -m $machine -p $lpar_name -r mem -o a -q $mem_mb" \
	    hmc
}

testlib_write_sut_kmsg() {
    echo "$1" | ssh "$sut_user"@"$sut" tee /dev/kmsg >/dev/null
}

__testlib_mark_test_begin() {
    testlib_write_sut_kmsg "TEST BEGIN: $1"
}

__testlib_mark_test_end() {
    testlib_write_sut_kmsg "TEST END: $1"
}

testlib_remove_mem() {
    local mem_mb="$1"

    ansible -m raw \
	    -a "chhwres -m $machine -p $lpar_name -r mem -o r -q $mem_mb" \
	    hmc
}

testlib_common_preconditions() {
    :
}

testlib_common_postconditions() {
    testlib_kernel_log_good
}

testlib_setup_file() {
    getent hosts "$sut"
    # boot the victim
}

testlib_setup() {
    __testlib_mark_test_begin "$BATS_TEST_DESCRIPTION ($BATS_TEST_FILENAME:$BATS_TEST_NUMBER)"
}

testlib_teardown() {
    __testlib_mark_test_end "$BATS_TEST_DESCRIPTION ($BATS_TEST_FILENAME:$BATS_TEST_NUMBER)"
}

testlib_run() {
    testlib_common_preconditions
    $1
    testlib_common_postconditions
}

################################################################
# bats hooks

setup_file() {
    :
    testlib_setup_file
}

setup() {
    testlib_setup
}

teardown() {
    testlib_teardown
}

teardown_file() {
    :
    # halt the victim
}
