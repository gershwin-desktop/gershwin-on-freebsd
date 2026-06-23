#!/bin/sh
#
# Vendored from FreeBSD releng/15.0:release/arm64/mkisoimages.sh, with the
# tools.subr dependency replaced by inline defaults so the script can run
# from this directory layout (alongside install-boot.sh).
#
# Usage:
#   mkisoimages-arm64.sh [-b] image-label image-name base-bits-dir [extra-bits-dir]

set -e

. install-boot.sh

if [ -z $ETDUMP ]; then
    ETDUMP=etdump
fi

if [ -z $MAKEFS ]; then
    MAKEFS=makefs
fi

if [ -z $MKIMG ]; then
    MKIMG=mkimg
fi

if [ "$1" = "-b" ]; then
    BASEBITSDIR="$4"

    # Make an EFI system partition.
    espfilename=$(mktemp /tmp/efiboot.XXXXXX)
    # ESP file size in KB.
    espsize="2048"
    make_esp_file ${espfilename} ${espsize} ${BASEBITSDIR}/boot/loader.efi

    bootable="-o bootimage=efi;${espfilename} -o no-emul-boot -o platformid=efi"

    shift
else
    BASEBITSDIR="$3"
    bootable=""
fi

if [ $# -lt 3 ]; then
    echo "Usage: $0 [-b] image-label image-name base-bits-dir [extra-bits-dir]"
    exit 1
fi

LABEL=`echo "$1" | tr '[:lower:]' '[:upper:]'`; shift
NAME="$1"; shift

publisher="The FreeBSD Project.  https://www.FreeBSD.org/"
echo "/dev/iso9660/$LABEL / cd9660 ro 0 0" > "$BASEBITSDIR/etc/fstab"
$MAKEFS -t cd9660 $bootable -o rockridge -o label="$LABEL" -o publisher="$publisher" "$NAME" "$@"
rm -f "$BASEBITSDIR/etc/fstab"
rm -f ${espfilename}

if [ "$bootable" != "" ]; then
    # Look for the EFI System Partition image we dropped in the ISO image.
    for entry in `$ETDUMP --format shell $NAME`; do
        eval $entry
        # arm64 etdump returns "default" for the initial (and only) entry.
        if [ "$et_platform" = "default" ] || [ "$et_platform" = "efi" ]; then
            espstart=`expr $et_lba \* 2048`
            espsize=`expr $et_sectors \* 512`
            espparam="-p efi::$espsize:$espstart"
            break
        fi
    done

    # Create a GPT image containing the EFI partition (no PMBR / freebsd-boot
    # — arm64 boots EFI only).
    efifilename=$(mktemp /tmp/efi.img.XXXXXX)
    imgsize=`stat -f %z "$NAME"`
    $MKIMG -s gpt \
        --capacity $imgsize \
        $espparam \
        -o $efifilename

    # Drop the GPT into the System Area of the ISO.
    dd if=$efifilename of="$NAME" bs=32k count=1 conv=notrunc
    rm -f $efifilename
fi
