#!/bin/ash
# shellcheck shell=dash
# alpine/debian initrd 

# accept_ra  RA + 
# autoconf   accept_ra

mac_addr=$1
ipv4_addr=$2
ipv4_gateway=$3
ipv6_addr=$4
ipv6_gateway=$5
is_in_china=$6
ipv6_extra_addrs=$7

DHCP_TIMEOUT=15
DNS_FILE_TIMEOUT=5
TEST_TIMEOUT=10

#  IP 
#  debian initrd  nslookup
#  generate_204 resolv.conf 
# HTTP 80
# HTTPS/DOH 443
# DOT 853
if $is_in_china; then
    ipv4_dns1='223.5.5.5'
    ipv4_dns2='119.29.29.29' #  853
    ipv6_dns1='2400:3200::1'
    ipv6_dns2='2402:4e00::' #  853
else
    ipv4_dns1='1.1.1.1'
    ipv4_dns2='8.8.8.8' #  80
    ipv6_dns1='2606:4700:4700::1111'
    ipv6_dns2='2001:4860:4860::8888' #  80
fi

# 
# debian 11 initrd  xargs awk
# debian 12 initrd  xargs
get_ethx() {
    #  azure vf ( master ethx)
    # 2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP qlen 1000\    link/ether 60:45:bd:21:8a:51 brd ff:ff:ff:ff:ff:ff
    # 3: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP800> mtu 1500 qdisc mq master eth0 state UP qlen 1000\    link/ether 60:45:bd:21:8a:51 brd ff:ff:ff
    if false; then
        ip -o link | grep -i "$mac_addr" | grep -v master | awk '{print $2}' | cut -d: -f1 | grep .
    else
        ip -o link | grep -i "$mac_addr" | grep -v master | cut -d' ' -f2 | cut -d: -f1 | grep .
    fi
}

get_ipv4_gateway() {
    # debian 11 initrd  xargs awk
    # debian 12 initrd  xargs
    ip -4 route show default dev "$ethx" | head -1 | cut -d ' ' -f3
}

get_ipv6_gateway() {
    # debian 11 initrd  xargs awk
    # debian 12 initrd  xargs
    ip -6 route show default dev "$ethx" | head -1 | cut -d ' ' -f3
}

get_first_ipv4_addr() {
    # debian 11 initrd  xargs awk
    # debian 12 initrd  xargs
    if false; then
        ip -4 -o addr show scope global dev "$ethx" | head -1 | awk '{print $4}'
    else
        ip -4 -o addr show scope global dev "$ethx" | head -1 | grep -o '[0-9\.]*/[0-9]*'
    fi
}

get_first_ipv4_gateway() {
    # debian 11 initrd  xargs awk
    # debian 12 initrd  xargs
    if false; then
        ip -4 route show default dev "$ethx" | head -1 | awk '{print $3}'
    else
        ip -4 route show default dev "$ethx" | head -1 | cut -d' ' -f3
    fi
}

remove_netmask() {
    cut -d/ -f1
}

get_first_ipv6_addr() {
    # debian 11 initrd  xargs awk
    # debian 12 initrd  xargs
    if false; then
        ip -6 -o addr show scope global dev "$ethx" | head -1 | awk '{print $4}'
    else
        ip -6 -o addr show scope global dev "$ethx" | head -1 | grep -o '[0-9a-f\:]*/[0-9]*'
    fi
}

get_first_ipv6_gateway() {
    # debian 11 initrd  xargs awk
    # debian 12 initrd  xargs
    if false; then
        ip -6 route show default dev "$ethx" | head -1 | awk '{print $3}'
    else
        ip -6 route show default dev "$ethx" | head -1 | cut -d' ' -f3
    fi
}

is_have_ipv4_addr() {
    ip -4 addr show scope global dev "$ethx" | grep -q inet
}

is_have_ipv6_addr() {
    ip -6 addr show scope global dev "$ethx" | grep -q inet6
}

is_have_ipv4_gateway() {
    ip -4 route show default dev "$ethx" | grep -q .
}

is_have_ipv6_gateway() {
    ip -6 route show default dev "$ethx" | grep -q .
}

is_have_ipv4() {
    is_have_ipv4_addr && is_have_ipv4_gateway
}

is_have_ipv6() {
    is_have_ipv6_addr && is_have_ipv6_gateway
}

is_have_ipv4_dns() {
    [ -f /etc/resolv.conf ] && grep -q '^nameserver .*\.' /etc/resolv.conf
}

is_have_ipv6_dns() {
    [ -f /etc/resolv.conf ] && grep -q '^nameserver .*:' /etc/resolv.conf
}

