---
title: Boot and Security
nav_order: 4
has_children: true
permalink: /boot-and-security/
---

# Boot and Security

cache22 uses systemd-boot loading a per-machine-signed Unified Kernel Image (UKI). The signing key is generated at install time on the user's machine and lives only on the encrypted root. There is no central CI signing key.

Pages in this section:

1. [Boot Chain](./boot-chain/). The full sd-boot + UKI architecture.
2. [cache22-secureboot](./cache22-secureboot/). Managing the per-machine SB key and firmware DB enrollment.
3. [TPM and LUKS](./tpm-luks/). Auto-unlock with `cache22-encryption`. Includes the PCR 11 vs PCR 7 dual-keyslot decision.
4. [Threat Model](./threat-model/). What is and is not protected.

For the one-time first-boot key enrollment, see [First-Boot Secure Boot Setup](../getting-started/secure-boot-first-boot/).
