#!/usr/bin/env bash

# English is the default. Danish is selected for da_* locales.
# Override detection with QEMU_SPINRITE_LANG=en or QEMU_SPINRITE_LANG=da.
LOCALE="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
case "${QEMU_SPINRITE_LANG:-}" in
    da|DA) LANGUAGE=da ;;
    en|EN) LANGUAGE=en ;;
    *) case "$LOCALE" in da|da_*|da-*) LANGUAGE=da ;; *) LANGUAGE=en ;; esac ;;
esac

if [[ "$LANGUAGE" == da ]]; then
    TXT_SCAN="🔍 scanner systemet for tilgængelige diske..."
    TXT_NO_DISKS="❌ Ingen tilgængelige diske fundet i systemet!"
    TXT_CHOOSE="Vælg den disk, som SpinRite skal scanne:"
    TXT_MOUNTED="⚠️  MONTERET (LÅST)"
    TXT_READY="✅ Klar (Ikke monteret)"
    TXT_CANCELLED="Afbrudt."
    TXT_INVALID="❌ Ugyldigt valg!"
    TXT_EXCLUSIVE="SpinRite kræver rå, eksklusiv adgang til disken."
    TXT_UNMOUNT_FAILED="❌ Kunne ikke afmontere disken automatisk. Luk eventuelle programmer, der bruger disken, og prøv igen."
    TXT_UNMOUNT_OK="✅ Disken blev afmonteret med succes!"
    TXT_MUST_UNMOUNT="❌ Afbrudt. SpinRite kan ikke køre på en monteret disk."
    TXT_STARTING="🚀 Starter SpinRite 6.1..."
else
    TXT_SCAN="🔍 scanning system for available disks..."
    TXT_NO_DISKS="❌ No available disks found on the system!"
    TXT_CHOOSE="Select the disk that SpinRite should scan:"
    TXT_MOUNTED="⚠️  MOUNTED (LOCKED)"
    TXT_READY="✅ Ready (Not mounted)"
    TXT_CANCELLED="Cancelled."
    TXT_INVALID="❌ Invalid selection!"
    TXT_EXCLUSIVE="SpinRite requires raw, exclusive access to the disk."
    TXT_UNMOUNT_FAILED="❌ Could not unmount the disk automatically. Close any programs using the disk and try again."
    TXT_UNMOUNT_OK="✅ Disk successfully unmounted!"
    TXT_MUST_UNMOUNT="❌ Cancelled. SpinRite cannot run on a mounted disk."
    TXT_STARTING="🚀 Starting SpinRite 6.1..."
fi


# Sæt den præcise sti til din SpinRite ISO-fil her
ISO="$HOME/vm-space/ISO/SpinRite.iso" 

# Tjek om ISO-filen overhovedet eksisterer
if [ ! -f "$ISO" ]; then
    echo "❌ Fejl: SpinRite ISO blev ikke fundet på: $ISO"
    exit 1
fi

echo "========================================================="
echo "$TXT_SCAN"
echo "========================================================="

# Find alle diske (ekskluder loop-enheder, rom-drev og zram)
# Henter NAVN, MODEL, STØRRELSE, TYPE og MONTERINGSPUNKT
mapfile -t DISK_LINES < <(lsblk -dno NAME,MODEL,SIZE,TYPE | grep -E "disk" | grep -v zram | awk '{print $1}')

if [ ${#DISK_LINES[@]} -eq 0 ]; then
    echo "$TXT_NO_DISKS"
    exit 1
fi


# Find bus/transport information and, where Linux exposes it, the negotiated link speed.
# Examples: USB 480M / 5000M / 10000M, SATA 6.0 Gbps, PCIe/NVMe link width/speed.
get_bus_info() {
    local dev="$1"
    local name="${dev##*/}"
    local transport bus_path speed width usb_node sata_link pci_addr

    transport=$(lsblk -dno TRAN "$dev" 2>/dev/null | xargs)
    bus_path=$(readlink -f "/sys/class/block/$name/device" 2>/dev/null)

    case "$transport" in
        usb)
            # Walk up the sysfs tree until we find the USB device node that has "speed".
            usb_node="$bus_path"
            while [[ "$usb_node" == /sys/* && "$usb_node" != /sys ]]; do
                if [[ -r "$usb_node/speed" && -r "$usb_node/idVendor" ]]; then
                    speed=$(<"$usb_node/speed")
                    break
                fi
                usb_node="${usb_node%/*}"
            done

            if [[ -n "$speed" ]]; then
                printf 'USB %sM' "$speed"
            else
                printf 'USB (speed unknown)'
            fi
            ;;

        sata|ata)
            # libata exposes the negotiated SATA link in /sys/class/ata_link/link*/sata_spd.
            sata_link=$(find "$bus_path" -maxdepth 6 -type f -name sata_spd -print -quit 2>/dev/null)
            if [[ -n "$sata_link" && -r "$sata_link" ]]; then
                speed=$(xargs < "$sata_link")
                printf '%s %s' "${transport^^}" "$speed"
            else
                printf '%s' "${transport^^}"
            fi
            ;;

        nvme)
            # Find the PCI device backing the NVMe controller.
            pci_addr=$(grep -oE '[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]' <<<"$bus_path" | tail -1)
            if [[ -n "$pci_addr" ]]; then
                speed=$(cat "/sys/bus/pci/devices/$pci_addr/current_link_speed" 2>/dev/null)
                width=$(cat "/sys/bus/pci/devices/$pci_addr/current_link_width" 2>/dev/null)
            fi

            if [[ -n "$speed" && -n "$width" ]]; then
                printf 'NVMe / PCIe %s x%s' "$speed" "$width"
            elif [[ -n "$speed" ]]; then
                printf 'NVMe / PCIe %s' "$speed"
            else
                printf 'NVMe / PCIe'
            fi
            ;;

        mmc)
            printf 'MMC/SD'
            ;;

        "")
            # Some kernel drivers do not populate lsblk TRAN. Try PCI as a useful fallback.
            pci_addr=$(grep -oE '[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]' <<<"$bus_path" | tail -1)
            if [[ -n "$pci_addr" ]]; then
                speed=$(cat "/sys/bus/pci/devices/$pci_addr/current_link_speed" 2>/dev/null)
                width=$(cat "/sys/bus/pci/devices/$pci_addr/current_link_width" 2>/dev/null)
                if [[ -n "$speed" && -n "$width" ]]; then
                    printf 'PCIe %s x%s' "$speed" "$width"
                else
                    printf 'PCIe'
                fi
            else
                printf 'Bus unknown'
            fi
            ;;

        *)
            printf '%s' "${transport^^}"
            ;;
    esac
}