add_missing_ipv4_config() {
    if [ -n "$ipv4_addr" ] && [ -n "$ipv4_gateway" ]; then
        if ! is_have_ipv4_addr; then
            ip -4 addr add "$ipv4_addr" dev "$ethx"
        fi

        if ! is_have_ipv4_gateway; then
            #  dhcp onlink
            # debian 9 ipv6  onlink ipv4  onlink
            if true; then
                ip -4 route add "$ipv4_gateway" dev "$ethx"
                ip -4 route add default via "$ipv4_gateway" dev "$ethx"
            else
                ip -4 route add default via "$ipv4_gateway" dev "$ethx" onlink
            fi
        fi
    fi
}

add_missing_ipv6_config() {
    if [ -n "$ipv6_addr" ] && [ -n "$ipv6_gateway" ]; then
        if ! is_have_ipv6_addr; then
            ip -6 addr add "$ipv6_addr" dev "$ethx"
        fi

        if ! is_have_ipv6_gateway; then
            #  dhcp onlink
            # debian 9 ipv6  onlink
            if true; then
                ip -6 route add "$ipv6_gateway" dev "$ethx"
                ip -6 route add default via "$ipv6_gateway" dev "$ethx"
            else
                ip -6 route add default via "$ipv6_gateway" dev "$ethx" onlink
            fi
        fi

        #  IPv6 
        if [ -n "$ipv6_extra_addrs" ]; then
            printf '%s\n' "$ipv6_extra_addrs" | tr ',' '\n' | while IFS= read -r addr; do
                if [ -n "$addr" ]; then
                    ip -6 addr add "$addr" dev "$ethx" 2>/dev/null || true
                fi
            done
        fi
    fi
}

is_need_test_ipv4() {
    is_have_ipv4 && ! $ipv4_has_internet
}

is_need_test_ipv6() {
    is_have_ipv6 && ! $ipv6_has_internet
}

# 
# ping   
# nc      dot doh 
# wget   

# initrd IP/
#      nc  wget  nslookup
# debian9  ×    √   
# alpine   √    ×      ×

test_by_wget() {
    src=$1
    dst=$2

    # ipv6  []
    if echo "$dst" | grep -q ':'; then
        url="https://[$dst]"
    else
        url="https://$dst"
    fi

    # tcp 443  http  404
    # grep -m1 
    wget -T "$TEST_TIMEOUT" \
        --bind-address="$src" \
        --no-check-certificate \
        --max-redirect 0 \
        --tries 1 \
        -O /dev/null \
        "$url" 2>&1 | grep -iq -m1 connected
}

test_by_nc() {
    src=$1
    dst=$2

    # tcp 443 
    nc -z -v \
        -w "$TEST_TIMEOUT" \
        -s "$src" \
        "$dst" 443
}

is_debian_kali() {
    [ -f /etc/lsb-release ] && grep -Eiq 'Debian|Kali' /etc/lsb-release
}

test_connect() {
    if is_debian_kali; then
        test_by_wget "$1" "$2"
    else
        test_by_nc "$1" "$2"
    fi
}

test_internet() {
    for i in $(seq 5); do
        echo "Testing Internet Connection. Test $i... "
        if is_need_test_ipv4 &&
            current_ipv4_addr="$(get_first_ipv4_addr | remove_netmask)" &&
            { test_connect "$current_ipv4_addr" "$ipv4_dns1" ||
                test_connect "$current_ipv4_addr" "$ipv4_dns2"; } >/dev/null 2>&1; then
            echo "IPv4 has internet."
            ipv4_has_internet=true
        fi
        if is_need_test_ipv6 &&
            current_ipv6_addr="$(get_first_ipv6_addr | remove_netmask)" &&
            { test_connect "$current_ipv6_addr" "$ipv6_dns1" ||
                test_connect "$current_ipv6_addr" "$ipv6_dns2"; } >/dev/null 2>&1; then
            echo "IPv6 has internet."
            ipv6_has_internet=true
        fi
        if ! is_need_test_ipv4 && ! is_need_test_ipv6; then
            break
        fi
        sleep 1
    done
}

flush_ipv4_config() {
    ip -4 addr flush scope global dev "$ethx"
    ip -4 route flush dev "$ethx"
    # DHCP  IP  IP  DHCP  DNS DNS 
    sed -i "/\./d" /etc/resolv.conf
}

should_disable_dhcpv4=false
should_disable_accept_ra=false
should_disable_autoconf=false

flush_ipv6_config() {
    if $should_disable_accept_ra; then
        echo 0 >"/proc/sys/net/ipv6/conf/$ethx/accept_ra"
    fi
    if $should_disable_autoconf; then
        echo 0 >"/proc/sys/net/ipv6/conf/$ethx/autoconf"
    fi
    ip -6 addr flush scope global dev "$ethx"
    ip -6 route flush dev "$ethx"
    # DHCP  IP  IP  DHCP  DNS DNS 
    sed -i "/:/d" /etc/resolv.conf
}

