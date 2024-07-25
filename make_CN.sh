#!/bin/bash

URL="$1"              # 移植包下载地址
GITHUB_ENV="$2"       # 输出环境变量
GITHUB_WORKSPACE="$3" # 工作目录

device=peridot # Device code

zip_name=$(echo ${URL} | cut -d"/" -f5)        #包名，例：miui_PERIDOT_OS1.0.14.0.UNPCNXM_f31a1bac03_14.0.zip
os_version=$(echo ${URL} | cut -d"/" -f4)      #版本号，例：OS1.0.14.0.UNPCNXM  
android_version=$(echo ${URL} | cut -d"_" -f5 | cut -d"." -f1) # Android 版本号, 例: 14
build_time=$(date) && build_utc=$(date -d "$build_time" +%s)   # 构建时间

sudo timedatectl set-timezone Asia/Shanghai
sudo apt-get remove -y firefox zstd
sudo apt-get install python3 aria2
sudo chmod -R 777 "$GITHUB_WORKSPACE"/tools

magiskboot="$GITHUB_WORKSPACE"/tools/magiskboot
ksud="$GITHUB_WORKSPACE"/tools/ksud
a7z="$GITHUB_WORKSPACE"/tools/7zzs
zstd="$GITHUB_WORKSPACE"/tools/zstd
payload_extract="$GITHUB_WORKSPACE"/tools/payload_extract
erofs_extract="$GITHUB_WORKSPACE"/tools/extract.erofs
erofs_mkfs="$GITHUB_WORKSPACE"/tools/mkfs.erofs
vbmeta="$GITHUB_WORKSPACE"/tools/vbmeta-disable-verification
lpmake="$GITHUB_WORKSPACE"/tools/lpmake
apktool_jar="java -jar "$GITHUB_WORKSPACE"/tools/apktool.jar"

Red='\033[1;31m'    # 粗体红色 Bold red
Yellow='\033[1;33m' # 粗体黄色 Bold yellow
Blue='\033[1;34m'   # 粗体蓝色 Bold blue
Green='\033[1;32m'  # 粗体绿色 Bold green

Start_Time() {
  Start_ns=$(date +'%s%N')
}

End_Time() {
  local End_ns time
  End_ns=$(date +'%s%N')
  time=$(expr $End_ns - $Start_ns)
  [[ -z "$time" ]] && return 0

  local s ms ns h min
  ns=${time:0-9}
  s=${time%$ns}

  if [[ $s -ge 10800 ]]; then
    echo -e "${Green}- 本次$1用时: ${Blue}少于100毫秒"
	echo -e "${Green}- This time $1 took: ${Blue} is less than 100 milliseconds"
  elif [[ $s -ge 3600 ]]; then
    ms=$(expr $ns / 1000000)
    h=$(expr $s / 3600)
    s=$(expr $s % 3600)
    [[ $s -ge 60 ]] && {
      min=$(expr $s / 60)
      s=$(expr $s % 60)
    }
    echo -e "${Green}- 本次$1用时: ${Blue}$h小时$min分$s秒$ms毫秒"
	echo -e "${Green}- This time $1 took: ${Blue}$h hours $min minutes $s seconds $ms milliseconds"
  elif [[ $s -ge 60 ]]; then
    ms=$(expr $ns / 1000000)
    min=$(expr $s / 60)
    s=$(expr $s % 60)
    echo -e "${Green}- 本次$1用时: ${Blue}$min分$s秒$ms毫秒"
	echo -e "${Green}- This time $1 took: ${Blue}$min minutes$s seconds$ms milliseconds"
  elif [[ -n $s ]]; then
    ms=$(expr $ns / 1000000)
    echo -e "${Green}- 本次$1用时: ${Blue}$s秒$ms毫秒"
	echo -e "${Green}- This time $1 took: ${Blue}$s seconds $ms milliseconds"
  else
    ms=$(expr $ns / 1000000)
    echo -e "${Green}- 本次$1用时: ${Blue}$ms毫秒"
	echo -e "${Green}- This time $1 took: ${Blue}$ms milliseconds"
  fi
}

### System package download
echo -e "${Red}- Start downloading system package"
Start_Time
if [ ! -f "$GITHUB_WORKSPACE/${zip_name}" ]; then
    # If the system package does not exist, download it
    aria2c -x16 -j$(nproc) -U "Mozilla/5.0" -d "$GITHUB_WORKSPACE" "$URL"
