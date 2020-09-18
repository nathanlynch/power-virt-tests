#!/bin/bash

# Usage:
#   load testlib.bash
# in any .bats testcase definition

playbooks="./playbooks"

__testlib_log() {
    local msg="$1"

    printf "# %s\n" "$msg" >&3
}

[ -r ./testlib.bash ] || {
    __testlib_log "Test suite must be run from power-virt-tests directory."
    false
}

[ -v ANSIBLE_CONFIG ] || {
    __testlib_log "ANSIBLE_CONFIG is unset."
    false
}

kbadpatterns="kernel-badpatterns"

workdir="$BATS_TMPDIR"
victim_vars="$workdir"/victim.variables
hmc_vars="$workdir"/hmc.variables

host_var() {
    local key="$1" ; shift
    local host_alias="$1" ; shift
    local var_cache="$1" ; shift
    local value

    [ -r "$var_cache" ] || \
	ansible-inventory --host "$host_alias" --toml > "$var_cache"
    value="$(awk -F'"' /^"$key"/'{print $2}' "$var_cache")"
    [ -n "$value" ] || {
	__testlib_log "No value for key $key for host $host_alias"
	false
    }
    echo "$value"
}

victim_var() {
    local key="$1"

    host_var "$key" victim "$victim_vars"
}

hmc_var() {
    local key="$1"

    host_var "$key" hmc "$hmc_vars"
}

sut="$(victim_var ansible_host)"
sut_user="$(victim_var ansible_user)"
machine="$(victim_var machine)"
lpar_name="$(victim_var lpar_name)"
lpar_profile="$(victim_var lpar_profile)"

hmc_host="$(hmc_var ansible_host)"
hmc_user="$(hmc_var ansible_user)"

__testlib_ssh_cmd() {
    local user="$1" ; shift
    local host="$1" ; shift

    ssh "$user"@"$host" "$@"
}

__testlib_hmc_cmd() {
    __testlib_ssh_cmd "$hmc_user" "$hmc_host" "$@"
}

__testlib_sut_cmd() {
    __testlib_ssh_cmd "$sut_user" "$sut" "$@"
}

# Check the given kernel log against a list of known patterns that
# indicate an assertion failure, warning condition, etc. Patterns
# lifted from the output of 'abrt-dump-oops -m'.
#
# Returns 0 if no matches, 1 otherwise.
testlib_kernel_log_good() {
    local ret=0
    local klog="$BATS_TMPDIR"/klog."$BATS_TEST_NUMBER"

    __testlib_sut_cmd dmesg > "$klog"

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

testlib_write_sut_kmsg() {
    echo "$1" | __testlib_sut_cmd tee /dev/kmsg >/dev/null
}

__testlib_mark_test_begin() {
    testlib_write_sut_kmsg "TEST BEGIN: $1"
}

__testlib_mark_test_end() {
    testlib_write_sut_kmsg "TEST END: $1"
}

__testlib_wait_for_rmc_up() {
    while : ; do
	run __testlib_hmc_cmd lssyscfg -r lpar -m "$machine" \
	    --filter lpar_names="$lpar_name" -F rmc_state

	[ "$status" -eq 0 ]
	[ "$output" = "active" ] && break
	__testlib_log "Waiting for RMC connection; current state: $output"
	sleep 1
    done
}

testlib_dlpar_mem_cmd() {
    local op="$1" ; shift
    local mem_mb="$1" ; shift

    __testlib_wait_for_rmc_up

    # Note -w 1 is a temp hack to force earlier failure on crash
    # etc. It won't be suitable for larger values (more than a few
    # GB).
    __testlib_hmc_cmd chhwres -w 1 -m "$machine" -p "$lpar_name" \
		      -r mem -o "$op" -q "$mem_mb"
}

testlib_add_mem() {
    local mem_mb="$1"

    testlib_dlpar_mem_cmd a "$mem_mb"
}

testlib_remove_mem() {
    local mem_mb="$1"

    testlib_dlpar_mem_cmd r "$mem_mb"
}

testlib_set_mem() {
    local mem_mb="$1"

    testlib_dlpar_mem_cmd s "$mem_mb"
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
    run __testlib_hmc_cmd lssyscfg -r lpar -m "$machine" \
	--filter lpar_names="$lpar_name" -F state
    [ "$status" -eq 0 ]
    [ "$output" = "Running" ] && return 0

    # TODO: Specify profile instead of relying on defaults.
    __testlib_log "Activating $lpar_name"
    __testlib_hmc_cmd chsysstate -r lpar -m "$machine" -n "$lpar_name" \
		      -o on -f "$lpar_profile" || {
	__testlib_log "Activation failed"
	false
    }
    __testlib_wait_for_host_up "$sut"
}

__testlib_halt_victim() {
    __testlib_hmc_cmd chsysstate -r lpar -m "$machine" \
		      -n "$lpar_name" -o osshutdown --immed
    while : ; do
	run __testlib_hmc_cmd lssyscfg -r lpar -m "$machine" \
	    --filter lpar_names="$lpar_name" -F state
	[ "$status" -eq 0 ]
	[ "$output" = "Not Activated" ] && break
	__testlib_log "Waiting for $lpar_name to halt, current state: $output"
	sleep 1
    done
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
    ansible-playbook "$playbooks"/grub2-reboot-dev-kernel.yml
}

testlib_teardown_file() {
    __testlib_set_next_boot "development kernel"
    __testlib_halt_victim
}

testlib_setup() {
    __testlib_mark_test_begin "$BATS_TEST_DESCRIPTION ($BATS_TEST_FILENAME:$BATS_TEST_NUMBER)"
    testlib_common_preconditions
}

testlib_teardown() {
    testlib_common_postconditions
    __testlib_mark_test_end "$BATS_TEST_DESCRIPTION ($BATS_TEST_FILENAME:$BATS_TEST_NUMBER)"
    __testlib_sut_cmd dmesg | tail -n 5
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
    rm -f "$victim_vars"
}