for i in $(seq 20); do
    if ethx=$(get_ethx); then
        break
    fi
    sleep 1
done

if [ -z "$ethx" ]; then
    echo "Not found network card: $mac_addr"
    exit
fi

echo "Configuring $ethx ($mac_addr)..."

#  lo  frp  127.0.0.1 22
ip link set dev lo up

#  ethx
ip link set dev "$ethx" up
sleep 1

#  dhcpv4/v6
# debian / kali
if [ -f /usr/share/debconf/confmodule ]; then
    # shellcheck source=/dev/null
    . /usr/share/debconf/confmodule

    db_progress STEP 1

    # dhcpv4
    #  dns dhcpv6 
    db_progress INFO netcfg/dhcp_progress
    udhcpc -i "$ethx" -f -q -n || true
    db_progress STEP 1

    # slaac + dhcpv6
    db_progress INFO netcfg/slaac_wait_title
    # https://salsa.debian.org/installer-team/netcfg/-/blob/master/autoconfig.c#L148
    cat <<EOF >/var/lib/netcfg/dhcp6c.conf
interface $ethx {
    send ia-na 0;
    request domain-name-servers;
    request domain-name;
    script "/lib/netcfg/print-dhcp6c-info";
};

id-assoc na 0 {
};
EOF
    dhcp6c -c /var/lib/netcfg/dhcp6c.conf "$ethx" || true
    sleep $DHCP_TIMEOUT #  ip  dns
    # kill-all-dhcp
    kill -9 "$(cat /var/run/dhcp6c.pid)" || true
    db_progress STEP 1

    #  + 
    db_subst netcfg/link_detect_progress interface "$ethx"
    db_progress INFO netcfg/link_detect_progress
else
    # alpine
    # h3c  udhcpc  sending select timeout 
    # dhcpcd  IP dhcpcd  udhcpc
    method=udhcpc

    case "$method" in
    udhcpc)
        timeout $DHCP_TIMEOUT udhcpc -i "$ethx" -f -q -n || true
        timeout $DHCP_TIMEOUT udhcpc6 -i "$ethx" -f -q -n || true
        sleep $DNS_FILE_TIMEOUT #  dns
        ;;
    dhcpcd)
        # https://gitlab.alpinelinux.org/alpine/aports/-/blob/master/main/dhcpcd/dhcpcd.pre-install
        grep -q dhcpcd /etc/group || addgroup -S dhcpcd
        grep -q dhcpcd /etc/passwd || adduser -S -D -H \
            -h /var/lib/dhcpcd \
            -s /sbin/nologin \
            -G dhcpcd \
            -g dhcpcd \
            dhcpcd

        # --noipv4ll  169.254.x.x
        if false; then
            #  DHCP 
            timeout $DHCP_TIMEOUT \
                dhcpcd --persistent --noipv4ll --nobackground "$ethx"
        else
            #  DNS
            dhcpcd --persistent --noipv4ll "$ethx" #  IP 
            sleep $DNS_FILE_TIMEOUT                #  dns
            dhcpcd -x "$ethx"                      # 
        fi
        # autoconf  accept_ra  dhcpcd 
        #  dhcpcd  slaac 
        sysctl -w "net.ipv6.conf.$ethx.autoconf=1"
        sysctl -w "net.ipv6.conf.$ethx.accept_ra=1"
        ;;
    esac
fi

# slaac
# ipv6slaacdhcpv6
# trans
# 5dhcp6
for i in $(seq 5 -1 0); do
    is_have_ipv6 && break
    echo "waiting slaac for ${i}s"
    sleep 1
done

# 
# ip
is_have_ipv4_addr && dhcpv4=true || dhcpv4=false
is_have_ipv6_addr && dhcpv6_or_slaac=true || dhcpv6_or_slaac=false
is_have_ipv6_gateway && ra_has_gateway=true || ra_has_gateway=false

#  IP  IP
#  IP/
# 1. /
# 2. openSUSE wicked dhcpv6  64 aws lightsail  dhcpv6  128 
if $dhcpv4 && [ -n "$ipv4_addr" ] && [ -n "$ipv4_gateway" ] &&
    ! [ "$(echo "$ipv4_addr" | cut -d/ -f1)" = "$(get_first_ipv4_addr | cut -d/ -f1)" ]; then
    echo "IPv4 address obtained from DHCP is different from old system."
    should_disable_dhcpv4=true
    flush_ipv4_config
fi
if $dhcpv6_or_slaac && [ -n "$ipv6_addr" ] && [ -n "$ipv6_gateway" ] &&
    ! [ "$(echo "$ipv6_addr" | cut -d/ -f1)" = "$(get_first_ipv6_addr | cut -d/ -f1)" ]; then
    echo "IPv6 address obtained from SLAAC/DHCPv6 is different from old system."
    should_disable_accept_ra=true
    should_disable_autoconf=true
    flush_ipv6_config