else
    echo "The system package already exists, no need to download"
fi
End_Time Download system package
### System package download completed

### Unpacking
echo -e "${Red}- 准备解包"
echo -e "${Red}- ready to unpack"
mkdir -p "$GITHUB_WORKSPACE"/Extra_dir
mkdir -p "$GITHUB_WORKSPACE"/"${device}" #The storage directory of the base package payload.bin
mkdir -p "$GITHUB_WORKSPACE"/images/config #The directory where the transplant packages product, system, and system_ext are stored（images）
mkdir -p "$GITHUB_WORKSPACE"/zip

echo -e "${Yellow}- 开始解包"
echo -e "${Yellow}- Start unpacking"
Start_Time
$a7z x "$GITHUB_WORKSPACE"/${zip_name} -o"$GITHUB_WORKSPACE"/"${device}" payload.bin >/dev/null
echo -e "${Red}- 开始解payload"
echo -e "${Red}- Start extracting payload"
$payload_extract -s -o "$GITHUB_WORKSPACE"/Extra_dir/ -i "$GITHUB_WORKSPACE"/"${device}"/payload.bin -x -T0
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/payload.bin
for i in product system system_ext; do
  echo -e "${Red}- 开始转移${i}"
  echo -e "${Red}- Start transfer ${i}"
  sudo mv -f "$GITHUB_WORKSPACE"/Extra_dir/$i.img "$GITHUB_WORKSPACE"/images/
done

echo -e "${Red}- 转移完成，开始删除原包"
echo -e "${Red}- Transfer completed, start deleting the original package"
rm -rf "$GITHUB_WORKSPACE"/${zip_name} #删除原包 Delete the original package
End_Time 

echo -e "${Red}- 开始第一次分解image"
echo -e "${Red}- Start first decomposition of image"
for i in mi_ext odm system_dlkm vendor vendor_dlkm; do
  echo -e "${Yellow}- 正在分解image: $i.img"
  echo -e "${Yellow}- Decomposing image: $i.img"
  cd "$GITHUB_WORKSPACE"/"${device}"
  sudo $erofs_extract -s -i "$GITHUB_WORKSPACE"/Extra_dir/$i.img -x
  rm -rf "$GITHUB_WORKSPACE"/Extra_dir/$i.img
done

