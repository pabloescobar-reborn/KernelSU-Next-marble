properties() { '
kernel.string=Poco F5 | Redmi Note 12 Turbo
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=marble
device.name2=marblein
supported.versions=
supported.patchlevels=
'; }

block=boot;
is_slot_device=auto;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

. tools/ak3-core.sh;

kdir="${AKHOME:-${home:-$PWD}}";

ui_print " "
ui_print "███████╗ ██████╗ ██╗███████╗"
ui_print "╚══███╔╝██╔═══██╗██║██╔════╝"
ui_print "  ███╔╝ ██║   ██║██║███████╗"
ui_print " ███╔╝  ██║   ██║██║╚════██║"
ui_print "███████╗╚██████╔╝██║███████║"
ui_print "╚══════╝ ╚═════╝ ╚═╝╚══════╝"
ui_print " "
ui_print "        Kernel by Pablo Escobar"
ui_print " "

detect_source() {
  for f in /system_root/system/build.prop /system/build.prop /product/etc/build.prop /system_ext/etc/build.prop; do
    [ -f "$f" ] || continue
    v=$(grep -m1 '^ro.sys.buildtype=' "$f" | cut -d= -f2 | tr -d '\r ' | tr '[:upper:]' '[:lower:]');
    [ -n "$v" ] && { echo "$v"; return; }
  done
  echo unknown
}

unsupported() {
  ui_print " "
  ui_print "──────────────────────────────────────"
  ui_print "            Unsupported ROM"
  ui_print "──────────────────────────────────────"
  ui_print " "
  abort "Installation aborted.";
}

wait_key() {
  while true; do
    ev=$(getevent -lc 1 2>/dev/null | grep -Eo 'KEY_(VOLUMEUP|VOLUMEDOWN|POWER) +DOWN' | head -n1);
    case "$ev" in
      KEY_VOLUMEUP*) return 1;;
      KEY_VOLUMEDOWN*) return 2;;
      KEY_POWER*) return 3;;
    esac
  done
}

ui_print "Checking ROM compatibility..."
SRC=$(detect_source)
case "$SRC" in
  aosp|clo) ui_print "Detected ROM type: $SRC";;
  *) unsupported;;
esac

command -v getevent >/dev/null 2>&1 || abort "getevent not available in this recovery; cannot show menu. Aborting...";

ui_print " "
ui_print "Select kernel to flash:"
ui_print "  1. KernelSU"
ui_print "  2. KernelSU-Next"
ui_print "  3. SukiSU Ultra"
ui_print "  4. ReSukiSU"
ui_print " "
ui_print "  Vol+ / Vol- = move   Power = confirm"

sel=1
while true; do
  case $sel in
    1) name=kernelsu; lbl="1. KernelSU";;
    2) name=kernelsu-next; lbl="2. KernelSU-Next";;
    3) name=sukisu-ultra; lbl="3. SukiSU Ultra";;
    4) name=resukisu; lbl="4. ReSukiSU";;
  esac
  ui_print "  > $lbl"
  wait_key; k=$?
  case $k in
    1) sel=$((sel - 1)); [ $sel -lt 1 ] && sel=4;;
    2) sel=$((sel % 4 + 1));;
    3)
      if [ -s "$kdir/$SRC/$name" ]; then break; fi
      ui_print "  ($name is not available in this zip, choose another)";;
  esac
done

ui_print " "; ui_print "Flashing: $lbl ($SRC)";
cp -f "$kdir/$SRC/$name" "$kdir/Image" || abort "Unable to stage kernel Image. Aborting...";
for f in dtb dtbo; do
  [ -s "$kdir/$SRC/$f" ] && cp -f "$kdir/$SRC/$f" "$kdir/$f";
done
rm -rf "$kdir/aosp" "$kdir/clo";

backup_current_boot() {
  backup_dir="/sdcard/marble-kernel-backup";
  slot_name="${SLOT:-noslot}";
  stamp="$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%s)";
  backup_img="${backup_dir}/boot-marble-${slot_name}-${stamp}.img";
  backup_txt="${backup_dir}/boot-marble-${slot_name}-${stamp}.txt";

  ui_print "Backing up current boot image...";
  mkdir -p "$backup_dir" || abort "Unable to create ${backup_dir}. Aborting...";
  [ -s "$BOOTIMG" ] || abort "Dumped boot image is missing. Backup failed; aborting for safety.";
  cp -f "$BOOTIMG" "$backup_img" || abort "Unable to save boot backup. Aborting...";
  {
    echo "device=marble/marblein";
    echo "slot=${slot_name}";
    echo "source_block=${BLOCK}";
    echo "created=${stamp}";
    echo "backup=${backup_img}";
    echo "installed=${SRC}/${name}";
  } > "$backup_txt" 2>/dev/null || true;
  ui_print "Backup saved:";
  ui_print "  ${backup_img}";
}

dump_boot;
backup_current_boot;
write_boot;