fi

#  debian 9 udhcpc 
add_missing_ipv4_config
add_missing_ipv6_config

#  ipv4/ipv6 
ipv4_has_internet=false
ipv6_has_internet=false
test_internet

#  / 
# ip_addr  IP/
# IP 
if ! $ipv4_has_internet &&
    $dhcpv4 && [ -n "$ipv4_addr" ] && [ -n "$ipv4_gateway" ] &&
    ! { [ "$ipv4_addr" = "$(get_first_ipv4_addr)" ] && [ "$ipv4_gateway" = "$(get_first_ipv4_gateway)" ]; }; then
    echo "IPv4 netmask/gateway obtained from DHCP is different from old system."
    should_disable_dhcpv4=true
    flush_ipv4_config
    add_missing_ipv4_config
    test_internet
fi
#  IPv6  RA  || $ra_has_gateway
if ! $ipv6_has_internet &&
    { $dhcpv6_or_slaac || $ra_has_gateway; } &&
    [ -n "$ipv6_addr" ] && [ -n "$ipv6_gateway" ] &&
    ! { [ "$ipv6_addr" = "$(get_first_ipv6_addr)" ] && [ "$ipv6_gateway" = "$(get_first_ipv6_gateway)" ]; }; then
    echo "IPv6 netmask/gateway obtained from SLAAC/DHCPv6 is different from old system."
    should_disable_accept_ra=true
    should_disable_autoconf=true
    flush_ipv6_config
    add_missing_ipv6_config
    test_internet
fi

# ip
# 1 ipv6
#   ipv6ipv6
#   alpineipv6apkipv4
# 2 ipv4ipv4(vultr $2.5 ipv6 only)aria2ipv4

#  ipv4 ipv6 ipv4  ipv6  ipv6
#  ipv4_has_internet && ! ipv6_has_internet 
if ! $ipv4_has_internet; then
    if $dhcpv4; then
        should_disable_dhcpv4=true
    fi
    flush_ipv4_config
fi
if ! $ipv6_has_internet; then
    #  IPv6  SLAAC 
    #  || $ra_has_gateway  IPv6  IPv6 
    if $dhcpv6_or_slaac; then
        should_disable_accept_ra=true
        should_disable_autoconf=true
    fi
    flush_ipv6_config
fi

#  DNS DNS

# 
#  flush_ipv4_config  IP  dns
#  dhcp4  dns
#  dns
if ! is_have_ipv4_dns; then
    echo "nameserver $ipv4_dns1" >>/etc/resolv.conf
    echo "nameserver $ipv4_dns2" >>/etc/resolv.conf
fi
if ! is_have_ipv6_dns; then
    echo "nameserver $ipv6_dns1" >>/etc/resolv.conf
    echo "nameserver $ipv6_dns2" >>/etc/resolv.conf
fi

#  trans.start
netconf="/dev/netconf/$ethx"
mkdir -p "$netconf"
$dhcpv4 && echo 1 >"$netconf/dhcpv4" || echo 0 >"$netconf/dhcpv4"
$dhcpv6_or_slaac && echo 1 >"$netconf/dhcpv6_or_slaac" || echo 0 >"$netconf/dhcpv6_or_slaac"
$should_disable_dhcpv4 && echo 1 >"$netconf/should_disable_dhcpv4" || echo 0 >"$netconf/should_disable_dhcpv4"
$should_disable_accept_ra && echo 1 >"$netconf/should_disable_accept_ra" || echo 0 >"$netconf/should_disable_accept_ra"
$should_disable_autoconf && echo 1 >"$netconf/should_disable_autoconf" || echo 0 >"$netconf/should_disable_autoconf"
$is_in_china && echo 1 >"$netconf/is_in_china" || echo 0 >"$netconf/is_in_china"
echo "$ethx" >"$netconf/ethx"
echo "$mac_addr" >"$netconf/mac_addr"
echo "$ipv4_addr" >"$netconf/ipv4_addr"
echo "$ipv4_gateway" >"$netconf/ipv4_gateway"
echo "$ipv6_addr" >"$netconf/ipv6_addr"
echo "$ipv6_gateway" >"$netconf/ipv6_gateway"
echo "$ipv6_extra_addrs" >"$netconf/ipv6_extra_addrs"
$ipv4_has_internet && echo 1 >"$netconf/ipv4_has_internet" || echo 0 >"$netconf/ipv4_has_internet"
$ipv6_has_internet && echo 1 >"$netconf/ipv6_has_internet" || echo 0 >"$netconf/ipv6_has_internet"
