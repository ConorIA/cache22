#!/bin/bash
#  cloud-init  onlink 

set -eE
os_dir=$1

#  alpine live 
#  alpine live  systemctl netplan 
systemctl() {
    if systemd-detect-virt --chroot; then
        return
    fi
    command systemctl "$@"
}

netplan() {
    if systemd-detect-virt --chroot; then
        return
    fi
    command netplan "$@"
}

insert_into_file() {
    file=$1
    location=$2
    regex_to_find=$3

    if [ "$location" = head ]; then
        bak=$(mktemp)
        cp "$file" "$bak"
        cat - "$bak" >"$file"
    else
        line_num=$(grep -E -n "$regex_to_find" "$file" | cut -d: -f1)

        found_count=$(echo "$line_num" | wc -l)
        if [ ! "$found_count" -eq 1 ]; then
            return 1
        fi

        case "$location" in
        before) line_num=$((line_num - 1)) ;;
        after) ;;
        *) return 1 ;;
        esac

        sed -i "${line_num}r /dev/stdin" "$file"
    fi
}

fix_netplan_conf() {
    # 
    # gateway4: 1.1.1.1
    # gateway6: ::1

    # 
    # routes:
    #   - to: 0.0.0.0/0
    #     via: 1.1.1.1
    #     on-link: true
    # routes:
    #   - to: ::/0
    #     via: ::1
    #     on-link: true
    conf=$os_dir/etc/netplan/50-cloud-init.yaml
    if ! [ -f "$conf" ]; then
        return
    fi

    #  bug 
    if grep -q 'on-link:' "$conf"; then
        return
    fi

    # 
    gateways=$(grep 'gateway[4|6]:' "$conf" | awk '{print $2}')
    if [ -z "$gateways" ]; then
        return
    fi

    # 
    spaces=$(grep 'gateway[4|6]:' "$conf" | head -1 | grep -o '^[[:space:]]*')

    {
        # 
        cat <<EOF
${spaces}routes:
EOF
        # 
        for gateway in $gateways; do
            # debian 11  netplan  to: default
            case $gateway in
            *.*) to='0.0.0.0/0' ;;
            *:*) to='::/0' ;;
            esac

            cat <<EOF
${spaces}  - to: $to
${spaces}    via: $gateway
${spaces}    on-link: true
EOF
        done
    } | insert_into_file "$conf" before 'match:'

    # 
    sed -i '/gateway[4|6]:/d' "$conf"

    # 
    if command -v netplan && {
        systemctl -q is-enabled systemd-networkd || systemctl -q is-enabled NetworkManager
    }; then
        netplan apply
    fi
}

fix_networkd_conf() {
    #  gentoo
    # [Route]
    # Gateway=1.1.1.1
    # Gateway=2602::1

    #  arch
    # [Route]
    # Gateway=1.1.1.1
    #
    # [Route]
    # Gateway=2602::1

    # 
    # [Route]
    # Gateway=1.1.1.1
    # GatewayOnLink=yes
    #
    # [Route]
    # Gateway=2602::1
    # GatewayOnLink=yes

    if ! confs=$(ls "$os_dir"/etc/systemd/network/10-cloud-init-*.network 2>/dev/null); then
        return
    fi

    for conf in $confs; do
        #  bug 
        if grep -q '^GatewayOnLink=' "$conf"; then
            return
        fi

        # 
        gateways=$(grep '^Gateway=' "$conf" | cut -d= -f2)
        if [ -z "$gateways" ]; then
            return
        fi

        # 
        sed -i '/^\[Route\]/d; /^Gateway=/d; /^GatewayOnLink=/d' "$conf"

        # 
        for gateway in $gateways; do
            echo "
[Route]
Gateway=$gateway
GatewayOnLink=yes
"
        done >>"$conf"
    done

    # 
    # networkctl reload 
    if systemctl -q is-enabled systemd-networkd; then
        systemctl restart systemd-networkd
    fi
}

# ubuntu 18.04 cloud-init  23.1.2

# debian 10/11  ifupdown + resolvconf netplan + networkd/resolved
# debian 12 : netplan + networkd/resolved
# 23.1.1 
fix_netplan_conf

# arch: networkd/resolved
# gentoo: networkd/resolved
# 24.2 
# 
#  alpine  cloud-init
fix_networkd_conf