sudo mkdir -p "$GITHUB_WORKSPACE"/"${device}"/firmware-update/
sudo cp -rf "$GITHUB_WORKSPACE"/Extra_dir/* "$GITHUB_WORKSPACE"/"${device}"/firmware-update/ #Base package mi_ext odm system_dlkm vendor vendor_dlkm storage directory
cd "$GITHUB_WORKSPACE"/images
echo -e "${Red}- 开始第二次分解image"
echo -e "${Red}- Start second decomposition of image"
for i in product system system_ext; do
  echo -e "${Yellow}- 正在分解: $i"
  echo -e "${Yellow}- Decomposing: $i"
  sudo $erofs_extract -s -i "$GITHUB_WORKSPACE"/images/$i.img -x
  rm -rf "$GITHUB_WORKSPACE"/images/$i.img
done

### Unpacking completed

### Write variables

echo -e "${Red}- Start writing variables"
# Build date
echo "build_time=$build_time" >>$GITHUB_ENV
echo -e "${Blue}- 构建日期: $build_time"
echo -e "${Blue}- Build date: $build_time"
# Package version
echo "os_version=$os_version" >>$GITHUB_ENV
echo -e "${Blue}- 移植包版本: $os_version"
echo -e "${Blue}- Porting package version: $os_version"
# 包安全补丁
# Package security patches
system_build_prop=$(find "$GITHUB_WORKSPACE"/images/system/system/ -maxdepth 1 -type f -name "build.prop" | head -n 1)
security_patch=$(grep "ro.build.version.security_patch=" "$system_build_prop" | awk -F "=" '{print $2}')
echo -e "${Blue}- 包安全补丁版本: $security_patch"
echo -e "${Blue}- Package security patch version: $security_patch"
echo "security_patch=$security_patch" >>$GITHUB_ENV
# Package baseline version
base_line=$(grep "ro.system.build.id=" "$system_build_prop" | awk -F "=" '{print $2}')
echo -e "${Blue}- 包基线版本: $base_line"
echo -e "${Blue}- Package baseline version: $base_line"
echo "base_line=$base_line" >>$GITHUB_ENV

### End of writing variables

### Function repair

echo -e "${Red}- 开始功能修复"
echo -e "${Red}- Start function repair"
Start_Time

# 添加 KernelSU 支持 (可选择)
# Add KernelSU support (optional)
echo -e "${Red}- 添加 KernelSU 支持 (可选择)"
echo -e "${Red}- Add KernelSU support (optional)"
mkdir -p "$GITHUB_WORKSPACE"/init_boot
cd "$GITHUB_WORKSPACE"/init_boot
cp -f "$GITHUB_WORKSPACE"/"${device}"/firmware-update/init_boot.img "$GITHUB_WORKSPACE"/init_boot/
$ksud boot-patch -b "$GITHUB_WORKSPACE"/init_boot/init_boot.img --magiskboot $magiskboot --kmi android14-5.15
mv -f "$GITHUB_WORKSPACE"/init_boot/kernelsu_boot*.img "$GITHUB_WORKSPACE"/"${device}"/firmware-update/init_boot-kernelsu.img
rm -rf "$GITHUB_WORKSPACE"/init_boot

# Replace Replace system framework.jar
echo -e "${Red}- Replace system framework.jar"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/framework.zip -d "$GITHUB_WORKSPACE"/images/system/framework

# Replace Replace system services.jar
echo -e "${Red}- Replace system services.jar"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/services.zip -d "$GITHUB_WORKSPACE"/images/system/framework

# Replace Replace system_ext miui-services.jar
echo -e "${Red}- Replace system_ext miui-services.jar"
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/miui-services.jar "$GITHUB_WORKSPACE"/images/system/system_ext/framework

# Replace Replace system_ext miui-framework.jar
echo -e "${Red}- Replace system_ext miui-framework.jar"
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/miui-framework.jar "$GITHUB_WORKSPACE"/images/system/system_ext/framework

# Replace vendor fstab
echo -e "${Red}- Replace vendor fstab"
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/fstab.qcom "$GITHUB_WORKSPACE"/"${device}"/vendor/etc/fstab.qcom

# add product's overlay vietnamese
echo -e "${Red}- add product's overlay vietnamese"
#sudo rm -rf "$GITHUB_WORKSPACE"/images/product/overlay/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/overlay.zip -d "$GITHUB_WORKSPACE"/images/product/overlay
#
# 替换 device_features 文件
# Replace the device_features file
echo -e "${Red}- 替换 device_features 文件"
echo -e "${Red}- replace device_features file"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/etc/device_features/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/device_features.zip -d "$GITHUB_WORKSPACE"/images/product/etc/device_features/

# 修复精准电量 (亮屏可用时长)
#Fix accurate battery life (screen on time)
echo -e "${Red}- 修复精准电量 (亮屏可用时长)"
echo -e "${Red}- Repair accurate power (screen on time)"
sudo rm -rf "$GITHUB_WORKSPACE"/images/system/system/app/PowerKeeper/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/PowerKeeper.zip -d "$GITHUB_WORKSPACE"/images/system/system/app/PowerKeeper/

# 修复注视感知
# Fix gaze perception
#echo -e "${Red}- 修复注视感知"
#echo -e "${Red}- fix gaze perception"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/app/MiAONService*
mkdir "$GITHUB_WORKSPACE"/images/product/app/MiAONService
sudo cp "$GITHUB_WORKSPACE"/"${device}"_files/MiAONService.apk "$GITHUB_WORKSPACE"/images/product/app/MiAONService

# 统一 build.prop
echo -e "${Red}- 统一 build.prop"
sudo sed -i 's/ro.build.user=[^*]*/ro.build.user=grass2/' "$GITHUB_WORKSPACE"/images/system/system/build.prop
for port_build_prop in $(sudo find "$GITHUB_WORKSPACE"/images/ -type f -name "build.prop"); do
  sudo sed -i 's/build.date=[^*]*/build.date='"$build_time"'/' "$port_build_prop"
  sudo sed -i 's/build.date.utc=[^*]*/build.date.utc='"$build_utc"'/' "$port_build_prop"
  sudo sed -i 's/persist.device_config.mglru_native.lru_gen_config=[^*]*/persist.device_config.mglru_native.lru_gen_config=all/' "$port_build_prop"