echo "$TXT_CHOOSE"
echo "---------------------------------------------------------"

# Vis diskene i en nummereret menu med monterings-status
declare -A DISK_MAP
declare -A DISK_MOUNTED
index=1

for dev in "${DISK_LINES[@]}"; do
    dev_path="/dev/$dev"
    model=$(lsblk -dno MODEL "$dev_path" | xargs)
    size=$(lsblk -dno SIZE "$dev_path")
    bus_info=$(get_bus_info "$dev_path")
    
    # Tjek om disken eller nogle af dens partitioner er monteret
    mount_points=$(lsblk -no MOUNTPOINTS "$dev_path" | grep -v '^$')
    
    if [ -n "$mount_points" ]; then
        mount_status="$TXT_MOUNTED"
        DISK_MOUNTED[$index]=true
    else
        mount_status="$TXT_READY"
        DISK_MOUNTED[$index]=false
    fi
    
    echo "[$index] $dev_path - $model ($size) [$bus_info] [$mount_status]"
    DISK_MAP[$index]="$dev_path"
    ((index++))
done

echo "---------------------------------------------------------"
if [[ "$LANGUAGE" == da ]]; then prompt="Indtast nummer (1-$((index-1))) eller 'q' for at afbryde: "; else prompt="Enter number (1-$((index-1))) or 'q' to quit: "; fi
read -p "$prompt" valg

if [[ "$valg" == "q" ]]; then
    echo "$TXT_CANCELLED"
    exit 0
fi

# Validering af input
if ! [[ "$valg" =~ ^[0-9]+$ ]] || [ "$valg" -lt 1 ] || [ "$valg" -ge "$index" ]; then
    echo "$TXT_INVALID"
    exit 1
fi

DISK="${DISK_MAP[$valg]}"

# Hvis disken er monteret, skal vi håndtere det
if [ "${DISK_MOUNTED[$valg]}" = true ]; then
    echo ""
    if [[ "$LANGUAGE" == da ]]; then echo "⚠️  $DISK er i øjeblikket monteret."; else echo "⚠️  $DISK is currently mounted."; fi
    echo "$TXT_EXCLUSIVE"
    if [[ "$LANGUAGE" == da ]]; then prompt="Vil du have, at scriptet forsøger at afmontere den nu? (j/n): "; else prompt="Would you like the script to try to unmount it now? (y/n): "; fi
    read -p "$prompt" unmount_valg
    
    if [[ "$unmount_valg" =~ ^[JjYy]$ ]]; then
        if [[ "$LANGUAGE" == da ]]; then echo "Forsøger at afmontere alle partitioner på $DISK..."; else echo "Attempting to unmount all partitions on $DISK..."; fi
        # Finder og afmonterer alle partitioner hørende til disken
        sudo udisksctl unmount -b "${DISK}"* 2>/dev/null || sudo umount "${DISK}"* 2>/dev/null
        
        # Tjek om det lykkedes
        if [ -n "$(lsblk -no MOUNTPOINTS "$DISK" | grep -v '^$')" ]; then
            echo "$TXT_UNMOUNT_FAILED"
            exit 1
        else
            echo "$TXT_UNMOUNT_OK"
        fi
    else
        echo "$TXT_MUST_UNMOUNT"
        exit 1
    fi
fi

echo ""
echo "$TXT_STARTING"
echo "Target disk: $DISK"
echo "---------------------------------------------------------"

# Kør QEMU med de optimerede indstillinger
qemu-system-x86_64 \
    -enable-kvm \
    -machine pc,accel=kvm \
    -cpu host \
    -smp 1,sockets=1,cores=1,threads=1 \
    -m 1088M \
    -drive file="$DISK",format=raw,if=none,id=sysdisk,cache=none,aio=native \
    -device ide-hd,bus=ide.0,unit=0,drive=sysdisk \
    -drive file="$ISO",media=cdrom,index=1 \
    -boot d \
    -display gtk \
    -vga std \
    -rtc base=localtime

