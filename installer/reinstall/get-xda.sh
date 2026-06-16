#!/bin/sh
# debian ubuntu redhat 
# alpine 

get_all_disks() {
    # shellcheck disable=SC2010
    ls /sys/block/ | grep -Ev '^(loop|sr|nbd)'
}

get_xda() {
    #  main_disk  xda
    # 
    eval "$(grep -o 'extra_main_disk=[^ ]*' /proc/cmdline | sed 's/^extra_//')"

    if [ -z "$main_disk" ]; then
        echo 'MAIN_DISK_NOT_FOUND'
        return 1
    fi

    for disk in $(get_all_disks); do
        if fdisk -l "/dev/$disk" | grep -iq "$main_disk"; then
            echo "$disk"
            return
        fi
    done

    echo 'XDA_NOT_FOUND'
    return 1
}

get_xda
