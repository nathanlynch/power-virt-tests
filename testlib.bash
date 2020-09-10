#!/bin/bash

# Usage:
#   load testlib.bash
# in any .bats testcase definition

__testlib_log() {
    local msg="$1"

    printf "# %s\n" "$msg" >&3
}

[ -v ANSIBLE_CONFIG ] || {
    __testlib_log "ANSIBLE_CONFIG is unset"
    false
}

kbadpatterns="kernel-badpatterns"

workdir="$BATS_TMPDIR"
victim_vars="$workdir"/victim.variables

victim_var() {
    local key="$1"

    [ -r "$victim_vars" ] || {
	ansible-inventory --host victim --toml > "$victim_vars"
    }
    awk -F'"' /^"$key"/'{print $2}' "$victim_vars"
}

sut="$(victim_var ansible_host)"
sut_user="$(victim_var ansible_user)"
machine="$(victim_var machine)"
lpar_name="$(victim_var lpar_name)"

__testlib_run_ansible() {
    local logdir="$workdir"/ansible-logs
    mkdir -p "$logdir"
    ansible -t "$logdir" "$@"
}

__testlib_ansible_raw() {
    local cmd="$1" ; shift
    local host="$1" ; shift
    local args=(-m raw -a "$cmd" "$host")

    __testlib_run_ansible "${args[@]}"
}

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

    __testlib_ansible_raw \
	"chhwres -w 1 -m $machine -p $lpar_name -r mem -o a -q $mem_mb" \
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

    __testlib_ansible_raw \
	"chhwres -w 1 -m $machine -p $lpar_name -r mem -o r -q $mem_mb" \
	hmc
}

__testlib_wait_for_host_up() {
    local host="$1" ; shift
    local deadline=300
    local count=5

    printf "Waiting for %s to come up (count=%s, deadline=%s)\n" "$host" \
	   "$count" "$deadline"

    ping -q -w "$deadline" -c "$count" "$host"
    testlib_sut_reachable
}

__testlib_boot_victim() {
    # TODO: Handle victim that is already up.
    # TODO: Specify profile instead of relying on defaults.
    __testlib_ansible_raw \
	"chsysstate -r lpar -m $machine -n $lpar_name -o on" \
	hmc
    __testlib_wait_for_host_up "$sut"
}

__testlib_halt_victim() {
    __testlib_ansible_raw \
	"chsysstate -r lpar -m $machine -n $lpar_name -o osshutdown --immed" \
	hmc
    # TODO: Wait for
    #   lssyscfg -r lpar -m $machine --filter "lpar_names=$lpar_name" -F state
    # to yield 'Not Activated'.
}

testlib_common_preconditions() {
    :
}

testlib_common_postconditions() {
    testlib_kernel_log_good
}

testlib_setup_file() {
    getent hosts "$sut"
    __testlib_boot_victim
}

__testlib_set_next_boot() {
    ssh "$sut_user"@"$sut" grub2-reboot "$1"
}

testlib_teardown_file() {
    __testlib_set_next_boot "development kernel"
    __testlib_halt_victim
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
# bats hooks:
# https://github.com/bats-core/bats-core#setup-and-teardown-pre--and-post-test-hooks

setup_file() {
    testlib_setup_file
}

setup() {
    testlib_setup
}

teardown() {
    testlib_teardown
}

teardown_file() {
    testlib_teardown_file
}
