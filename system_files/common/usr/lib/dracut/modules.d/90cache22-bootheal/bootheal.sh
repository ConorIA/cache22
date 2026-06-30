#!/bin/sh
# cache22-bootheal — make a stale ostree= bootversion path resolve so a
# surviving deployment still boots after a sibling was removed.
#
# Why this exists: cache22 boots signed UKIs whose cmdline bakes in the
# ostree deployment path, ostree=/ostree/boot.N/<os>/<csum>/<serial>. The
# only volatile part is the bootversion N: ostree flips it (0<->1) on every
# `ostree_sysroot_write_deployments` — which includes `ostree admin
# undeploy`. An undeploy does NOT rebuild the UKIs, so a survivor UKI baked
# with boot.0 stops resolving once the live bootversion is boot.1, and the
# machine drops to the emergency shell. The <os>/<csum>/<serial> tail stays
# valid (ostree does not renumber surviving deployments), so the fix is to
# repoint the stale boot.N symlink at the live generation.
#
# Runs in the initramfs before ostree-prepare-root, against the physical
# sysroot mounted at /sysroot. STRICTLY a no-op when the baked path already
# resolves, so a healthy boot is never touched.

sysroot=/sysroot

arg=$(tr ' ' '\n' < /proc/cmdline | sed -n 's/^ostree=//p' | head -1)
[ -n "$arg" ] || exit 0
case "$arg" in
    /ostree/boot.*) ;;
    *) exit 0 ;;
esac

# Healthy boot: the baked path resolves. Do nothing.
[ -e "$sysroot$arg" ] && exit 0

# Extract the bootversion N and the stable tail (/<os>/<csum>/<serial>).
n=$(echo "$arg" | sed -n 's|^/ostree/boot\.\([0-9][0-9]*\)/.*|\1|p')
[ -n "$n" ] || exit 0
tail=${arg#/ostree/boot.$n}
[ -n "$tail" ] || exit 0

# Find a live generation dir (/ostree/boot.X.Y) whose tail resolves, and
# point the stale boot.N at it. Relative target so it stays valid post-pivot.
for gen in "$sysroot"/ostree/boot.*.*; do
    [ -e "$gen$tail" ] || continue
    ln -sfn "${gen##*/}" "$sysroot/ostree/boot.$n"
    echo "cache22-bootheal: repointed boot.$n -> ${gen##*/} to resolve $arg"
    exit 0
done

echo "cache22-bootheal: no live generation resolves $tail; leaving boot.$n as-is" >&2
exit 0
