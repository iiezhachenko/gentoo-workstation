#!/usr/bin/env bash
# Bash3 Boilerplate. Copyright (c) 2014, kvz.io

DEBUG_MODE=false
DEV_MODE=true

set -o errexit
set -o pipefail
set -o nounset
[ $DEBUG_MODE = true ] && set -o xtrace

# Set magic variables for current file & dir
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
__base="$(basename ${__file} .sh)"
__root="$(cd "$(dirname "${__dir}")" && pwd)" # <-- change this as it depends on your app

vm_os_type=Gentoo_64
autobuild_number=$(curl http://mirror.eu.oneandone.net/linux/distributions/gentoo/gentoo/releases/amd64/autobuilds/latest-install-amd64-minimal.txt | grep iso | cut -d ' ' -f 1)
usage_banner="usage: create_vm.sh hdd_size ram vm_name
    hdd_size - VM disk size in megabytes
    ram_mib - VM RAM size in megabytes
    vm_name - VM name. Allowed characters: a-z, A-Z, -, _
"

hdd_size=$1
ram_size=$2
read -r -a args <<< $*
last_arg_index=$(($#-1))
vm_name=${args[$last_arg_index]}

function usage {
  echo "$usage_banner"
  exit 1
}

function create_vbox_hdd {
  local hdd_file=$__dir/$1
  if [ $DEV_MODE = true ]; then
    if [ -f $hdd_file ]; then
      echo "Do you really want to delete $hdd_file? (y,n):"
      read answer
      [ $answer = y ] && vboxmanage closemedium disk $hdd_file --delete
    fi
    VBoxManage createhd --filename $vm_name.vdi --size $hdd_size
  fi
}

function create_vbox_vm {
  local vm_name=$1
  local vm_exist=$(VBoxManage showvminfo $vm_name | grep UUID)
  if [ $DEV_MODE = true ]; then
    if [ "x$vm_exist" != "x" ]; then
      echo "Do you really want to delete VM $vm_name? (y,n):"
      read answer
      [ $answer = y ] && VBoxManage unregistervm $vm_name --delete 
    fi
    VBoxManage createvm --name $vm_name --ostype $vm_os_type --register
  fi
}

[[ $# -ne 3 ]] && usage
[[ ! $hdd_size =~ ^[0-9]+$ ]] && usage
[[ ! $ram_size =~ ^[0-9]+$ ]] && usage
[[ ! $vm_name =~ ^[a-zA-Z_\-]+$ ]] && usage


curl http://distfiles.gentoo.org/releases/amd64/autobuilds/$autobuild_number.DIGESTS.asc > $__dir/gentoo-install-cd-digests
[ $DEBUG_MODE = true ] && cat $__dir/gentoo-install-cd-digests
target_checksum=$(grep -A 1 -i sha512  gentoo-install-cd-digests | grep iso | grep -v CONTENTS | cut -d ' ' -f 1)
existing_checksum=$(shasum -a 512 $__dir/gentoo-install-cd.iso | cut -d ' ' -f 1)

if [ -f $__dir/gentoo-install-cd.iso ] && [ $existing_checksum != $target_checksum ]; then
  curl http://distfiles.gentoo.org/releases/amd64/autobuilds/$autobuild_number > $__dir/gentoo-install-cd.iso
fi

create_vbox_vm $vm_name
create_vbox_hdd $vm_name.vdi

VBoxManage storagectl $vm_name --name "SATA Controller" --add sata --controller IntelAHCI
VBoxManage storageattach $vm_name --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium $vm_name.vdi

VBoxManage storagectl $vm_name --name "IDE Controller" --add ide
VBoxManage storageattach $vm_name --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium $__dir/gentoo-install-cd.iso 

VBoxManage modifyvm $vm_name --memory $ram_size --vram 256 --cpus 4 --natpf1 "guestssh,tcp,,2222,,22" 
VBoxManage startvm $vm_name
