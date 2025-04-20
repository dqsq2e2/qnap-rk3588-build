qnap_build.conf文件的一些基本说明
# ==================== 基础配置 ====================
BOARD_NAME="orangepi_5_plus-sd"          # 目标板型（必须以 -emmc/-sd 结尾）
UBOOT_CONFIG="orangepi_5_plus"			 # 编译uboot对应的orangepi_5_plus开头的defconfig文件    即 u-boot/u-boot-qnap/configs/orangepi_5_plus_defconfig	
DTS_FILES="rk3588-orangepi-5-plus"		 # 编译kernel 对应的rk3588-orangepi-5-plus开头的dts文件 即 boards/orangepi_5_plus-sd/dts-qnap-510/rk3588-orangepi-5-plus.dts

# ==================== 固件下载配置 ====================
QNAP_FIRMWARE_FILE="TS-X42_20240520-5.1.7.2770.zip"  # 官方固件文件名,写入dom的初始固件版本
QNAP_FIRMWARE_URL="https://download.qnap.com.cn/Storage/TS-X42/"


# ==================== 内核启动模式配置 ====================
# KERNEL 启动模式:
#   qnap   - 使用QNAP原厂内核 (默认)
#   custom - 使用自定义编译内核
KERNEL_BOOT_MODE="custom"

# ===================== UBOOT编译模式 =====================
# U-Boot 编译模式:
#   auto  - 自动检测已有编译产物 (默认)
#   force - 强制重新编译
#   only  - 仅编译U-Boot后退出
UBOOT_MODE="auto"

# ===================== DTB编译模式 =====================
# DTB 编译模式:
#   auto  - 自动检测已有dtb文件 (默认)
#   force - 强制重新编译
#   only  - 仅编译dtb后退出
DTB_MODE="auto"

# ==================== 内核编译模式 ====================
# KERNEL 编译模式:
#   auto  - 自动检测已有内核文件 (默认)
#   force - 强制重新编译
#   only  - 仅编译内核
#   unused - 不编译内核
KERNEL_MODE="auto"

# ================== 内核编译下载 =====================
COMPILE_DOWNURL="https://sourceforge.net/projects/qosgpl/files/QNAP%20NAS%20Tool%20Chains/Cross%20Toolchain%20SDK%20%28arm64%29.tar.gz/download"
#新增内核时必须确保 MIN_VER 严格大于前一条目的 MAX_VER
declare -g -A KERNEL_VERSIONS=(
    # ████ 条目1: 适用于 QTS 5.1.0 ~ 5.2.0 ████
    [510]='(
        # 资源文件分段下载配置
        [part0]="https://sourceforge.net/projects/qosgpl/files/QNAP%20NAS%20GPL%20Source/QTS%205.1.0/QTS_Kernel_5.1.0.20230808.tar.gz.0/download"
        [part1]="https://sourceforge.net/projects/qosgpl/files/QNAP%20NAS%20GPL%20Source/QTS%205.1.0/QTS_Kernel_5.1.0.20230808.tar.gz.1/download"
        [dir]="GPL_QTS"      # 解压后的根目录名称
        [parts]="2"           # 分卷总数
        [tar_opts]="z"        # tar解压参数：z=用gzip解压

        # ▄▄▄ 版本控制关键参数 ▄▄▄
        [MIN_VER]="510"       # 最低兼容版本 (QTS 5.1.0 → 0x01FE → 510)
        [MAX_VER]="520"       # 最高兼容版本 (QTS 5.2.0 → 0x0208 → 520)

        # ▄▄▄ 存储偏移量 ▄▄▄
        [dtb_offset]="$((0x219800))"    # DTB起始地址 (0x00219800 00 21 98 00)
        [kernel_offset]="$((0x241800))"  # 内核起始地址 (0x00241800 00 24 18 00)

        [sectors]="$((0x32000))"        # 分配扇区数 (0x32000 × 512 = 104MB)
    )'

    # ████ 条目2: 适用于 QTS 5.2.1 ~ 5.3.0 ████
    [520]='(
        [part0]="https://sourceforge.net/projects/qosgpl/files/QNAP%20NAS%20GPL%20Source/QTS%205.2.0/QTS_Kernel_5.2.0.20240910.0.tar.gz/download"
        [part1]="https://sourceforge.net/projects/qosgpl/files/QNAP%20NAS%20GPL%20Source/QTS%205.2.0/QTS_Kernel_5.2.0.20240910.1.tar.gz/download"
        [dir]="GPL_QTS"
        [parts]="2"
        [tar_opts]="z"

        # ▄▄▄ 版本控制 ▄▄▄
        [MIN_VER]="521"       # QTS 5.2.1 → 0x0209 → 521
        [MAX_VER]="530"       # QTS 5.3.0 → 0x0212 → 530

        # ▄▄▄ 存储布局 ▄▄▄
        [dtb_offset]="$((0x21B800))"    # DTB起始地址 (0x0021b800 00 21 b8 00)
        [kernel_offset]="$((0x273800))" # 内核起始地址 (0x00273800 00 27 38 00)

        [sectors]="$((0x32000))"        # 分区大小保持104MB
    )'
)
##############################################################################
# 关键字段注释规则：
# 1. 版本号转换：
#    QTS版本 X.Y.Z → 十六进制 0xXXYY → 十进制
#    示例:
#      5.1.0 → X=5(0x05), Y=1(0x01) → 0x0501 → 十进制 1281
#      但QNAP实际使用 MIN_VER=510 (0x01FE)，需以实测值为准
#
# 2. 偏移量规范：
#    - dtb_offset 必须为 kernel_offset 的前置地址
#    - 所有偏移需满足 512字节对齐，验证命令：
#      echo "ibase=16; $(printf '%X' 地址) % 200" | bc   # 结果应为0
#
# 3. 版本区间：
#    - 新条目 MIN_VER 必须 > 旧条目 MAX_VER
#    - 通过脚本自动检查：test ${NEW_MIN} -gt ${OLD_MAX}
##############################################################################

# ================== 复制文件列表 勿修改 =====================
FILES_TO_COPY=("Image" "initrd" "qpkg" "rootfs_ext" "rootfs2" "ts642.dtb") # 需复制的内核文件
DTB_FILE="ts642.dtb"                    # 默认设备树文件

qnap-tools/PC1
来源
qnap-tools/pc1.c
https://gist.github.com/galaxy4public/0420c7c9a8e3ff860c8d5dce430b2669#file-pc1-c