done
for vendor_build_prop in $(sudo find "$GITHUB_WORKSPACE"/"${device}"/ -type f -name "*build.prop"); do
  sudo sed -i 's/build.date=[^*]*/build.date='"$build_time"'/' "$vendor_build_prop"
  sudo sed -i 's/build.date.utc=[^*]*/build.date.utc='"$build_utc"'/' "$vendor_build_prop"
  sudo sed -i 's/ro.mi.os.version.incremental=[^*]*/ro.mi.os.version.incremental='"$os_version"'/' "$vendor_build_prop"
done


# 精简部分应用
# Simplify some applications
echo -e "${Red}- Simplify some applications"
echo -e "${Red}- 精简部分应用"
apps=("MIGalleryLockscreen" "MIUIDriveMode" "MIUIDuokanReader" "MIUIGameCenter" "MIUINewHomeMIUI15" "MIUINewHome" "MIUIYoupin" "MIUIHuanJi" "MIUIMiDrive" "MIUIVirtualSim" "ThirdAppAssistant" "XMRemoteController" "MIUIVipAccount" "MiuiScanner" "Xinre" "SmartHome" "MiShop" "MiRadio" "MediaEditor" "BaiduIME" "iflytek.inputmethod" "MIService" "MIUIEmail" "MIUIVideo" "MIUIMusicT")
for app in "${apps[@]}"; do
  appsui=$(sudo find "$GITHUB_WORKSPACE"/images/product/data-app/ -type d -iname "*${app}*")
  if [[ -n $appsui ]]; then
    echo -e "${Yellow}- 找到精简目录: $appsui"
	echo -e "${Yellow}- Found simplified directory: $appsui"
    sudo rm -rf "$appsui"
  fi
done

# 分辨率修改
# Resolution modification
echo -e "${Red}- 分辨率修改"
echo -e "${Red}- Resolution modification"
sudo sed -i 's/persist.miui.density_v2=[^*]*/persist.miui.density_v2=480/' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
# Add aptX Lossless
echo -e "${Red}- Add aptX Lossless"
sudo sed -i '/# end of file/i persist.vendor.qcom.bluetooth.aptxadaptiver2_2_support=true' "$GITHUB_WORKSPACE"/"${device}"/vendor/build.prop


