#!/bin/bash
# cache22-bootheal dracut module: install the boot-version heal that lets a
# surviving deployment boot after a sibling undeploy left the UKI's baked
# ostree= path stale. See bootheal.sh for the full rationale.

# Pulled in explicitly via add_dracutmodules in 10-cache22.conf.
check() {
    return 0
}

# Needs ostree's prepare-root to order against, and systemd to run a unit
# inside the initramfs.
depends() {
    echo ostree systemd
    return 0
}

install() {
    inst_script "$moddir/bootheal.sh" /usr/lib/cache22/bootheal.sh
    inst_simple "$moddir/cache22-bootheal.service" \
        "$systemdsystemunitdir/cache22-bootheal.service"

    # Order before ostree-prepare-root.service and make sure it gets pulled
    # in (the unit is otherwise wanted by nothing). add-wants is the dracut
    # idiom; fall back to a manual .wants symlink if it is unavailable.
    if ! $SYSTEMCTL -q --root "$initdir" add-wants \
            ostree-prepare-root.service cache22-bootheal.service 2>/dev/null; then
        mkdir -p "$initdir$systemdsystemunitdir/ostree-prepare-root.service.wants"
        ln -sf ../cache22-bootheal.service \
            "$initdir$systemdsystemunitdir/ostree-prepare-root.service.wants/cache22-bootheal.service"
    fi
}
