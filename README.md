

# QNAP 定制固件构建工具

![License](https://img.shields.io/badge/License-GPLv3-blue.svg)

本项目用于探讨 RK3588/RK3588S 自动化构建 QNAP TS-AI642 固件镜像。

本工具仅供学习交流, 严禁用于商业用途, 请于24小时之内删除。

## 📋 功能特性

- **U-Boot编译**
- **设备树DTB编译** 
- **QNAP内核多版本定制编译 (5.1.x/5.2.x)**
- **固件镜像生成**

## 🛠️ 支持设备

### 当前配置板型
| 设备型号          | 处理器       | 存储类型 | 状态       |
|-------------------|--------------|----------|------------|
| `rock-5c-rk3588s` | Rockchip RK3588S | eMMC/SD | ✅ 完全支持 |
| `orangepi_5_plus` | Rockchip RK3588 | eMMC/SD  | ✅ 完全支持 |

> 提示：可通过修改 `qnap_build.conf` 扩展新设备支持

## ⚙️ 系统依赖

### 使用环境

- 架构：x86_64 
- 操作系统：Ubuntu 22.04 LTS  Desktop
- 权限要求：root 用户或 sudo 权限


### 依赖

- create_dom.sh会自动检测, 安装构建脚本需要的命令以及依赖,
- 构建过程缺失依赖, 自行调整安装依赖或者调整create_dom.sh的check_dependencies()中相关依赖和命令。

## 📂 主要文件目录结构
```
.
├── boards/                # 设备配置目录
│   ├── qnap_build.conf    # 主构建配置文件
│   └── [板型名称]/         # 各设备独立配置
│       ├── dts-qnap-*/    # 设备树源文件
│       ├── kernel-build-* # 内核构建配置
│       ├── patch/         # qts系统补丁文件
│       ├── build-out/     # 自动创建,构建过程文件
│       └── custom.conf    # 板级配置文件
├── qnap-tools/            # qnap PC1以及源码
├── u-boot/                # U-Boot源码
├── qnap-kernel/           # 自动创建,qnap内核源码
├── qnap-firmware/         # 自动创建,qnap官方固件
├── build_logs/            # 自动创建,构建日志存储
└── 板型名称-版本号-日期.zip  # 最终输出构建压缩文件
```

## ⚡ 快速开始

### 1. 基础构建 (使用默认配置rock-5c-rk3588s-emmc)
```bash
./create_dom.sh
```

### 2. 指定设备构建
```bash
./create_dom.sh board=orangepi_5_plus-emmc
```

### 3. 强制dtb重新编译构建
```bash
./create_dom.sh dtb=force
```
- 默认值dtb=auto, boards/[板型名称]/dts-qnap-*/dts修改后, 再次./create_dom.sh的时候, 如果boards/[板型名称]/build-out目录已经存在对应的dtb文件,不会重新编译dtb。
- dtb=force时, boards/[板型名称]/build-out目录无论已经存在对应的dtb文件, 均重新编译dtb,最后打包整个固件。
- ./create_dom.sh kernel=force
- ./create_dom.sh uboot=force
- 以上类似, 主要是调试打包用. 
- 更多帮助 ./create_dom.sh -h


## 🔧 高级配置

### 一级配置文件 (`boards/qnap_build.conf`)
```conf
# 设备基础配置
BOARD_NAME="rock-5c-rk3588s-emmc"
#对应boards/rock-5c-rk3588s-emmc目录
KERNEL_BOOT_MODE="custom"
#对应uboot引导时 挂载qnap原厂内核还是自编译内核, 如果设定为qnap,引导qnap原厂内核, 也可以系统启动后 fw_printenv qnap_kernel查询后修改 fw_setenv qnap_kernel qnap
QNAP_FIRMWARE_FILE="TS-X42_20250108-5.2.3.3006.zip"
#dom包中放入的初始固件版本,自行去qnap官方网站对应的下载链接
```
### 二级配置文件 (`boards/机型/custom.conf`)
```conf
UBOOT_CONFIG="rock-5c-rk3588s"
#对应u-boot/u-boot-qnap/configs/中的rock-5c-rk3588s_defconfig文件
DTS_FILES="rk3588s-rock-5c"
#对应boards/rock-5c-rk3588s-emmc/dts-qnap-5X0/中rk3588s-rock-5c.dts
```
### 常用参数说明
| 参数                 | 可选值              | 说明                      |
|----------------------|---------------------|-------------------------|
| `kernel_boot_mode`   | qnap/custom         | 内核启动模式              |
| `uboot`              | auto/force/only     | U-Boot 编译控制           |
| `clean`              | board/all           | 清理模式                  |
| `kernel`             | auto/force/unused   | 内核编译策略               |

## ⚡ 扩展新设备支持
### 必要条件 
- 可正常启动的Linux系统
- 完整的5.10内核设备树(dts)
- 已完成至少一次成功构建（确保基础环境正常）
### 适配步骤
以我的 firefly ROC-RK3588S-PC STATION-M3 做适配
https://www.t-firefly.com/product/industry/rocrk3588spc
这里我硬盘用的是 pcie m2
### 1.克隆同样是rk3588s的rock-5c的版型作为模板
```bash
cp -ar boards/rock-5c-rk3588s-emmc boards/roc-rk3588s-pc-emmc
rm -rf boards/roc-rk3588s-pc-emmc/build-out
``` 
### 2.修正qnap的qts系统补丁,目录boards/roc-rk3588s-pc-emmc/patch/

ROC-RK3588S-PC 的linux启动,启动前自行修改dtb中的M2接口

```bash
apt install hwinfo
hwinfo --disk
hwinfo --netcard
``` 
```log
13: PCI 00.0: 10600 Disk                                    
  SysFS ID: /class/block/nvme0n1
  SysFS BusID: nvme0
  SysFS Device Link: /devices/platform/fe190000.pcie/pci0004:40/0004:40:00.0/0004:41:00.0/nvme/nvme0
  Driver: "nvme"
  Driver Modules: "nvme"
  Device File: /dev/nvme0n1
  Device Files: /dev/nvme0n1, /dev/disk/by-id/nvme-YMTC_PC210-512GB-D_YMA1512JA212100802, /dev/disk/by-path/platform-fe190000.pcie-pci-0004:41:00.0-nvme-1, /dev/disk/by-id/nvme-YMTC_PC210-512GB-D_YMA1512JA212100802_1, /dev/disk/by-id/nvme-eui.a428b72aaafb0049  
  Attached to: #1 (Non-Volatile memory controller)

  #M2接口信息

15: None 00.0: 10600 Disk
  SysFS ID: /class/block/mmcblk0
  SysFS BusID: mmc0:0001
  SysFS Device Link: /devices/platform/fe2e0000.mmc/mmc_host/mmc0/mmc0:0001
  Hardware Class: disk
  Model: "Disk"
  Driver: "sdhci-dwcmshc", "mmcblk"
  Device File: /dev/mmcblk0
  Device Files: /dev/mmcblk0, /dev/disk/by-id/mmc-CJTD4R_0xa13cbc38, /dev/disk/by-path/platform-fe2e0000.mmc

  #emmc信息

16: None 00.0: 10600 Disk
  SysFS ID: /class/block/mmcblk1
  SysFS Device Link: /devices/platform/fe2c0000.mmc/mmc_host/mmc1/mmc1:b36d
  Hardware Class: disk
  Model: "Disk"
  Driver: "dwmmc_rockchip", "mmcblk"
  Device File: /dev/mmcblk1
  Device Files: /dev/mmcblk1, /dev/disk/by-path/platform-fe2c0000.mmc, /dev/disk/by-id/mmc-SDABC_0xaa000b59

#sd卡信息

05: None 00.0: 0200 Ethernet controller
  [Created at pci.1030]
  Unique ID: B7sH.TfPFe67fIBB
  SysFS ID: /devices/platform/fe1c0000.ethernet
  SysFS BusID: fe1c0000.ethernet
  Hardware Class: network

#网卡信息

```

- 修改boards/roc-rk3588s-pc-emmc/patch/etc/model.conf
```conf
[System Disk 1]
DEV_DOMAIN = 4
DEV_BUS = B64:D00:F0
DEV_BRIDGE_BUS = B65:D00:F0
DEV_PORT = 3
SLOT_NAME = Disk 1
[System Disk 2]
DEV_DOMAIN = 4
DEV_BUS = B64:D00:F0
DEV_BRIDGE_BUS = B65:D00:F0
DEV_PORT = 2
SLOT_NAME = Disk 2
************

[System Network 1]
DEV_BUS = B-1:fe1c0000.ethernet
DEV_PORT = 0
NIC_NAME = ARM Cortex 64-bit Processor GbE

[Boot Disk 1]
DISK_DRV_TYPE = MMC
DEV_BUS = B-1:fe2e0000.mmc
BOOT_RECOVERY_MODE=2
```
这里跟rock-5c完全一致,不需要修正,如果不一致,修改具体见nanyun论坛我的帖子,跟x86类似
usb 写法也类似,自行修正

- 修改boards/roc-rk3588s-pc-emmc/patch/sbin/patch,删除如下内容

移除不需要的rokc-5c驱动补丁（如蓝牙/WiFi驱动）
```txt
	if [ $(fw_printenv -n qnap_kernel_version) -lt 521 ]; then
		/sbin/insmod /lib/modules/5.10.60-qnap/5.1.x/uhid.ko
		/sbin/insmod /lib/modules/5.10.60-qnap/5.1.x/aic_btusb.ko
		/sbin/insmod /lib/modules/5.10.60-qnap/5.1.x/aic_load_fw.ko
	else
		/sbin/insmod /lib/modules/5.10.60-qnap/uhid.ko
		/sbin/insmod /lib/modules/5.10.60-qnap/aic_btusb.ko
		/sbin/insmod /lib/modules/5.10.60-qnap/aic_load_fw.ko
	fi	
```
### 2.uboot适配
查看u-boot/u-boot-qnap/configs/目录 并没有rk3588s-roc-pc相关的defconfig, 可以去如下网址下载uboot补丁

https://github.com/Joshua-Riek/ubuntu-rockchip/tree/main/packages/u-boot-radxa-rk3588/debian/patches

```bash
cd u-boot/u-boot-qnap/
wget https://github.com/Joshua-Riek/ubuntu-rockchip/raw/refs/heads/main/packages/u-boot-radxa-rk3588/debian/patches/0008-board-add-roc-rk3588s-pc-support.patch
patch -p1 < 0008-board-add-roc-rk3588s-pc-support.patch  
```
configs/roc-rk3588s-pc-rk3588s_defconfig复制进boards/roc-rk3588s-pc-emmc/board-org/备份,
删除掉里面的rock-5c-rk3588s_defconfig.

- 修改u-boot/u-boot-qnap/configs/roc-rk3588s-pc-rk3588s_defconfig文件,尾部添加
```conf
CONFIG_USE_BOOTARGS=y
CONFIG_BOOTARGS="earlycon=uart8250,mmio32,0xfeb50000 ramoops.mem_address=0x110000 ramoops.mem_size=0xf0000 ramoops.console_size=0x80000 uboot_build_date=202308161711 qnap_model=ts642"
CONFIG_SPL_FIT_IMAGE_KB=4096
CONFIG_SPL_FIT_IMAGE_MULTIPLE=2
CONFIG_LOADER_INI="RK3588_115200MINIALL.ini"
CONFIG_ENV_IS_IN_MMC=y
CONFIG_ROCKCHIP_SET_ETHADDR=y
CONFIG_SYS_PROMPT="R-mt# "
```

- 修改boards/roc-rk3588s-pc-emmc/custom.conf
```conf
UBOOT_CONFIG="roc-rk3588s-pc-rk3588s"
 ```

 - 如没有对应机型的uboot适配,这里改成rk3588通用版型,不一定能保证正常启动
```conf
UBOOT_CONFIG="rk3588"
 ```
 ### 3.dts适配
 获取ROC-RK3588S-PC的5.10内核的dts, 可以在firefly官网的下载linux sdk获取, 但是比较繁琐
这里直接从Joshua-Riek的Ubuntu获取
https://github.com/Joshua-Riek/linux-rockchip/blob/jammy/arch/arm64/boot/dts/rockchip/rk3588s-roc-pc.dts

或者armbian获取
https://github.com/armbian/linux-rockchip/blob/rk-5.10-rkr8/arch/arm64/boot/dts/rockchip/rk3588s-roc-pc.dts

down下来,复制到boards/roc-rk3588s-pc-emmc/board-org/目录备份
同时删除掉boards/roc-rk3588s-pc-emmc/board-org/rock-5c-rk3588s.dts
修改rk3588s-roc-pc.dts文件后复制进boards/roc-rk3588s-pc-emmc/dts-qnap-510/目录 以及dts-qnap-520/目录,
同时删除里面的rock-5c-rk3588s.dts

```diff
diff --git a/boards/roc-rk3588s-pc-emmc/dts-qnap-510/rk3588s-roc-pc.dts b/boards/roc-rk3588s-pc-emmc/dts-qnap-510/rk3588s-roc-pc.dts
index 111908a..f30d498 100644
--- a/boards/roc-rk3588s-pc-emmc/dts-qnap-510/rk3588s-roc-pc.dts
+++ b/boards/roc-rk3588s-pc-emmc/dts-qnap-510/rk3588s-roc-pc.dts
@@ -17,13 +17,31 @@
 
 #include "rk3588s.dtsi"
 #include "rk3588-rk806-single.dtsi"
-#include "rk3588-linux.dtsi"
+//#include "rk3588-linux.dtsi"
 
 #define M2_SATA_OR_PCIE 0
 
 / {
-       model = "ROC-RK3588S-PC V12(Linux)";
-       compatible = "firefly,roc-rk3588s-pc", "firefly,station-m3", "rockchip,rk3588";
+       model = "QNAP TS-AI642";
+       compatible = "rockchip,rk3588-nvr-demo-v10", "rockchip,rk3588";
+
+       aliases {
+               mmc0 = &sdhci;
+               mmc1 = &sdmmc;
+       };
+
+       fiq_debugger: fiq-debugger {
+               compatible = "rockchip,fiq-debugger";
+               rockchip,serial-id = <2>;
+               rockchip,wake-irq = <0>;
+               /* If enable uart uses irq instead of fiq */
+               rockchip,irq-mode-enable = <1>;
+               rockchip,baudrate = <115200>;  /* Only 115200 and 1500000 */
+               interrupts = <GIC_SPI 423 IRQ_TYPE_LEVEL_LOW>;
+               pinctrl-names = "default";
+               pinctrl-0 = <&uart2m0_xfer>;
+               status = "okay";
+       };
 
        adc_keys: adc-keys {
                status = "okay";
@@ -49,7 +67,7 @@
                rockchip,codec = <&dp0 1>;
                rockchip,jack-det;
        };
-
+/*
        es8388_sound: es8388-sound {
                status = "okay";
                compatible = "rockchip,multicodecs-card";
@@ -78,7 +96,7 @@
                pinctrl-names = "default";
                pinctrl-0 = <&hp_det>;
        };
-
+*/
        fan: pwm-fan {
                compatible = "pwm-fan";
                #cooling-cells = <2>;
@@ -287,10 +305,6 @@
 
 };
 
-&chosen {
-       bootargs = "earlycon=uart8250,mmio32,0xfeb50000 console=ttyFIQ0 coherent_pool=1m irqchip.gicv3_pseudo_nmi=0";
-};
-
 &av1d {
        status = "okay";
 };
@@ -535,7 +549,7 @@
                };
        };
 };
-
+/*
 &i2c3 {
        status = "okay";
        es8388: es8388@11 {
@@ -551,7 +565,7 @@
                pinctrl-0 = <&i2s0_mclk>;
        };
 };
-
+*/
 &i2c4 {
        status = "okay";
        pinctrl-names = "default";
@@ -826,7 +840,7 @@
 };
 
 &sdmmc {
-       status = "okay";
+       status = "disable";
        max-frequency = <150000000>;
        no-sdio;
        no-mmc;

 ```
注释掉rk3588-linux.dtsi, 删掉chosen节点, 添加fiq_debugger节点baudrate=115200 ,
&sdmmc(sd卡) 给disable, es8388声卡给注释掉


- 修改boards/roc-rk3588s-pc-emmc/custom.conf,指定dts文件名
```conf
DTS_FILES="rk3588s-roc-pc"
 ```
 ### 4.内核适配 
 分别修改boards/roc-rk3588s-pc-emmc/kernel-build-510/kernel-build.conf 以及kernel-build-520/kernel-build.conf
 删除其中的下列行,这是给rock-5c的aic8800的驱动编译的内核删除
 ```conf
        ["AIC8800-蓝牙wifi驱动"]="CONFIG_AIC_WLAN_SUPPORT=y\nCONFIG_AIC8800_WLAN_SUPPORT=m\nCONFIG_AIC_LOADFW_SUPPORT=m"
 ```
删除boards/roc-rk3588s-pc-emmc/kernel-build-510/patchs 以及kernel-build-520/patchs目录中的对应的aic8800补丁文件
 ```txt
0005-fix-add-aic-usb-blue.patch
0006-add-usb-aic8800-wif-driver-org.patch
0007-change-aic8800-firmware-patch-to-lib-firmware.patch
 ```

 ### 5.修改boards/qnap_build.conf
 ```conf
 BOARD_NAME="roc-rk3588s-pc-emmc"
 ```

 ### 6.回到qnap-build主目录执行编译指令
 ```bash
./create_dom.sh
```
 生成roc-rk3588s-pc-emmc-523-20250419.zip

 ### 7.调试
  roc-rk3588s-pc-emmc-523-20250419.zip解压后全盘刷入roc-rk3588s-pc的emmc
  正常安装系统,发现风扇一直全速运转,qnap下admin权限 执行
 ```bash  
[~] # cat /sys/class/hwmon/hwmon*/name
tcpm_source_psy_2_0022
pwmfan
soc_thermal
bigcore0_thermal
bigcore1_thermal
littlecore_thermal
center_thermal
gpu_thermal
npu_thermal
[~] # cat /sys/class/hwmon/hwmon0/name
tcpm_source_psy_2_0022
[~] # cat /sys/class/hwmon/hwmon1/name
pwmfan
[~] # 
```
发现pwm-fan在hwmon1上,进行调试,解包patch
 ```bash
[~] # qnap_patch --unpack
执行解包...
unpack解压成功，生成的目录在/tmp/patch

```
修改其中/tmp/patch/etc/model.conf中的SIO_HWMON_INDEX = 0 为 = 1
```conf
SIO_HWMON_INDEX = 1
```
重新打包
```bash
[~] # qnap_patch --repack
执行打包...
打包目录/tmp/patch 写入设备/dev/mmcblk0 reboot 重启生效
```
重启生效,重启后查看风扇已经自动温控了


 ### 8.完成roc-rk3588s-pc-emmc的patch修正
修改boards/roc-rk3588s-pc-emmc/patch/etc/model.conf
```conf
SIO_HWMON_INDEX = 1
```

全部clean后 全部重新编译生成dom
 ```bash
./create_dom.sh clean=all
./create_dom.sh 
```

## 本项目会使用,下载,参考以下开源项目部分代码：
- [Joshua-Riek/ubuntu-rockchip](https://github.com/Joshua-Riek/ubuntu-rockchip)
- [armbian/linux-rockchip](https://github.com/armbian/linux-rockchip)
- [radxa](https://github.com/radxa)
- [firefly](https://gitlab.com/firefly-linux/prebuilts/gcc/linux-x86/aarch64/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu)
- [qnap](https://sourceforge.net/projects/qosgpl/)


## 📜 许可协议

本项目采用 [GPL-3.0 License](LICENSE)