# 占位广告应用
# Placeholder advertising application
echo -e "${Red}- 占位广告应用"
echo -e "${Red}- Placeholder advertising application"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/app/MSA/*
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/MSA.apk "$GITHUB_WORKSPACE"/images/product/app/MSA

# 替换完美图标
# Replace the perfect icon
echo -e "${Red}- 替换完美图标"
echo -e "${Red}- Replace the perfect icon"
cd "$GITHUB_WORKSPACE"
git clone https://github.com/pzcn/Perfect-Icons-Completion-Project.git icons --depth 1
for pkg in "$GITHUB_WORKSPACE"/images/product/media/theme/miui_mod_icons/dynamic/*; do
  if [[ -d "$GITHUB_WORKSPACE"/icons/icons/$pkg ]]; then
    rm -rf "$GITHUB_WORKSPACE"/icons/icons/$pkg
  fi
done
rm -rf "$GITHUB_WORKSPACE"/icons/icons/com.xiaomi.scanner
mv "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons.zip
rm -rf "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons
mkdir -p "$GITHUB_WORKSPACE"/icons/res
mv "$GITHUB_WORKSPACE"/icons/icons "$GITHUB_WORKSPACE"/icons/res/drawable-xxhdpi
cd "$GITHUB_WORKSPACE"/icons
zip -qr "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons.zip res
cd "$GITHUB_WORKSPACE"/icons/themes/Hyper/
zip -qr "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons.zip layer_animating_icons
cd "$GITHUB_WORKSPACE"/icons/themes/common/
zip -qr "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons.zip layer_animating_icons
mv "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons.zip "$GITHUB_WORKSPACE"/images/product/media/theme/default/icons
mv "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons.zip "$GITHUB_WORKSPACE"/images/product/media/theme/default/dynamicicons
rm -rf "$GITHUB_WORKSPACE"/icons

#去除avb2.0校验
#Remove avb2.0 checksum
for i in  vbmeta.img vbmeta_system.img; do
  echo -e "${Red}- 正在去 "$i" avb2.0校验"
  echo -e "${Red}- Going to "$i" avb2.0 verification"
  sudo $vbmeta "$GITHUB_WORKSPACE"/Extra_dir/"$i"
done

# 常规修改
# General modification
echo -e "${Red}- 常规修改"
echo -e "${Red}- General modification"
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/vendor/recovery-from-boot.p
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/vendor/bin/install-recovery.sh

# 修复 init 崩溃
# Fix init crash
echo -e "${Red}- 修复 init 崩溃"
echo -e "${Red}- fix init crash"
sudo sed -i "/start qti-testscripts/d" "$GITHUB_WORKSPACE"/"${device}"/vendor/etc/init/hw/init.qcom.rc

# 内置 TWRP
# Built-in TWRP
echo -e "${Red}- 内置 TWRP"
echo -e "${Red}- Built-in TWRP"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/recovery.zip -d "$GITHUB_WORKSPACE"/"${device}"/firmware-update/

# 添加刷机脚本
# Add flashing script
echo -e "${Red}- 添加刷机脚本"
echo -e "${Red}- Add flashing script"
sudo unzip -o -q "$GITHUB_WORKSPACE"/tools/flashtools.zip -d "$GITHUB_WORKSPACE"/images

# Remove Android signature verification
sudo mkdir -p "$GITHUB_WORKSPACE"/apk/
echo -e "${Red}- 移除 Android 签名校验"
echo -e "${Red}- Remove Android signature verification"
sudo cp -rf "$GITHUB_WORKSPACE"/images/system/system/framework/services.jar "$GITHUB_WORKSPACE"/apk/services.apk
cd "$GITHUB_WORKSPACE"/apk
sudo $apktool_jar d -q "$GITHUB_WORKSPACE"/apk/services.apk
fbynr='getMinimumSignatureSchemeVersionForTargetSdk'
sudo find "$GITHUB_WORKSPACE"/apk/services/smali_classes2/com/android/server/pm/ "$GITHUB_WORKSPACE"/apk/services/smali_classes2/com/android/server/pm/pkg/parsing/ -type f -maxdepth 1 -name "*.smali" -exec grep -H "$fbynr" {} \; | cut -d ':' -f 1 | while read -r i; do
  hs=$(grep -n "$fbynr" "$i" | cut -d ':' -f 1)
  sz=$(sudo tail -n +"$hs" "$i" | grep -m 1 "move-result" | tr -dc '0-9')
  hs1=$(sudo awk -v HS=$hs 'NR>=HS && /move-result /{print NR; exit}' "$i")
  hss=$hs
  sedsc="const/4 v${sz}, 0x0"
  { sudo sed -i "${hs},${hs1}d" "$i" && sudo sed -i "${hss}i\\${sedsc}" "$i"; } && echo -e "${Yellow}- ${i} Successfully modified"
done
cd "$GITHUB_WORKSPACE"/apk/services/
sudo $apktool_jar b -q -f -c "$GITHUB_WORKSPACE"/apk/services/ -o services.jar
sudo cp -rf "$GITHUB_WORKSPACE"/apk/services/services.jar "$GITHUB_WORKSPACE"/images/system/system/framework/services.jar

# 替换更改文件/删除多余文件
# Replace changed files/delete redundant files
echo -e "${Red}- 替换更改文件/删除多余文件"
echo -e "${Red}- replace changed files/delete redundant files"
sudo cp -r "$GITHUB_WORKSPACE"/"${device}"/* "$GITHUB_WORKSPACE"/images #(Copy all files and folders under the device ${device} directory, including the contents of subdirectories, to the $GITHUB_WORKSPACE/images directory.)
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"_files
End_Time Function repair
### Function repair completed

### Generate super.img
echo -e "${Red}- Start Packaging super.img"
Start_Time
partitions=("mi_ext" "odm" "product" "system" "system_ext" "system_dlkm" "vendor" "vendor_dlkm")
for partition in "${partitions[@]}"; do
  echo -e "${Red}- 正在生成: $partition"
  echo -e "${Red}- Generating: $partition"
  sudo python3 "$GITHUB_WORKSPACE"/tools/fspatch.py "$GITHUB_WORKSPACE"/images/$partition "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config
  sudo python3 "$GITHUB_WORKSPACE"/tools/contextpatch.py "$GITHUB_WORKSPACE"/images/$partition "$GITHUB_WORKSPACE"/images/config/"$partition"_file_contexts
  sudo $erofs_mkfs --quiet -zlz4hc,9 -T 1230768000 --mount-point /$partition --fs-config-file "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config --file-contexts "$GITHUB_WORKSPACE"/images/config/"$partition"_file_contexts "$GITHUB_WORKSPACE"/images/$partition.img "$GITHUB_WORKSPACE"/images/$partition
  eval "${partition}_size=$(du -sb "$GITHUB_WORKSPACE"/images/$partition.img | awk '{print $1}')"
  sudo rm -rf "$GITHUB_WORKSPACE"/images/$partition
done
sudo rm -rf "$GITHUB_WORKSPACE"/images/config
$lpmake --metadata-size 65536 --super-name super --block-size 4096 --partition mi_ext_a:readonly:"$mi_ext_size":qti_dynamic_partitions_a --image mi_ext_a="$GITHUB_WORKSPACE"/images/mi_ext.img --partition mi_ext_b:readonly:0:qti_dynamic_partitions_b --partition odm_a:readonly:"$odm_size":qti_dynamic_partitions_a --image odm_a="$GITHUB_WORKSPACE"/images/odm.img --partition odm_b:readonly:0:qti_dynamic_partitions_b --partition product_a:readonly:"$product_size":qti_dynamic_partitions_a --image product_a="$GITHUB_WORKSPACE"/images/product.img --partition product_b:readonly:0:qti_dynamic_partitions_b --partition system_a:readonly:"$system_size":qti_dynamic_partitions_a --image system_a="$GITHUB_WORKSPACE"/images/system.img --partition system_b:readonly:0:qti_dynamic_partitions_b --partition system_ext_a:readonly:"$system_ext_size":qti_dynamic_partitions_a --image system_ext_a="$GITHUB_WORKSPACE"/images/system_ext.img --partition system_ext_b:readonly:0:qti_dynamic_partitions_b --partition system_dlkm_a:readonly:"$system_dlkm_size":qti_dynamic_partitions_a --image system_dlkm_a="$GITHUB_WORKSPACE"/images/system_dlkm.img --partition system_dlkm_b:readonly:0:qti_dynamic_partitions_b --partition vendor_a:readonly:"$vendor_size":qti_dynamic_partitions_a --image vendor_a="$GITHUB_WORKSPACE"/images/vendor.img --partition vendor_b:readonly:0:qti_dynamic_partitions_b --partition vendor_dlkm_a:readonly:"$vendor_dlkm_size":qti_dynamic_partitions_a --image vendor_dlkm_a="$GITHUB_WORKSPACE"/images/vendor_dlkm.img --partition vendor_dlkm_b:readonly:0:qti_dynamic_partitions_b --device super:8321499136 --metadata-slots 3 --group qti_dynamic_partitions_a:8321499136 --group qti_dynamic_partitions_b:8321499136 --virtual-ab -F --output "$GITHUB_WORKSPACE"/images/super.img
End_Time Packaging super
for i in mi_ext odm product system system_ext system_dlkm vendor vendor_dlkm; do
  rm -rf "$GITHUB_WORKSPACE"/images/$i.img
done
### 生成 super.img 结束
### Generate super.img End

### 输出卡刷包
### Output card flash package
echo -e "${Red}- 开始生成卡刷包"
echo -e "${Red}- 开始压缩super.zst"
echo -e "${Red}- Start generating card flash package"
echo -e "${Red}- Start compressing super.zst"
Start_Time
sudo find "$GITHUB_WORKSPACE"/images/ -exec touch -t 200901010000.00 {} \;
zstd -12 -f "$GITHUB_WORKSPACE"/images/super.img -o "$GITHUB_WORKSPACE"/images/super.zst --rm
End_Time Compress super.zst
# Generate card flash package
echo -e "${Red}-Generate card flash package"
Start_Time
sudo $a7z a "$GITHUB_WORKSPACE"/zip/miui_${device}_${os_version}.zip "$GITHUB_WORKSPACE"/images/* >/dev/null
sudo rm -rf "$GITHUB_WORKSPACE"/images
End_Time Compressed card flash pack
# Custom ROM package name
echo -e "${Red}- Custom ROM package name"
md5=$(md5sum "$GITHUB_WORKSPACE"/zip/miui_${device}_${os_version}.zip)
echo "MD5=${md5:0:32}" >>$GITHUB_ENV
zip_md5=${md5:0:10}
rom_name="miui_peridot_${os_version}_${zip_md5}_${android_version}.0_grass2.zip"
sudo mv "$GITHUB_WORKSPACE"/zip/miui_${device}_${os_version}.zip "$GITHUB_WORKSPACE"/zip/"${rom_name}"
echo "rom_name=$rom_name" >>$GITHUB_ENV
### 输出卡刷包结束
### Output card flash package is finished