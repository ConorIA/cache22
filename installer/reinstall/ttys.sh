#!/bin/sh
prefix=$1

#  windows 
#  cloud 

#  debian initrd  xargs

#  tty  tty
if [ "$(uname -m)" = "aarch64" ]; then
    ttys="ttyS0 ttyAMA0 tty0"
else
    ttys="ttyS0 tty0"
fi

#  tty 
# hytron ttyS0 
#  cmdline  tty getty 
# https://github.com/bin456789/reinstall/issues/620

if [ "$prefix" = "console=" ]; then
    is_for_cmdline=true
else
    is_for_cmdline=false
fi

#        
#    
# console       tty 

is_first=true
for tty in $ttys; do
    if { [ -c "/dev/$tty" ] && stty -g -F "/dev/$tty" >/dev/null 2>&1; } ||
        { $is_for_cmdline && ! [ -c "/dev/$tty" ]; }; then
        if $is_first; then
            is_first=false
        else
            printf " "
        fi

        printf "%s" "$prefix$tty"

        if $is_for_cmdline &&
            { [ "$tty" = ttyS0 ] || [ "$tty" = ttyAMA0 ]; }; then
            printf ",115200n8"
        fi
    fi
done
