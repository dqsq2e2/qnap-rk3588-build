#!/bin/bash
set -eo pipefail

# ==================== 初始化配置 ====================
# 版本信息
VERSION="V1.0"
# 颜色定义
GREEN='\033[1;32m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
RED='\033[31m'
YELLOW='\033[33m'
NC='\033[0m'
declare -g -A KERNEL_VERSIONS

# ==================== 配置加载 ======================
config_check() {
    local file_path=$1
    [[ -f "${file_path}" ]] || {
        echo -e "${RED}错误：缺少配置文件 ${file_path}${NC}"
        exit 1
    }

    if file "${file_path}" | grep -q CRLF; then
        echo -e "${YELLOW}检测到Windows换行符，3秒内按任意键取消转换...${NC}"
        if read -t 3 -n 1; then
            echo -e "\n${YELLOW}转换已取消${NC}"
            exit 1
        else
            sed -i 's/\r$//' "${file_path}"
        fi
    fi
}

# # ==================== 配置加载 ======================
safe_source_config() {
    [[ -f "${CONFIG_FILE}" ]] || {
        echo -e "${RED}错误：配置文件缺失 ${CONFIG_FILE}${NC}"
        exit 1
    }
    
    # 先加载主配置
    source "${CONFIG_FILE}" || {
        echo -e "${RED}配置文件语法错误 ${CONFIG_FILE}${NC}"
        exit 1
    }

    local board_config="${SRC}/boards/${BOARD_NAME}/custom.conf"
    [[ -f "${board_config}" ]] || {
        echo -e "${RED}错误：板级配置文件缺失 ${board_config}${NC}"
        exit 1
    }

    # 再加载板级配置
    source "${board_config}" || {
        echo -e "${RED}板级配置文件语法错误 ${board_config}${NC}"
        exit 1
    }

    # 关键修复点：将连续的&&判断改为独立判断
    [[ -z "${UBOOT_CONFIG}" ]] && {
        echo -e "${RED}配置错误：UBOOT_CONFIG 未在板级配置中定义${NC}"
        exit 1
    }

    [[ -z "${DTS_FILES}" ]] && {
        echo -e "${RED}配置错误：DTS_FILES 未在板级配置中定义${NC}"
        exit 1
    }

    if [[ ${#KERNEL_VERSIONS[@]} -eq 0 ]]; then
        echo -e "${RED}配置错误：KERNEL_VERSIONS 未定义或格式错误${NC}"
        exit 1
    fi
}

# ==================== 命令行参数 ====================
parse_arguments() {
    case "$1" in
        --init)
            # 初始化模式仅解析board参数
            for arg in "$@"; do
                [[ "$arg" == board=* ]] && BOARD_NAME="${arg#*=}"
            done
            return 0
            ;;
        *)
            # 原完整参数解析逻辑
            for arg in "$@"; do
                case "${arg}" in
					board=*)      BOARD_NAME="${arg#*=}" ;;
					firmware=*)   QNAP_FIRMWARE_FILE="${arg#*=}" ;;
					kernel_boot_mode=*) KERNEL_BOOT_MODE="${arg#*=}" ;;
					uboot=*)      UBOOT_MODE="${arg#*=}" ;;
					clean=*)      CLEAN_MODE="${arg#*=}" ;;
					dtb=*)        DTB_MODE="${arg#*=}" ;;
					kernel=*)    KERNEL_MODE="${arg#*=}" ;;
					table=*)     TABLE_MODE="${arg#*=}" ;;
					-h|--help)    show_usage; exit 0 ;;
					*)
						echo -e "${RED}错误：未知参数 ${arg}${NC}"
						show_usage
						exit 1
						;;
                esac
            done
            ;;
    esac
}

# ==================== 命令行参数 ====================

show_usage() {
    echo -e "\n${CYAN}QNAP构建脚本 ${VERSION}${NC}"
    echo -e "${GREEN}当前值见 ${CONFIG_FILE}${NC}"
    echo -e "可用参数："
    echo -e "  ${GREEN}board=<板型名称>${NC}			设置目标板型				（当前值：${BOARD_NAME} ）"
    echo -e "  ${GREEN}firmware=<固件文件名>${NC}			指定QNAP固件				（当前值：${QNAP_FIRMWARE_FILE} ）"
	echo -e "  ${GREEN}kernel_boot_mode=<模式>${NC}		内核启动模式（qnap/custom）		（当前值：${KERNEL_BOOT_MODE} ）"
    echo -e "  ${GREEN}uboot=<模式>${NC}				U-Boot编译模式（auto/force/only）	（当前值：${UBOOT_MODE} ）"
    echo -e "  ${GREEN}dtb=<模式>${NC}				DTB编译模式（auto/force/only）		（当前值：${DTB_MODE} ）"
	echo -e "  ${GREEN}kernel=<模式>${NC}				内核编译模式（auto/force/only/unused）	（当前值：${KERNEL_MODE} ）"
	echo -e "  ${GREEN}clean=<模式>${NC}				清除模式（board/all）			 board: 清除当前boards/${BOARD_NAME}/build-out目录, all: build-ou清除,重置固件目录,内核源码目录以及uboot源码目录"
    echo -e "  ${GREEN}-h|--help${NC}				显示帮助信息"

	echo -e "\n${CYAN}示例：${NC}"

    echo -e "  ${GREEN}1. 使用 ${CONFIG_FILE}指定值 版型=${BOARD_NAME}; 初始固件=${QNAP_FIRMWARE_FILE}; 默认内核启动方式=原厂内核"${KERNEL_BOOT_MODE}"; uboot是否编译=${UBOOT_MODE}; dtb是否编译=${DTB_MODE}; 内核是否编译=${KERNEL_MODE}.${NC}"
    echo -e "    ./create_dom.sh"


    echo -e "\n  ${GREEN}2. 版型="orangepi_5_plus-emmc"; 初始固件="TS-X42_20241120-5.1.9.2954.zip"; 默认内核启动方式=自定义内核custom; 强制重新编译 \"uboot dtb kernel\" ${NC}"
    echo -e "    ./create_dom.sh board=orangepi_5_plus-emmc firmware=TS-X42_20241120-5.1.9.2954.zip \\"
    echo -e "        kernel_boot_mode=custom uboot=force dtb=force kernel=force"

    echo -e "\n  ${GREEN}3. 修改uboot源码后 版型使用${BOARD_NAME}; 重新编译${BOARD_NAME}的uboot 玩成后 \"idbloader.img uboot.img\" 复制到 ${SRC}/boards/${BOARD_NAME}; 退出. ${NC}"
    echo -e "    ./create_dom.sh uboot=only"

    echo -e "\n  ${GREEN}4. 修改dts 内核源码 后 版型使用orangepi_5_plus-sd; 默认内核启动方式=自定义内核custom; 强制重新编译dtb; 其余参数使用 ${CONFIG_FILE}值; 最后打包生成整个img/zip ${NC}"
    echo -e "    ./create_dom.sh kernel_boot_mode=custom dtb=force"

    echo -e "\n  ${GREEN}5. 修改任意 patch kernel dts uboot 代码后 先./create_dom.sh clean=board  再 ./create_dom.sh${NC}"
    echo -e "\n  ${GREEN}6. 修改 uboot 代码后 打包生成整个img/zip${NC}"
	echo -e "    ./create_dom.sh uboot=force"

    echo -e "\n  ${GREEN}7. 修改 kernel 代码后 打包生成整个img/zip${NC}"
	echo -e "    ./create_dom.sh kernel=force \n"

    echo -e "\n  ${GREEN}8. 修改 dts 代码后 打包生成整个img/zip${NC}"
	echo -e "    ./create_dom.sh dtb=force \n"

    echo -e "\n  ${GREEN}9. 修改 kernel uboot 代码后 回到初始化到原始状态 ${NC}"
	echo -e "    ./create_dom.sh clean=all \n"
}

cleanup() {
    local exit_code=$?
    local remain_mounts=() loop_devices=() remain_files=()

    # 卸载所有挂载点
    if [[ -d "${TMP_DIR}" ]]; then
        while IFS= read -r mountpoint; do
            umount -lf "$mountpoint" 2>/dev/null || remain_mounts+=("$mountpoint")
        done < <(find "${TMP_DIR}" -type d -exec mountpoint -q {} \; -print)
    fi

    # 释放所有循环设备
    while IFS= read -r dev; do
        losetup -d "$dev" 2>/dev/null || loop_devices+=("$dev")
    done < <(losetup -j "${QNAP_DOM_NAME}" 2>/dev/null | cut -d: -f1)

    # 清理临时目录
    if [[ -d "${TMP_DIR}" ]]; then
        rm -rf "${TMP_DIR}" 2>/dev/null || remain_files=("${TMP_DIR}")
        [[ ${#remain_files[@]} -gt 0 ]] && fuser -km "${TMP_DIR}" 2>/dev/null
        rm -rf "${TMP_DIR}" 2>/dev/null || remain_files=("${TMP_DIR}")
    fi

    # 错误报告
    {
        (( ${#remain_mounts[@]} > 0 )) && printf "挂载残留: %s\n" "${remain_mounts[@]}"
        (( ${#loop_devices[@]} > 0 )) && printf "设备未释放: %s\n" "${loop_devices[@]}"
        (( ${#remain_files[@]} > 0 )) && printf "目录残留: %s\n" "${remain_files[@]}"
    } | awk '{print "'${RED}'✗ " $0 "'${NC}'"}' >&2

    # 最终状态验证
    if [[ -d "${TMP_DIR}" ]]; then
        echo -e "${YELLOW}警告: 临时目录残留 → ${TMP_DIR}${NC}" >&2
    else
        echo -e "${GREEN}✅ 清理完成 (退出码: ${exit_code})${NC}" >&2
    fi
}
trap cleanup EXIT INT TERM

# ==================== 核心功能函数 ====================
check_board_type() {
    [[ "${BOARD_NAME}" =~ -(emmc|sd)$ ]] || {
        echo -e "${RED}错误：板型名称必须以 -emmc 或 -sd 结尾${NC}"
        exit 1
    }
    echo -e "\n${BLUE}[硬件配置]"
    echo -e "${GREEN}板型标识：			${YELLOW}${BOARD_NAME}"
    echo -e "${GREEN}存储类型：			${CYAN}${BASH_REMATCH[1]^^}${NC}"
    echo -e "${GREEN}固件版本：			${CYAN}${QNAP_FIRMWARE_FILE}${NC}"
    echo -e "${GREEN}KERNEL启动模式：		${CYAN}${KERNEL_BOOT_MODE}${NC}"
    echo -e "${GREEN}U-Boot编译模式：		${CYAN}${UBOOT_MODE}${NC}"
    echo -e "${GREEN}DTB编译模式：   		${CYAN}${DTB_MODE}${NC}"
    echo -e "${GREEN}KERNEL编译模式：		${CYAN}${KERNEL_MODE}${NC}"
    echo -e "${GREEN}输出镜像：			${CYAN}${QNAP_DOM_NAME}${NC}"
}

download_firmware() {
    local target_file="${SRC}/qnap-firmware/${QNAP_FIRMWARE_FILE}"
    local max_retries=3 timeout=30

    # 存在性检查与自动续传
    if [[ ! -f "${target_file}" ]]; then
        echo -e "${CYAN}▶ 下载固件 [${QNAP_FIRMWARE_FILE}]${NC}"
        if ! wget -qc -t ${max_retries} -T ${timeout} -P "${SRC}/qnap-firmware" \
             "${QNAP_FIRMWARE_URL}${QNAP_FIRMWARE_FILE}"; then
            echo -e "${RED}✗ 下载失败 (重试 ${max_retries} 次)${NC}" >&2
            return 1
        fi
    else
        echo -e "${GREEN}✓ 固件已缓存 [${QNAP_FIRMWARE_FILE##*/}]${NC}"
    fi

    # 完整性验证（基础校验）
    if ! file "${target_file}" | grep -q "Zip archive"; then
        echo -e "${RED}✗ 文件损坏或非ZIP格式${NC}" >&2
        rm -f "${target_file}"
        return 2
    fi
}

uncompress_firmware() {
    local boot_dir="${SRC}/qnap-firmware/${QNAP_FIRMWARE_NAME}-BOOT"
    local initrd_dir="${SRC}/qnap-firmware/${QNAP_FIRMWARE_NAME}-INITRD"

    if [[ -d "${boot_dir}" && -d "${initrd_dir}" ]]; then
        echo -e "${GREEN}✓ 固件已解压，已存在 ${boot_dir} ${initrd_dir} 跳过解压...${NC}"
        return 0
    fi

    echo -e "\n${CYAN}▶ 开始处理固件 [${YELLOW}${QNAP_FIRMWARE_FILE}${CYAN}] ◀${NC}"
    
    # 清理旧目录

    rm -rf "${boot_dir}" "${initrd_dir}"

    # 解压ZIP文件
    if ! unzip -q -o -d "${SRC}/qnap-firmware" "${SRC}/qnap-firmware/${QNAP_FIRMWARE_FILE}"; then
        echo -e "${RED}✗ ZIP文件解压失败！${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ ZIP解压完成 (输出目录: ${YELLOW}${SRC}/qnap-firmware${GREEN})${NC}"

    # 解码固件镜像
    if ! "${QNAP_PC1}" d QNAPNASVERSION4 \
        "${SRC}/qnap-firmware/${QNAP_FIRMWARE_NAME}.img" \
        "${SRC}/qnap-firmware/decoded_firmware.tar.gz"; then
        echo -e "${RED}✗ 固件解码失败！${NC}"
        exit 1
    fi

    # 解压BOOT分区
    mkdir -p "${boot_dir}"
    if ! tar -xf "${SRC}/qnap-firmware/decoded_firmware.tar.gz" -C "${boot_dir}" 2>/dev/null; then
        echo -e "${YELLOW}⚠ 警告：忽略,正常提示，继续处理...${NC}"
    fi
    echo -e "${GREEN}✓ BOOT分区解压完成 (目录: ${YELLOW}${boot_dir}${GREEN})${NC}"

    # 解压initrd
    mkdir -p "${initrd_dir}"
    if ! gunzip -c "${boot_dir}/initrd.boot" | (cd "${initrd_dir}" && cpio -idm 2>/dev/null); then
        echo -e "${RED}✗ initrd解压失败！${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ initrd解压完成 (目录: ${YELLOW}${initrd_dir}${GREEN})${NC}"

    # 清理临时文件
    echo -e "\n${CYAN}▷ 清理临时文件...${NC}"
    rm -rf "${SRC}/qnap-firmware/${QNAP_FIRMWARE_NAME}.img" \
           "${SRC}/qnap-firmware/decoded_firmware.tar.gz"
    echo -e "${GREEN}✓ 临时文件清理完成${NC}"
}

clone_git_repo() {
    local repo_url="$1"
    local branch="$2"
    local target_dir="$3"
    local retries=3
    local attempt=1
    local success=false

    # 参数有效性检查
    if [[ -z "$repo_url" || -z "$branch" || -z "$target_dir" ]]; then
        echo -e "${RED}✖ 参数错误: 必须提供仓库URL、分支名称和目标目录${NC}" >&2
        echo "用法: clone_git_repo <仓库URL> <分支> <目标目录>" >&2
        return 1
    fi

    # 目录存在性检查（幂等性设计）
    if [[ -d "$target_dir" ]]; then
        echo -e "${CYAN}ℹ 目录已存在: ${target_dir} 跳过克隆${NC}"
        return 0
    fi

    echo -e "${CYAN}▶ 开始克隆仓库 [分支: ${branch}] 到 ${target_dir}...${NC}"

    # 克隆重试循环
    while [[ $attempt -le $retries && $success == false ]]; do
        # 强制清理残留（防御性编程）
        rm -rf "$target_dir" 2>/dev/null

        echo -e "尝试 ${CYAN}${attempt}/${retries}${NC}: 正在克隆 ${CYAN}${repo_url}${NC}"

        # 执行克隆（显示进度）
        if git -c advice.detachedHead=false clone -b "$branch" "$repo_url" "$target_dir" --progress 2>&1; then
            success=true
            echo -e "${GREEN}✔ 成功克隆到: ${target_dir}${NC}"
            return 0
        else
            # 无论是否继续重试，立即清理残留
            rm -rf "$target_dir" 2>/dev/null

            # 错误处理
            if [[ $attempt -lt $retries ]]; then
                echo -e "${YELLOW}⚠️ 第${attempt}次失败，2秒后重试...${NC}"
                sleep 2
                ((attempt++))
            else
                echo -e "${RED}✖ 连续${retries}次克隆失败! 请检查:${NC}" >&2
                echo -e "  仓库URL有效性: curl -I ${repo_url%.git}" >&2
                echo -e "  分支是否存在: git ls-remote --heads ${repo_url} ${branch}" >&2
                echo -e "  目录权限: ls -ld $(dirname "$target_dir")" >&2
                return 1
            fi
        fi
    done
}

create_qnap_dom() {
    echo -e "\n${GREEN}[镜像构建]${NC}"
    local LOOP_DEV

    # # ==================== 加载配置文件参数 ====================
    # echo -e "${CYAN}▶ 加载磁盘元数据配置...${NC}"
    # source "${CONFIG_FILE}"  # 确保已通过 safe_source_config 加载

    # 动态加载关联数组
    declare -A PARTITION_METADATA=()
    eval "$(grep -A20 'PARTITION_METADATA=' ${CONFIG_FILE} | sed 's/declare -g -A/declare -A/')"
    declare -A PARTITION_LAYOUT=()
    eval "$(grep -A20 'PARTITION_LAYOUT=' ${CONFIG_FILE} | sed 's/declare -g -A/declare -A/')"

    # ==================== 参数校验 ====================
    [[ -z "${IMG_SECTORS}" ]] && { echo -e "${RED}错误：IMG_SECTORS 未定义${NC}"; exit 1; }
    [[ -z "${DISK_GUID}" ]] && { echo -e "${RED}错误：DISK_GUID 未定义${NC}"; exit 1; }
    [[ -z "${PARTITION_METADATA[*]}" ]] && { echo -e "${RED}错误：PARTITION_METADATA 未定义${NC}"; exit 1; }
    [[ -z "${PARTITION_LAYOUT[*]}" ]] && { echo -e "${RED}错误：PARTITION_LAYOUT 未定义${NC}"; exit 1; }

    declare -n PM_REF="PARTITION_METADATA"
    declare -n PL_REF="PARTITION_LAYOUT"

    # ==================== 创建基础镜像 ====================
    echo -e "${CYAN}▶ 初始化镜像文件 (${IMG_SECTORS} sectors)...${NC}"
    dd if=/dev/zero of="${QNAP_DOM_NAME}" bs=512 count=${IMG_SECTORS} status=progress || { echo "创建基础镜像失败"; exit 1; }
    sync

    # ==================== 动态构建分区命令 ====================
    echo -e "${CYAN}▶ 创建GPT分区表...${NC}"
    local parted_cmd="parted -s ${QNAP_DOM_NAME} mklabel gpt"
    for part in {1..7}; do
        if [[ -z "${PL_REF[$part]}" ]]; then
            echo -e "${RED}错误：分区 $part 布局未定义${NC}"
            exit 1
        fi

        if [[ $part -eq 1 ]]; then
            parted_cmd+=" mkpart uboot ${PL_REF[$part]}"
        else
            parted_cmd+=" mkpart primary ${PL_REF[$part]}"
        fi
    done
    eval "${parted_cmd}"

    # ==================== 设置磁盘标识 ====================
    LOOP_DEV=$(losetup --find --show --partscan "${QNAP_DOM_NAME}")
    echo -e "${CYAN}▶ 设置磁盘标识...${NC}"
    sgdisk --disk-guid "${DISK_GUID}" "${LOOP_DEV}"

    # ==================== 设置分区UUID ====================
    echo -e "${CYAN}▶ 设置分区标识符...${NC}"
    for part in {1..7}; do
        local partuuid=$(echo "${PARTITION_METADATA[$part]}" | grep -oE 'PARTUUID=[^ ]+' | cut -d= -f2)
        [[ -n "$partuuid" ]] && sgdisk --partition-guid=$part:"$partuuid" "${LOOP_DEV}"
    done

    # ==================== 刷新分区表 ====================
    partx -u "${LOOP_DEV}"
    sleep 2
    udevadm settle

    # ==================== 设备节点验证 ====================
    echo -e "${CYAN}▶ 验证设备节点...${NC}"
    for part in {1..7}; do
        dev_node="${LOOP_DEV}p${part}"
        [[ -b "$dev_node" ]] || {
            echo -e "${RED}错误：设备节点不存在 $dev_node${NC}"
            partprobe "$LOOP_DEV"
            udevadm trigger
            sleep 3
            [[ -b "$dev_node" ]] || { echo -e "${RED}节点仍未就绪，退出！"; exit 1; }
        }
    done

    # ==================== 格式化文件系统 ====================
    echo -e "${CYAN}▶ 格式化文件系统...${NC}"
    for part in 2 3 5 6; do
        local uuid=$(echo "${PARTITION_METADATA[$part]}" | tr ' ' '\n' | awk -F= '/^UUID=/{print $2; exit}')
        local dev_node="${LOOP_DEV}p${part}"

        case $part in
            2|3)
                local label="QTS_BOOT_PART${part}"
                mkfs.ext2 -b 1024 -F -q \
                    -U "${uuid}" \
                    -L "${label}" \
                    "${dev_node}"
                ;;
            5|6)
                mkfs.ext2 -b 1024 -F -q \
                    -U "${uuid}" \
                    "${dev_node}"
                ;;
        esac
    done

    # ==================== 文件复制 ====================
    safe_mount() {
        local part_num=$1
        local mount_point="${TMP_DIR}/dom-disk${part_num}"
        mkdir -p "$mount_point"
        mount "${LOOP_DEV}p${part_num}" "$mount_point" || exit 1
        echo "$mount_point"
    }

    echo -e "${CYAN}▶ 填充启动数据...${NC}"
    for part_num in 2 3; do
        mount_point=$(safe_mount $part_num)
        dest_dir="${mount_point}/boot"
        mkdir -p "${dest_dir}"

        find "${SRC}/qnap-firmware/${QNAP_FIRMWARE_NAME}-BOOT" -maxdepth 1 -type f \
            -regextype posix-extended \
            -regex ".*/($(IFS=\|; echo "${FILES_TO_COPY[*]}")).*" \
            -exec cp -- "{}" "${dest_dir}/" \;

        umount "$mount_point" && rm -rf "$mount_point"
    done
}


compile_uboot() {
    local start_time=$(date +%s)
    echo -e "\n${CYAN}==== 执行U-Boot编译流程 ====${NC}"

    # 编译模式检测
    local uboot_flag_file1="${BOARD_DIR}/build-out/idbloader.img"
    local uboot_flag_file2="${BOARD_DIR}/build-out/uboot.img"
    case "${UBOOT_MODE}" in
        "auto")
            if [[ -f "${uboot_flag_file1}" && -f "${uboot_flag_file2}" ]]; then
                echo -e "${GREEN}✔ [跳过] 使用预编译U-Boot文件${NC}"
                return 0
            fi
            ;;
        "force")
            rm -f "${uboot_flag_file1}" "${uboot_flag_file2}"
            echo -e "${YELLOW}⚠ 强制重新编译U-Boot${NC}"
            ;;
        "only") ;;
        *)
            echo -e "${RED}✖ 错误编译模式: ${UBOOT_MODE}${NC}"
            exit 1
            ;;
    esac

    # 直接使用本地存在的源码目录
    UBOOT_SRC_DIR="u-boot/u-boot-qnap"
    RKBIN_SRC_DIR="u-boot/rkbin"
    PREBUILTS_SRC_DIR="u-boot/prebuilts"

    local patch_dir="${BOARD_DIR}/uboot-patch"
    if [[ -d "${patch_dir}" ]]; then
        echo -e "${CYAN}▶ 处理U-Boot补丁 (共 $(ls "${patch_dir}"/*.patch 2>/dev/null | wc -l) 个)${NC}"

        (
            # 确保进入U-Boot源码目录
            cd "${UBOOT_SRC_DIR}" || { echo -e "${RED}无法进入U-Boot目录${NC}"; exit 1; }

            # 按版本排序应用补丁
            for patch in $(ls "${patch_dir}"/*.patch 2>/dev/null | sort -V); do
                echo -e "应用补丁: ${YELLOW}$(basename "${patch}")${NC}"

                # 在u-boot-qnap目录执行补丁检查
                if ! patch --dry-run -p0 -N -s < "${patch}" &>/dev/null; then
                    echo -e "${YELLOW}⚠ 补丁已存在或冲突，跳过: ${patch}${NC}"
                    continue
                fi

                # 实际应用
                if patch -p0 -N < "${patch}"; then
                    echo -e "${GREEN}✓ 补丁应用成功${NC}"
                else
                    echo -e "${RED}✗ 补丁应用失败! 错误码: $?${NC}"
                    exit 1
                fi
            done
        ) || exit 1
    fi

    # ================== 配置修改 ==================
    local target_value=0
    [[ "${BOARD_NAME}" == *"-sd" ]] && target_value=1

    # 配置文件定义（使用绝对路径）
    local config_files=(
        "${UBOOT_SRC_DIR}/include/configs/evb_rk3588.h"
        "${UBOOT_SRC_DIR}/cmd/qnap_boot.h"
    )

    # 备份配置文件
    echo -e "${CYAN}▶ 备份原始配置...${NC}"
    for cf in "${config_files[@]}"; do
        if [[ -f "${cf}" && ! -f "${cf}.orig" ]]; then
            cp -v "${cf}" "${cf}.orig" || {
                echo -e "${RED}✖ 配置文件备份失败: ${cf}${NC}"
                exit 1
            }
        fi
    done

    # 动态修改配置
    echo -e "${CYAN}▶ 应用板级配置修改...${NC}"

    # 修改evb_rk3588.h
    sed -i -E \
        "s/^(#define CONFIG_SYS_MMC_ENV_DEV\s+)[0-9]+/\1$((target_value ? 1 : 0))/" \
        "${config_files[0]}" || {
        echo -e "${RED}✖ 配置修改失败: ${config_files[0]}${NC}"
        exit 1
    }

    # 修改qnap_boot.h
    sed -i -E \
        -e "s/(#define QNAP_BOOT_DEV\s+)[0-9]+/\1${target_value}/" \
        -e "s/(#define QNAP_KERNEL_TYPE\s+\")[^\"]*/\1${KERNEL_BOOT_MODE}/" \
        -e "s/(#define QNAP_KERNEL_VERSION\s+)[0-9]+/\1${QNAP_VER:-100}/" \
        "${config_files[1]}" || {
        echo -e "${RED}✖ 配置修改失败: ${config_files[1]}${NC}"
        exit 1
    }
	
    # 确定配置名称
    #local uboot_config="${UBOOT_CONFIG:-${BOARD_NAME%-*}}"
    local defconfig_path="${UBOOT_SRC_DIR}/configs/${UBOOT_CONFIG}_defconfig"
    # 关键验证（在源码就绪后检查）
    if [[ ! -f "${defconfig_path}" ]]; then
        echo -e "${RED}错误：U-Boot配置文件不存在于源码中！${NC}"
        echo -e "请检查以下路径：\n  ${YELLOW}${defconfig_path}${NC}"
        echo -e "或确认 custom.conf 中的 UBOOT_CONFIG 变量是否正确"
        exit 1
    fi

	echo -e "${CYAN}▶ 使用配置：${UBOOT_CONFIG}_defconfig${NC}"
    # ================== 编译执行 ==================
    (
        echo -e "${CYAN}▶ 进入编译目录: ${UBOOT_SRC_DIR}${NC}"
        cd "${UBOOT_SRC_DIR}" || {
            echo -e "${RED}✖ 无法进入U-Boot目录${NC}"
            exit 1
        }

        # 清理并编译
        echo -e "${CYAN}▶ 执行编译命令 (板级配置: ${BOARD_NAME%-*})...${NC}"
        {
            make clean			
            time ./make.sh "${UBOOT_CONFIG}"
        } > build.log 2>&1 || {
            echo -e "${RED}✖ UBOOT编译失败! 查看日志: ${UBOOT_SRC_DIR}/build.log${NC}"
            exit 1
        }

		echo -e "${GREEN}✔ UBOOT编译成功！查看详细日志: ${UBOOT_SRC_DIR}/build.log${NC}"

        # 部署文件
        echo -e "${CYAN}▶ 部署编译产出...${NC}"
        mkdir -p "${BOARD_DIR}/build-out"
        cp -v idbloader.img uboot.img "${BOARD_DIR}/build-out/" || {
            echo -e "${RED}✖ 文件部署失败${NC}"
            exit 1
        }
    ) || exit 1 # 子shell错误传递

    # 耗时统计
    local duration=$(( $(date +%s) - start_time ))
    echo -e "${GREEN}✔ UBOOT编译流程完成，总耗时: ${duration} 秒${NC}"
}

write_uboot_images() {
    local board_dir="${SRC}/boards/${BOARD_NAME}"
    local idbloader="${board_dir}/build-out/idbloader.img"
    local uboot_img="${board_dir}/build-out/uboot.img"

    [[ ! -f "${idbloader}" ]] && { echo "缺失文件：${idbloader}"; exit 1; }
    [[ ! -f "${uboot_img}" ]] && { echo "缺失文件：${uboot_img}"; exit 1; }

    echo -e "\n${GREEN}#写入U-Boot镜像...${NC}"
    echo -e "文件路径: ${YELLOW}${idbloader} 偏移扇区: 0x40${NC}"
    if ! dd if="${idbloader}" of="${QNAP_DOM_NAME}" bs=512 seek=64 conv=notrunc status=progress; then
        echo -e "${RED}✗ idbloader 写入失败！${NC}"
        exit 1
    fi

    echo -e "文件路径: ${YELLOW}${uboot_img} 偏移扇区: 0x8000 ${NC}"
    if ! dd if="${uboot_img}" of="${QNAP_DOM_NAME}" bs=512 seek=32768 conv=notrunc status=progress; then
        echo -e "${RED}✗ uboot.img 写入失败！${NC}"
        exit 1
    fi
}

prepare_env() {
    echo -e "\n${GREEN} 准备编译环境${NC}"
    local kernel_root="${SRC}/qnap-kernel"

    if [[ ! -d "${kernel_root}" ]]; then
        mkdir -p "${kernel_root}"
    fi

    # ==================== 交叉工具链处理 ====================
    local toolchain_file="${kernel_root}/cross_toolchain.tar.gz"
    local toolchain_dir="${kernel_root}/aarch64-QNAP-linux-gnu"

    if [[ ! -d "${toolchain_dir}" ]]; then
        echo -e "${CYAN}▶ 下载交叉编译工具链...${NC}"
        if ! wget -q -t 3 -T 30 --show-progress -O "${toolchain_file}" "${COMPILE_DOWNURL}"; then
            echo -e "${RED}错误：工具链下载失败！${NC}"
            exit 1
        fi

        echo -e "${CYAN}▶ 解压工具链...${NC}"
        if ! tar zxf "${toolchain_file}" -C "${kernel_root}"; then
            echo -e "${RED}错误：工具链解压失败！${NC}"
            exit 1
        fi
        #rm -f "${toolchain_file}"
    fi

    # ==================== 全局环境变量设置 ====================
    export PATH="${toolchain_dir}/bin:$PATH"
    export CROSS_COMPILE="aarch64-QNAP-linux-gnu-"
    export ARCH="arm64"

    # ==================== 多版本内核处理 ====================
    echo -e "${CYAN}▶ 需要处理的内核版本：${!KERNEL_VERSIONS[@]}${NC}"

    # 按版本号排序处理（5.1.0优先）
    for version in $(printf "%s\n" "${!KERNEL_VERSIONS[@]}" | sort -V); do
        echo -e "\n${BLUE}▍ 开始处理 ${version} 内核 ▍${NC}"

        # ==================== 配置加载修复 ====================
        declare -A cfg
        eval "cfg=${KERNEL_VERSIONS[$version]}" 2>/dev/null || {
            echo -e "${RED}配置解析失败：版本$version 格式错误${NC}"
            exit 1
        } 

        # ==================== 动态路径配置 ====================
        local dir="GPL_QTS-${version}"
        local output_dir="${kernel_root}/${dir}"
        local base_name="qnap_kernel_${version//./_}"

        # ==================== 分卷下载修复 ====================
        local parts=${cfg[parts]}
        echo -e "${CYAN}▶ 处理分卷（共${parts}个）...${NC}"

        local parts_files=()
        for ((i=0; i<parts; i++)); do
            local part_var="part${i}"
            local md5_var="part${i}_md5"
            local part_url="${cfg[$part_var]}"
            local part_file="${kernel_root}/${base_name}_part${i}"
            local expected_md5="${cfg[$md5_var]}"
            local expected_size=$(curl -sI "$part_url" | awk '/Content-Length/ {print $2}' | tr -d '\r')

            # 存在性检查与校验
            if [[ -f "$part_file" ]]; then
                # 计算实际MD5
                actual_md5=$(md5sum "$part_file" | cut -d' ' -f1)
                if [[ "$actual_md5" != "$expected_md5" ]]; then
                    echo -e "${YELLOW}▶ MD5不匹配: ${part_file##*/} (${actual_md5:0:8}...)→删除重下${NC}"
                    rm -f "$part_file"
                else
                    echo -e "${GREEN}✓ 分卷 ${i} 已存在且校验通过${NC}"
                    parts_files+=("${part_file}")
                    continue
                fi
            fi

            # 断点续传下载（最多重试3次）
            for retry in {1..3}; do
                echo -e "下载分卷 ${i} (尝试 ${retry}/3): ${part_url}"
                #if wget -c -q -t 3 -T 30 --show-progress -O "${part_file}" "${part_url}"; then
                if wget -c -q -t 3 -T 30 --show-progress -O "${part_file}" "${part_url}"; then				
                    # 下载后校验
                    actual_md5=$(md5sum "$part_file" | cut -d' ' -f1)
                    if [[ "$actual_md5" == "$expected_md5" ]]; then
                        parts_files+=("${part_file}")
                        break
                    else
                        echo -e "${RED}✗ MD5校验失败: ${actual_md5} (预期:${expected_md5})${NC}"
                        rm -f "$part_file"
                    fi
                fi
                # 最终重试失败处理
                (( retry == 3 )) && { 
                    echo -e "${RED}分卷 ${i} 下载失败！退出码: $?${NC}"
                    exit 1
                }
            done
        done

        # ==================== 解压处理修复 ====================
        if [[ -d "${output_dir}" ]]; then
            echo -e "${GREEN}✓ 版本目录已存在：${dir}${NC}"
            continue  # 跳过当前循环剩余步骤，处理下一个版本
        fi

		echo -e "${CYAN}▶ 解压到 ${dir}...${NC}"
		if ! cat "${parts_files[@]}" | tar -${cfg[tar_opts]}x -C "${kernel_root}"; then
			echo -e "${RED}解压失败！可能原因：${NC}"
			echo "1. 分卷文件不完整（尝试删除重试）"
			echo "2. tar参数错误（当前使用：-${cfg[tar_opts]}x）"
			exit 1
		fi

		# 目录重命名修复
		if [[ -d "${kernel_root}/GPL_QTS" ]]; then
			mv -v "${kernel_root}/GPL_QTS" "${output_dir}"
		elif [[ -d "${kernel_root}/${cfg[dir]}" ]]; then
			mv -v "${kernel_root}/${cfg[dir]}" "${output_dir}"
		else
			echo -e "${RED}错误：解压后未找到内核目录！${NC}"
			echo "当前目录内容："
			ls -l "${kernel_root}"
			exit 1
		fi
		echo -e "${GREEN}✓ 已创建版本目录：${dir}${NC}"

        # ==================== 内核配置修复 ====================
        local kernel_cfg_src="${output_dir}/kernel_cfg/TS-X42/linux-5.10-arm64.config"
        local kernel_cfg_dest="${output_dir}/src/linux-5.10/.config"
        local kernel_src_dir="${output_dir}/src/linux-5.10"

        echo -e "${CYAN}▶ 进入内核源码目录: ${kernel_src_dir}${NC}"
        cd "${kernel_src_dir}" || exit 1
        # 初始化Git仓库（幂等操作）
        if [[ ! -d .git ]]; then
            git init -q -b main . >/dev/null
            git config --local user.name "R-mt"
            git config --local user.email "wxzmz@163.com"
            git add . >/dev/null
            git commit -m "Initial pristine source" >/dev/null
            git tag original-state
            echo -e "${GREEN}✓ Git仓库初始化完成${NC}"
        fi

        # 清理旧编译
        (
            cd "${kernel_src_dir}" || exit 1
            echo -e "${CYAN}▷ 清理原始编译环境...${NC}"
            make distclean >/dev/null 2>&1
        ) || exit 1

        if [[ -f "${kernel_cfg_src}" ]]; then
            echo -e "${CYAN}▶ 应用内核配置...${NC}"
            cp -vf "${kernel_cfg_src}" "${kernel_cfg_dest}"
            touch "${output_dir}/src/linux-5.10/include/config.h"
			#使用git的必须生成.scmversion否则内核版本后面有+
			touch .scmversion
            git add -f .config .scmversion include/config.h
            git commit -m "Apply kernel config" >/dev/null
            git tag original-cfg-state
			echo -e "${GREEN}✓ Git仓库内核配置完成${NC}"
            echo -e "${GREEN}✓ 内核配置完成${NC}"
        else
            echo -e "${YELLOW}⚠ 警告：配置文件缺失 ${kernel_cfg_src}${NC}"
        fi

    done

    echo -e "\n${GREEN}[完成] 所有内核环境准备就绪${NC}"
}

compile_dtb() {
    # ==================== 初始化配置 ====================
    echo -e "\n${GREEN}▶ DTB 设备树编译${NC}"
    local kernel_root="${SRC}/qnap-kernel"
    local warnings=()
    local need_compile=0
    local missing_dtbs=()

    # ==================== 模式预处理 ====================
    case "${DTB_MODE}" in
        "auto")
            echo -e "${CYAN}▶ AUTO模式：检测DTB文件${NC}"
            # 检测所有DTB是否存在
            for ver in $(printf "%s\n" "${!KERNEL_VERSIONS[@]}" | sort -V); do
                local dtb_file="${BOARD_DIR}/build-out/${BOARD_NAME}_qnap-${ver}.dtb"
                if [[ ! -f "${dtb_file}" ]]; then
                    missing_dtbs+=("${dtb_file}")
                    echo -e "${YELLOW}➤ 缺失DTB文件：${dtb_file}${NC}"
                else
                    echo -e "${GREEN}✓ 已存在：${dtb_file}${NC}"
                fi
            done
            
            # 全量存在时直接退出
            if (( ${#missing_dtbs[@]} == 0 )); then
                echo -e "${GREEN}✓ 所有DTB文件已存在，跳过编译流程${NC}"
                return 0
            fi
            need_compile=1
            ;;
            
        "force")
            echo -e "${YELLOW}▶ FORCE模式：强制重新编译所有DTB${NC}"
            need_compile=1
            ;;
            
        "only") # 仅保留模式标识，退出逻辑交给主流程
            echo -e "${CYAN}▶ ONLY模式：准备环境并编译DTB${NC}"
            prepare_env || {
                echo -e "${RED}错误：环境准备失败！${NC}"
                exit 1
            }
            need_compile=1
            ;;
            
        *)
            echo -e "${RED}错误：未知DTB模式 [${DTB_MODE}]${NC}"
            exit 1
            ;;
    esac

    # ==================== 环境准备 ====================
    if [[ ${need_compile} -eq 1 && "${DTB_MODE}" != "only" ]]; then
        echo -e "${CYAN}▶ 准备编译环境...${NC}"
        prepare_env || {
            echo -e "${RED}错误：环境准备失败！${NC}"
            exit 1
        }
    fi

    # ==================== 多版本编译 ====================
    for version in $(printf "%s\n" "${!KERNEL_VERSIONS[@]}" | sort -V); do
        # 动态路径配置
        local dir="GPL_QTS-${version}"
        local kernel_src_dir="${kernel_root}/${dir}/src/linux-5.10"
        local dtb_output="${BOARD_DIR}/build-out/${BOARD_NAME}_qnap-${version}.dtb"
        local board_dts_dir="${SRC}/boards/dts-files"

        # ==================== 严格目录检查 ====================
        if [[ ! -d "${board_dts_dir}" ]]; then
            echo -e "${RED}错误：DTS目录不存在 ${board_dts_dir}${NC}"
            exit 1
        fi

        # ==================== 编译前检查 ====================
        if [[ "${DTB_MODE}" == "force" ]]; then
            echo -e "${YELLOW}➤ 强制删除旧DTB文件：$(basename "${dtb_output}")${NC}"
            rm -f "${dtb_output}"
        fi

        if [[ "${DTB_MODE}" == "auto" && -f "${dtb_output}" ]]; then
            echo -e "${GREEN}✓ 跳过已存在的：$(basename "${dtb_output}")${NC}"
            continue
        fi

        # ==================== 编译流程 ====================
        echo -e "\n${BLUE}▍ 开始编译 ${version} DTB ▍${NC}"
        
        # 1. 内核源码验证
        if [[ ! -d "${kernel_src_dir}" ]]; then
            echo -e "${RED}错误：内核目录不存在 ${kernel_src_dir}${NC}"
            exit 1
        fi

        # 2. 清理旧文件
        local kernel_dts_dir="${kernel_src_dir}/arch/arm64/boot/dts/rockchip"
        echo -e "${CYAN}▶ 清理旧编译产物...${NC}"
        find "${kernel_dts_dir}" -maxdepth 1 -type f \( -name "*.dtb" -o -name "*.tmp" \) -delete

        # 3. 复制DTS文件
        echo -e "${CYAN}▶ 复制DTS/DTSI文件...${NC}"
        if [[ -d "${board_dts_dir}" ]]; then
            find "${board_dts_dir}" -type f \( -name "*.dts" -o -name "*.dtsi" \) \
                -exec echo -e "复制: ${YELLOW}{}${NC} → ${YELLOW}${kernel_dts_dir}${NC}" \; \
                -exec cp -v {} "${kernel_dts_dir}" \; || {
                echo -e "${RED}错误：文件复制失败！退出码: $?${NC}";
                exit 1;
            }
        else
            echo -e "${RED}错误：DTS目录不存在 ${board_dts_dir}${NC}"
            exit 1
        fi

        # ==================== 新增补丁处理步骤 ====================
        local patch_dir="${SRC}/qnap-kernel-config/kernel-patchs-${version}"
        # 修复数组引用方式（移除eval）
        local DTB_PATCH_FILES=(${DTB_PATCH_SET[$version]})
        echo "Valid patches for $version: ${DTB_PATCH_FILES[@]} in ${patch_dir}"
        
        if [[ -d "${patch_dir}" && ${#DTB_PATCH_FILES[@]} -gt 0 ]]; then
            echo -e "${CYAN}▶ 处理DTB补丁 (共 ${#DTB_PATCH_FILES[@]} 个)${NC}"
            
            (
                cd "${kernel_src_dir}" || exit 1
                for patch_name in ${DTB_PATCH_FILES}; do
                    patch="${patch_dir}/${patch_name}"
                    if [[ -f "${patch}" ]]; then
                        echo -e "应用补丁: ${YELLOW}${patch_name}${NC}"
                        
                        if ! patch --dry-run -p1 -N -s < "${patch}" &>/dev/null; then
                            echo -e "${YELLOW}⚠ 补丁已存在或冲突，跳过: ${patch_name}${NC}"
                            continue
                        fi

                        if patch -p1 -N < "${patch}"; then
                            echo -e "${GREEN}✓ 补丁应用成功${NC}"
                        else
                            echo -e "${RED}✗ 补丁应用失败! 错误码: $?${NC}"
                            exit 1
                        fi
                    else
                        echo -e "${YELLOW}⚠ 补丁文件缺失: ${patch_name}${NC}"
                    fi
                done
            ) || exit 1
        fi
		

        # 4. 创建版本化符号链接
        local main_dts="${DTS_FILES}.dts"
        if [[ -f "${kernel_dts_dir}/${main_dts}" ]]; then
            echo -e "${CYAN}▶ 创建版本符号链接...${NC}"
            ln -sfv "${main_dts}" "${kernel_dts_dir}/${BOARD_NAME}_qnap-${version}.dts"
        else
            echo -e "${RED}错误：主DTS文件缺失 ${main_dts}${NC}"
            exit 1
        fi

        # 5. 更新dts Makefile配置
        local makefile_path="${kernel_dts_dir}/Makefile"
        local makefile_entry="dtb-\$(CONFIG_ARCH_ROCKCHIP) += ${BOARD_NAME}_qnap-${version}.dtb"
        
        echo -e "${CYAN}▶ 更新Makefile配置...${NC}"
        if ! grep -q "^${makefile_entry}$" "${makefile_path}"; then
            echo "${makefile_entry}" >> "${makefile_path}"
            echo -e "添加: ${YELLOW}${makefile_entry}${NC}"
        else
            echo -e "${GREEN}✓ Makefile条目已存在${NC}"
        fi

        # 6. 执行编译
        echo -e "${CYAN}▶ 开始编译DTB...${NC}"
        # # 5. 执行编译
        (
            cd "${kernel_src_dir}" || exit 1
            echo -e "${CYAN}▷ 清理编译环境...${NC}"
            #make clean >/dev/null 2>&1
            
            echo -e "${CYAN}▷ 加载内核配置...${NC}"
            if ! make olddefconfig </dev/null >config.log 2>&1; then
                echo -e "${RED}错误：内核配置失败！查看 config.log 获取详情${NC}"
                exit 1
            fi
            
            echo -e "${CYAN}▷ 编译设备树 (使用 $(nproc) 线程)...${NC}"
            if ! make dtbs -j$(nproc) CC="ccache ${CROSS_COMPILE}gcc" >dtb_compile.log 2>&1; then
                echo -e "${RED}错误：DTB编译失败！查看 ${kernel_src_dir}/dtb_compile.log 获取详情${NC}"
                exit 1
            fi

        ) || exit 1

        # 7. 输出处理
        mkdir -p "${BOARD_DIR}/build-out"
        add_kread "${kernel_dts_dir}/${BOARD_NAME}_qnap-${version}.dtb" "${dtb_output}" || exit 1

        # 8. 编译后校验
        if [[ -s "${dtb_output}" ]]; then
            echo -e "${GREEN}✓ 编译成功: $(basename "${dtb_output}") [$(du -h "${dtb_output}" | cut -f1)]${NC}"
        else
            echo -e "${RED}错误：输出文件为空！${NC}"
            exit 1
        fi
    done

    # ==================== 最终检查 ====================
    echo -e "\n${GREEN}✅ 所有DTB编译完成${NC}"
    echo -e "输出目录: ${YELLOW}${BOARD_DIR}/build-out/${NC}"
}

compile_kernel() {
    echo -e "\n${GREEN}▶ KERNEL 内核编译${NC}"
    local kernel_root="${SRC}/qnap-kernel"
    local need_compile=0
    local missing_images=()

    # ==================== 模式预处理 ====================
    case "${KERNEL_MODE}" in
        "unused")
            echo -e "${GREEN}✔ [跳过] 内核编译模式设置为未使用${NC}"
            return 0
            ;;
        "only")
            echo -e "${YELLOW}▶ 仅内核编译模式${NC}"
            prepare_env
            need_compile=1
            ;;
        "auto")
            echo -e "${CYAN}▶ AUTO模式: 检测内核文件...${NC}"
            # 检查所有内核文件和模块目录
            for version in $(printf "%s\n" "${!KERNEL_VERSIONS[@]}" | sort -V); do
                local kernel_image="${BOARD_DIR}/build-out/Image-${version}"
                local modules_dir="${BOARD_DIR}/build-out/modules-${version}"  # 新增模块目录检查
                
                # 双条件校验（内核文件 + 模块目录）
                if [[ ! -f "${kernel_image}" || ! -d "${modules_dir}" ]]; then
                    missing_images+=("${kernel_image}")
                    echo -e "${YELLOW}➤ 缺失文件或目录:"
                    [[ ! -f "${kernel_image}" ]] && echo "  - 内核文件: ${kernel_image##*/}"
                    [[ ! -d "${modules_dir}" ]] && echo "  - 模块目录: ${modules_dir##*/}"
                    echo -e "${NC}"
                else
                    echo -e "${GREEN}✓ 已存在: ${kernel_image##*/} + ${modules_dir##*/}${NC}"
                fi
            done

            # 所有文件存在时直接返回
            if (( ${#missing_images[@]} == 0 )); then
                echo -e "${GREEN}✔ 所有内核文件已存在，跳过编译流程${NC}"
                return 0
            fi
            need_compile=1
            ;;
        "force")
            echo -e "${YELLOW}▶ 强制重新编译所有内核${NC}"
            need_compile=1
            ;;
        *)
            echo -e "${RED}错误：未知内核模式 [${KERNEL_MODE}]${NC}"
            exit 1
            ;;
    esac

    # ==================== 环境准备 ====================
    if [[ ${need_compile} -eq 1 && "${KERNEL_MODE}" != "only" ]]; then
        prepare_env || {
            echo -e "${RED}错误：环境准备失败！${NC}"
            exit 1
        }
    fi

	export PATH="${toolchain_dir}/bin:$PATH"
	export CROSS_COMPILE="aarch64-QNAP-linux-gnu-"
	export ARCH="arm64"
	export QNAP_NFS_QLOG=yes

    # ==================== 多版本编译 ====================
    for version in $(printf "%s\n" "${!KERNEL_VERSIONS[@]}" | sort -V); do
        # 动态路径配置
        #local conf_file="${BOARD_DIR}/kernel-build-${version}/kernel-build.conf"
        local kernel_image="${BOARD_DIR}/build-out/Image-${version}"
		local modules_dir="${BOARD_DIR}/build-out/modules-${version}"
		
        # # 跳过不存在的配置文件
        # [[ ! -f "${conf_file}" ]] && {
            # echo -e "${YELLOW}⚠ 跳过未配置版本: ${version} (缺失 ${conf_file})${NC}"
            # continue
        # }

        # 自动模式存在检查
        if [[ "${KERNEL_MODE}" == "auto" && -f "${kernel_image}" && -d "${modules_dir}" ]]; then
            echo -e "${GREEN}✓ 跳过已存在的: $(basename "${kernel_image}") + ${modules_dir##*/}${NC}"
            continue
        fi

        # 强制模式清理旧文件
        [[ "${KERNEL_MODE}" == "force" ]] && rm -f "${kernel_image}"

        # ==================== 编译准备 ====================
        echo -e "\n${BLUE}▍ 开始编译 ${version} 内核 ▍${NC}"

        # # 加载内核配置
        # config_check "${conf_file}"
        # source "${conf_file}" || {
            # echo -e "${RED}错误：加载配置文件失败 ${conf_file}${NC}"
            # exit 1
        # }

        # 内核源码路径
        local kernel_dir="GPL_QTS-${version}"
        local kernel_src_dir="${kernel_root}/${kernel_dir}/src/linux-5.10"

        # 源码目录验证
        [[ ! -d "${kernel_src_dir}" ]] && {
            echo -e "${RED}错误：内核目录不存在 ${kernel_src_dir}${NC}"
            exit 1
        }

        # ==================== 内核配置修复 ====================
        local kernel_cfg_src="${kernel_root}/${kernel_dir}/kernel_cfg/TS-X42/linux-5.10-arm64.config"
		local kernel_custom_cfg_src="${BOARD_DIR}/kernel-build-${version}/${BOARD_NAME}.config"
        local kernel_cfg_dest="${kernel_root}/${kernel_dir}/src/linux-5.10/.config"


        # ==================== 编译执行 ====================
        (
            echo -e "${CYAN}▶ 进入编译目录: ${kernel_src_dir}${NC}"
            cd "${kernel_src_dir}" || exit 1
			
        # ==================== 修正补丁处理 ====================
        local patch_dir="${SRC}/qnap-kernel-config/kernel-patchs-${version}"
        # 使用KERNEL_PATCH_SET代替PATCH_FILES
        local KERNEL_PATCH_FILES=(${KERNEL_PATCH_SET[$version]})
        echo "Valid kernel patches for $version: ${KERNEL_PATCH_FILES[@]} in ${patch_dir}"

        if [[ -d "${patch_dir}" && ${#KERNEL_PATCH_FILES[@]} -gt 0 ]]; then
            echo -e "${CYAN}▶ 处理内核补丁 (共 ${#KERNEL_PATCH_FILES[@]} 个)${NC}"
            
            (
                cd "${kernel_src_dir}" || exit 1
                for patch_name in "${KERNEL_PATCH_FILES[@]}"; do
                    patch="${patch_dir}/${patch_name}"
					if [[ -f "${patch}" ]]; then
						echo -e "应用补丁: ${YELLOW}${patch_name}${NC}"
						
						# 预检查补丁
						if ! patch --dry-run -p1 -N -s < "${patch}" &>/dev/null; then
							echo -e "${YELLOW}⚠ 补丁已存在或冲突，跳过: ${patch_name}${NC}"
							continue
						fi
			
						# 实际应用
						if patch -p1 -N < "${patch}"; then
							echo -e "${GREEN}✓ 补丁应用成功${NC}"
						else
							echo -e "${RED}✗ 补丁应用失败! 错误码: $?${NC}"
							exit 1
						fi
					else
						echo -e "${YELLOW}⚠ 补丁文件缺失: ${patch_name}${NC}"
					fi
				done
            ) || exit 1
        fi			

        # 清理并配置
        echo -e "${CYAN}▶ 重置内核版本标识...${NC}"
        > .version
        
        echo -e "${CYAN}▶ 加载内核配置...${NC}"
        #使用boards/board/kernel-build-version/kernel-build.conf中的kernel_config_manager的函数 设定特定内核参数
        #kernel_config_manager .config
        
        if [[ -f "${kernel_custom_cfg_src}" ]]; then
        	echo -e "${CYAN}▶ 应用自定义内核配置...${NC}"
        	cp -vf "${kernel_custom_cfg_src}" "${kernel_cfg_dest}"
        	echo -e "${GREEN}✓ 自定义内核配置完成${NC}"
        else
        	echo -e "${CYAN}▶ 应用custom.conf内核配置...${NC}"
        	cp -vf "${kernel_cfg_src}" "${kernel_cfg_dest}"
        	kernel_config_manager ${version} .config
        fi
        
        touch "include/config.h"
        make olddefconfig >/dev/null 2>&1
        
        # 强制模式时删除旧模块目录
        if [[ "${KERNEL_MODE}" =~ only|force ]] && [[ -d "${modules_dir}" ]]; then
            echo -e "${YELLOW}▶ 清理旧模块目录: ${modules_dir}${NC}"
            rm -rf "${modules_dir}"
        fi
        
        # 确保目录存在（自动创建）
        mkdir -p "${modules_dir}"        
	
        # 执行编译
        echo -e "${CYAN}▶ 开始编译内核 (使用 $(nproc) 线程)...${NC}"
        {
            time make -j$(nproc) \
                CFLAGS_KERNEL="${KERNEL_CFLAGS[$version]}" \
                CFLAGS_MODULE="${MODULE_CFLAGS[$version]}" \
                Image modules 2>&1 | tee "kernel_compile-${version}.log"
        } 
        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
            echo -e "${RED}错误：内核编译失败！查看日志: ${kernel_src_dir}/kernel_compile-${version}.log${NC}"
            exit 1
        fi

        # 模块安装并记录详细日志
        {
            time make INSTALL_MOD_PATH="${modules_dir}" modules_install 2>&1 | tee "modules_install-${version}.log"
        }
        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
            echo -e "${RED}✗ 模块安装失败！查看日志: ${kernel_src_dir}/modules_install-${version}.log${NC}"
            exit 1
        fi

        # 生成完整日志文件（包含实时输出和时间统计）
        {
            echo "==== 内核编译日志 ===="
            cat "kernel_compile-${version}.log"
            echo -e "\n\n==== 模块安装日志 ===="
            cat "modules_install-${version}.log"
            echo -e "\n\n==== 时间统计 ===="
            grep real *.log
        } > "full_build_log-${version}.log"		
        
        echo -e "${GREEN}✔ kernel-${version}编译成功！查看详细日志: ${kernel_src_dir}/kernel_compile-${version}.log${NC}"
        
        mkdir -p "${BOARD_DIR}/build-out"
        add_kread "arch/arm64/boot/Image" "${kernel_image}" || exit 1

        ) || exit 1
    done

    echo -e "\n${BLUE}✅ 所有内核编译完成${NC}"
    echo -e "输出目录: ${YELLOW}${BOARD_DIR}/build-out/${NC}"
    ls -lh "${BOARD_DIR}/build-out"/Image-* 2>/dev/null || {
        echo -e "${YELLOW}⚠ 未找到任何内核文件${NC}"
    }

    echo -e "\n${BLUE}✅ 所有模块编译安装完成：${NC}"
	echo -e "输出目录: ${YELLOW}${BOARD_DIR}/build-out/${NC}"
    for version in "${!KERNEL_VERSIONS[@]}"; do
        ls -ld "${BOARD_DIR}/build-out/modules-${version}" 2>/dev/null || 
        echo -e "${YELLOW}⚠ 缺失模块目录: modules-${version}${NC}"
    done
}

# ==================== 新增函数 add_kread ====================
add_kread() {
    # 参数校验增强
    [[ $# -ne 2 ]] && {
        echo -e "${RED}Usage: add_kread <input> <output>${NC}" >&2
        return 1
    }
    #mkdir -p "${TMP_DIR}"

    local input="$1"
    local output="$2"
    local header_temp="${TMP_DIR}/.header.bin"

    # 输入文件校验
    [[ -s "$input" ]] || {
        echo -e "${RED}错误：输入文件为空或不存在 [$input]${NC}" >&2
        return 2
    }

    # 校验magic配置
    if [[ -z "${MAGIC}" ]]; then
        echo -e "${RED}配置错误：MAGIC 未在 qnap_build.conf 中定义${NC}" >&2
        return 3
    fi

    if (( ${#MAGIC} != 4 )); then
        echo -e "${RED}配置错误：MAGIC 必须为4个ASCII字符 (当前长度 ${#MAGIC})${NC}" >&2
        return 4
    fi

    # 获取文件大小
    local file_size
    if ! file_size=$(stat -c%s "$input" 2>/dev/null); then  # <-- 行1080
        echo -e "${RED}无法获取文件大小: $input${NC}" >&2
        return 3
    fi

    # 生成文件头
    echo -e "${CYAN}生成KREAD头: ${input##*/} → ${output##*/} (数据大小: ${file_size} 字节)${NC}"

    # 生成二进制头文件
    {
        printf "%s" "$MAGIC"
        printf "%08x" "$file_size" | xxd -r -p
        dd if=/dev/zero bs=504 count=1 status=none
    } > "$header_temp" || {
        echo -e "${RED}文件头生成失败${NC}" >&2
        return 4
    }

    # 合并文件
    if ! (cat "$header_temp" "$input" | pv -s $((file_size + 512)) > "$output"); then
        echo -e "${RED}文件合并失败${NC}" >&2
        return 5
    fi

    # 校验文件大小
    local actual_size=$(stat -c%s "$output")
    local expected_size=$((file_size + 512))
    if [[ "$actual_size" -ne "$expected_size" ]]; then
        echo -e "${RED}校验失败！实际:${actual_size} 预期:${expected_size}${NC}" >&2
        return 6
    fi

    return 0
}

write_dtb_and_patch() {
    local board_dir="${SRC}/boards/${BOARD_NAME}"
    local warnings=()
    
    # =====================================================================
    # 多版本DTB写入处理
    # =====================================================================
    echo -e "\n${GREEN}▌ 写入多版本DTB文件 ▐${NC}"

    for version in $(printf "%s\n" "${!KERNEL_VERSIONS[@]}" | sort -V); do
        declare -A cfg
        eval "cfg=${KERNEL_VERSIONS[$version]}" 2>/dev/null || {
            echo -e "${RED}配置解析失败：版本$version 格式错误${NC}"
            exit 1
        }

        # 验证必须参数
        if [[ -z "${cfg[dtb_offset]:-}" ]]; then
            echo -e "${RED}错误：${version} 未定义dtb_offset${NC}"
            exit 1
        fi
		
        local dtb_file="${BOARD_DIR}/build-out/${BOARD_NAME}_qnap-${version}.dtb"
        local offset_hex=$(printf "%X" ${cfg[dtb_offset]})
        local offset_dec=${cfg[dtb_offset]}	
        
        # 三级文件验证
        if [[ -f "${dtb_file}" ]]; then
            echo -e "${CYAN}▶ 文件路径: ${dtb_file}${version} DTB 偏移: [0x${offset_hex}] ◀${NC}"

            echo -e "${BLUE}▷ 擦除 偏移: 0x${offset_hex}区域 (4096KB)...${NC}"
            dd if=/dev/zero of="${QNAP_DOM_NAME}" bs=512 seek=${offset_dec} count=8192 conv=notrunc status=none

            if ! dd if="${dtb_file}" of="${QNAP_DOM_NAME}" bs=512 seek=${offset_dec} conv=notrunc status=progress; then
                warnings+=("${version} DTB写入失败")
                echo -e "${RED}错误：${version} DTB写入异常！${NC}"
                continue
            fi

            echo -e "${GREEN}✓ ${version} DTB写入完成${NC}"

        else
            warnings+=("未找到${version} DTB文件")
            echo -e "${YELLOW}⚠ 警告：${dtb_file} 文件缺失${NC}"
        fi
    done

    # =====================================================================
    # 补丁文件处理
    # =====================================================================
    echo -e "\n${GREEN}▌ 写入补丁文件 ▐${NC}"
    local patch_dir="${board_dir}/patch"
    if [[ -d "${patch_dir}" ]]; then
        echo -e "${CYAN}▶ 打包补丁文件...${NC}"
		mkdir -p "${BOARD_DIR}/build-out"
        local patch_tgz="${board_dir}/build-out/${BOARD_NAME}_patch.tgz"

		(cd "${board_dir}" && tar zcf "${BOARD_NAME}_patch.tgz"  "./patch"  2>/dev/null)  #切勿修改
		mv "${board_dir}/${BOARD_NAME}_patch.tgz" "${patch_tgz}"

        if [[ -f "${patch_tgz}" ]]; then
            echo -e "${BLUE}▷ 写入补丁文件 ${patch_tgz} 到0x231800...${NC}"
            local patch_offset=$((0x231800))
            
            # 擦除目标区域
            dd if=/dev/zero of="${QNAP_DOM_NAME}" bs=512 seek=${patch_offset} count=65536 conv=notrunc status=none || { echo "擦除失败"; exit 1; }
            
            # 写入补丁
            dd if="${patch_tgz}" of="${QNAP_DOM_NAME}" bs=512 seek=${patch_offset} conv=notrunc status=progress || { echo "补丁写入失败"; exit 1; }
            #rm -f "${patch_tgz}"
            
            echo -e "${GREEN}✓ 补丁写入完成${NC}"
        else
            warnings+=("补丁打包失败")
            echo -e "${RED}错误：补丁文件生成失败！${NC}"
        fi
    else
        warnings+=("补丁目录缺失")
        echo -e "${YELLOW}⚠ 警告：${patch_dir} 目录不存在${NC}"
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo -e "\n${YELLOW}编译警告汇总：${NC}"
        printf "  • %s\n" "${warnings[@]}"
        printf "%s\n" "${warnings[@]}" > "${TMP_DIR}/build_warnings"
    fi
}

write_custom_kernel() {
    echo -e "\n${GREEN}▌ 写入自定义内核文件 ▐${NC}"
	
    # 设备存在性检查
    if [[ ! -f "${QNAP_DOM_NAME}" ]]; then
        echo -e "${RED}错误：存储设备 ${QNAP_DOM_NAME} 未找到${NC}"
        exit 1
    fi	

    for version in $(printf "%s\n" "${!KERNEL_VERSIONS[@]}" | sort -V); do
        # 多路径查找内核文件
        local kernel_file="Image-${version}"
        local search_paths=(
            "${BOARD_DIR}/build-out/${kernel_file}"
            "${tools_dir}/${kernel_file}"
        )
        
        # 查找存在的内核文件
        local kernel_path=""
        for path in "${search_paths[@]}"; do
            if [[ -f "${path}" ]]; then
                kernel_path="${path}"
                break
            fi
        done

        if [[ -z "${kernel_path}" ]]; then
            warnings+=("${kernel_file} 文件缺失")
            echo -e "${YELLOW}⚠ 警告：未找到内核文件 ${kernel_file}，跳过处理${NC}"
            continue
        fi

        # 加载版本配置
        declare -A cfg
        eval "cfg=${KERNEL_VERSIONS[$version]}" 2>/dev/null || {
            echo -e "${RED}配置解析失败：版本$version 格式错误${NC}"
            exit 1
        }		

        # 参数校验
        if [[ -z "${cfg[kernel_offset]}" || -z "${cfg[sectors]}" ]]; then
            echo -e "${RED}错误：${version} 缺少关键配置参数${NC}"
            exit 1
        fi

        local offset=${cfg[kernel_offset]}
        local offset_hex=$(printf "%X" ${cfg[kernel_offset]})
        local total_sectors=${cfg[sectors]}

        echo -e "${CYAN}▶ 处理 ${BOARD_DIR}/build-out/${kernel_file} (偏移: 0x${offset_hex} 扇区) ◀${NC}"

        # 安全擦除目标区域
        echo -e "${BLUE}▷ 擦除目标区域 (${total_sectors} sectors)...${NC}"
        dd if=/dev/zero of="${QNAP_DOM_NAME}" bs=512 seek=${offset} count=${total_sectors} \
           conv=notrunc status=progress 2>&1 || {
            echo -e "${RED}擦除操作失败${NC}"
            exit 1
        }

		if ! dd if="${kernel_path}" of="${QNAP_DOM_NAME}" bs=512 seek=${offset} conv=notrunc status=progress; then
			warnings+=("${version} KERNEL写入失败")
			echo -e "${RED}错误：${version} KERNEL写入异常！${NC}"
			continue
		fi
		echo -e "${GREEN}✓ ${kernel_file} KERNEL写入完成${NC}"

    done
}

create_write_table() {
    echo -e "\n${GREEN}▌ 生成/写入版本表 ▐${NC}"
    local version_table_file="${BOARD_DIR}/build-out/version_table.bin"

    local ver_dec=$((10#$QNAP_VER))

    # ==================== 转换函数 ====================
	be16() { # 大端序转换（用于版本号） 对应be16_to_cpu
		local val=$(($1))
		printf "\x$(printf "%02x" $(( (val >> 8) & 0xFF )))"
		printf "\x$(printf "%02x" $(( val & 0xFF )))"
	}

	be32() { # 大端序转换（用于 kernel_offset 和 dtb_offset）  对应be32_to_cpu
		local val=$(($1))
		printf "\x$(printf "%02x" $(( (val >> 24) & 0xFF )))"
		printf "\x$(printf "%02x" $(( (val >> 16) & 0xFF )))"
		printf "\x$(printf "%02x" $(( (val >> 8) & 0xFF )))"
		printf "\x$(printf "%02x" $(( val & 0xFF )))"
	}

	: > "${version_table_file}"

    {
        # ==================== 头部结构 ====================
        printf "%s" "$MAGIC"  		   # 与 add_kread 保持一致
        printf "\xa1\x1d\x02\x00"      # CRC32 (保留值)
        be16 "${ver_dec}"			   # 动态版本号


        # 条目数处理（大端序）
        local entry_count=${#KERNEL_VERSIONS[@]}
        printf "\x$(printf "%02x" $(( (entry_count >> 8) & 0xFF )))"  # 高位字节
        printf "\x$(printf "%02x" $(( entry_count & 0xFF )))"         # 低位字节
        printf "\x00\x00\x00\x00"      # 保留字段

        # ==================== 条目生成 ====================
        for ver in $(printf "%s\n" "${!KERNEL_VERSIONS[@]}" | sort -n); do
            declare -A entry
            eval "entry=${KERNEL_VERSIONS[$ver]}"

            # 生成条目数据（16字节）
            be16 "${entry[MIN_VER]}"    # MIN_VER（2字节大端序）
            be16 "${entry[MAX_VER]}"    # MAX_VER（2字节大端序）
            be32 "$((${entry[kernel_offset]}))"  # kernel_offset（4字节大端序）
            be32 "$((${entry[dtb_offset]}))"     # dtb_offset（4字节大端序）
            printf "\x00\x00\x00\x00"           # 保留字段（4字节）
        done

        # 512字节对齐填充
        local current_size=$(stat -c%s "$version_table_file")
        (( pad_size = (512 - (current_size % 512)) % 512 ))
        dd if=/dev/zero bs=$pad_size count=1 status=none || { echo "table 创建失败"; exit 1; }
    } > "${version_table_file}"

    # ==================== 写入镜像 ====================
    if [[ -f "${QNAP_DOM_NAME}" ]]; then
		echo -e "${CYAN}▶ 写入版本表到${QNAP_DOM_NAME} ${TABLE_OFFSET} 0x$(printf "%X" ${TABLE_OFFSET})扇区...${NC}"
		dd if="${version_table_file}" of="${QNAP_DOM_NAME}" \
			bs=512 seek=${TABLE_OFFSET} conv=notrunc status=progress || { echo "table 写入失败"; exit 1; }
	else
		echo -e "${YELLOW}▶ 生成 版本表${version_table_file} 未写入母盘 0x$(printf "%X" ${TABLE_OFFSET})扇区 ${NC}"
		echo -e "${YELLOW}▶ 使用以下命令写入eMMC dd if=version_table.bin of=/dev/mmcblk0 bs=512 seek=$((0x219000)) ${NC}"
    fi

    echo -e "${GREEN}✓ 版本表写入完成 (条目数: ${#KERNEL_VERSIONS[@]})${NC}"
}

create_update() {
	echo -e "${GREEN}正在构建更新包...${NC}"
    local build_out="${BOARD_DIR}/build-out"
    local output_img="${build_out}/${BOARD_NAME}-${QNAP_VER}-update.sh"
    local extract_dir="/share/Public/tmp-update"

    # 动态生成文件列表和版本信息
    local -a file_list=("idbloader.img" "uboot.img" "version_table.bin" "${BOARD_NAME}_patch.tgz")
    local -A version_map

    # 遍历所有内核版本生成对应条目
    for ver in "${!KERNEL_VERSIONS[@]}"; do
        eval "declare -A cfg=${KERNEL_VERSIONS[$ver]}"

        # 添加内核文件条目
        file_list+=("Image-${ver}")
        file_list+=("${BOARD_NAME}_qnap-${ver}.dtb")

        # 存储版本对应的偏移量（直接使用十进制扇区数）
        version_map["KERNEL_${ver}"]=${cfg[kernel_offset]}
        version_map["DTB_${ver}"]=${cfg[dtb_offset]}
    done

    # 生成自解压脚本
    {
        cat <<-EOF
		#!/bin/bash
		set -eo pipefail
		echo -e "\n\033[32m${BOARD_NAME}固件更新脚本\033[0m"
		echo -e "${CYAN}▶ 临时文件目录: \${target_dir} ◀${NC}"
		ARCHIVE=\$(awk '/^__ARCHIVE_BELOW__/ {print NR + 1; exit 0;}' "\$0")
		target_dir="${extract_dir}"

		cleanup() {
		    rm -rf "\${target_dir}"
		    exit \$1
		}

		# 创建临时目录
		rm -rf "\${target_dir}"
		mkdir -p "\${target_dir}" || {
		    echo -e "\033[31m无法创建临时目录\033[0m"
		    exit 1
		}

		# 解压文件
		echo -e "\033[33m解压文件中...\033[0m"
		tail -n+\$ARCHIVE "\$0" | tar xz -C "\${target_dir}" || {
		    echo -e "\033[31m解压失败！可能原因：\033[0m"
		    echo "1. 存储空间不足"
		    echo "2. 下载文件损坏"
		    cleanup 1
		}

		# 验证文件完整性
		for file in ${file_list[@]}; do
		    if [[ ! -f "\${target_dir}/\${file}" ]]; then
		        echo -e "\033[31m缺失关键文件: \${file}\033[0m"
		        cleanup 1
		    fi
		done

		# 获取存储设备路径
		DISK_DEV=\$(/sbin/hal_app --get_boot_pd port_id=0) || {
		    echo -e "\033[31m未找到存储设备!\033[0m"
		    cleanup 1
		}

		# 擦除旧分区数据
		echo -e "\n\033[33m▷ 开始写入数据到\${DISK_DEV} ◁\033[0m"
		EOF

        # 动态生成dd命令（保持固定count值）
        for ver in "${!KERNEL_VERSIONS[@]}"; do
            cat <<-EOF
			# 处理 ${ver} 内核
			echo -e "${CYAN}▷ 写入 Image-${ver}...${NC}"
			dd if=/dev/zero of=\${DISK_DEV} bs=512 seek=${version_map["KERNEL_${ver}"]} count=204800 conv=notrunc 2>>/dev/null
			dd if="\${target_dir}/Image-${ver}" of=\${DISK_DEV} bs=512 seek=${version_map["KERNEL_${ver}"]} conv=notrunc 2>>/dev/null

			# 处理 ${ver} DTB
			echo -e "${CYAN}▷ 写入 ${BOARD_NAME}_qnap-${ver}.dtb...${NC}"
			dd if=/dev/zero of=\${DISK_DEV} bs=512 seek=${version_map["DTB_${ver}"]} count=8192 conv=notrunc 2>>/dev/null
			dd if="\${target_dir}/${BOARD_NAME}_qnap-${ver}.dtb" of=\${DISK_DEV} bs=512 seek=${version_map["DTB_${ver}"]} conv=notrunc 2>>/dev/null
			EOF
        done

        # 公共分区处理
        cat <<-EOF
		# 写入补丁分区
		echo -e "${CYAN}▷ 写入补丁文件...${NC}"
		dd if=/dev/zero of=\${DISK_DEV} bs=512 seek=${PATCH_OFFSET} count=65536 conv=notrunc 2>>/dev/null
		dd if="\${target_dir}/${BOARD_NAME}_patch.tgz" of=\${DISK_DEV} bs=512 seek=${PATCH_OFFSET} conv=notrunc 2>>/dev/null

		# 写入版本表
		dd if="\${target_dir}/version_table.bin" of=\${DISK_DEV} bs=512 seek=${TABLE_OFFSET} conv=notrunc 2>>/dev/null
		# 写入uboot
		echo -e "${CYAN}▷ 写入UBOOT...${NC}"
		dd if="\${target_dir}/idbloader.img" of=\${DISK_DEV} bs=512 seek=64 conv=notrunc 2>>/dev/null
		dd if="\${target_dir}/uboot.img" of=\${DISK_DEV} bs=512 seek=32768 conv=notrunc 2>>/dev/null
		# 清除原有环境变量
		#dd if=/dev/zero of=\${DISK_DEV} bs=512 seek=8128 count=64 conv=notrunc 2>>/dev/null

		echo -e "\n${GREEN}✅ 写入完成！请重启设备${NC}"
		cleanup 0
		__ARCHIVE_BELOW__
		EOF
    } > "${output_img}"

    # 打包文件
    (
        cd "${build_out}"
        tar cz "${file_list[@]}" >> "${output_img}"
    )

    # # 添加必须的空行
    echo "" >> "${output_img}"

    chmod +x "${output_img}"
    echo -e "\n${GREEN}生成自解压镜像: ${output_img}${NC}"
}

compress_image() {
    echo -e "\n${GREEN}压缩最终镜像...${NC}"
    local img_base="${QNAP_DOM_NAME%.*}"
    local current_date=$(date +%Y%m%d)  # 获取当前日期
	declare -g qnap_dom_zip="${img_base}-${QNAP_VER}-${current_date}.zip"

    if [[ -f "${img_base}.img" ]]; then
        # 在文件名中添加日期
        zip -q -j "${qnap_dom_zip}" "${img_base}.img" && {
            echo -e "压缩完成：${CYAN}${qnap_dom_zip}${NC}"
            rm -f "${img_base}.img"
        } || {
            echo -e "${YELLOW}压缩失败，保留原始镜像文件${NC}"
        }
    fi
}


handle_only_mode() {
    if [[ "$UBOOT_MODE" == "only" ]]; then
        echo -e "\n${RED}▶ uboot Only模式：仅编译uboot 并复制至${BOARD_DIR}/build-out ${NC}"
        compile_uboot
        exit 0
    elif [[ "$DTB_MODE" == "only" ]]; then
        echo -e "\n${RED}▶ dtb Only模式：仅编译dtb 并复制至${BOARD_DIR}/build-out ${NC}"
        compile_dtb
        exit 0
    elif [[ "$KERNEL_MODE" == "only" ]]; then
        echo -e "\n${RED}▶ 内核 Only模式：仅编译内核 并复制至${BOARD_DIR}/build-out ${NC}"
        compile_kernel
        exit 0
    elif [[ "$TABLE_MODE" == "only" ]]; then
        echo -e "\n${RED}▶ table Only模式：仅生成version_table.bin 并复制至${BOARD_DIR}/build-out ${NC}"
        create_write_table
        exit 0
    fi
}

create_data_image() {
    local build_out="${BOARD_DIR}/build-out"
    local data_img="${build_out}/${BOARD_NAME}-data.img"
    local -i BASE_OFFSET="$TABLE_OFFSET"  # 基准偏移常量

    # ==================== 动态配置解析 ====================
    declare -A dtb_entries
    declare -A kernel_entries

    for version in $(printf "%s\n" "${!KERNEL_VERSIONS[@]}" | sort -V); do
        # 解析嵌套的关联数组
        eval "declare -A cfg=${KERNEL_VERSIONS[$version]}"

        # 提取关键偏移参数
        local -i dtb_offset=$(( ${cfg[dtb_offset]} ))
        local -i kernel_offset=$(( ${cfg[kernel_offset]} ))
        local -i sectors=$(( ${cfg[sectors]} ))

        # 计算新偏移量
        local -i new_dtb_offset=$(( dtb_offset - BASE_OFFSET ))
        local -i new_kernel_offset=$(( kernel_offset - BASE_OFFSET ))

        dtb_entries["$version"]="${new_dtb_offset}:${BOARD_NAME}_qnap-${version}.dtb"
        kernel_entries["$version"]="${new_kernel_offset}:${sectors}:Image-${version}"
    done

    # ==================== 镜像容量计算 ====================
    calculate_image_size() {
        local -i max_sector=0

        # 计算内核区域最大结束位置
        for version in "${!kernel_entries[@]}"; do
            IFS=':' read -r offset sectors _ <<< "${kernel_entries[$version]}"
            local -i end=$(( offset + sectors ))
            (( end > max_sector )) && max_sector=$end
        done

        # 计算补丁区域结束位置
        local -i patch_end=$(( (PATCH_OFFSET - BASE_OFFSET) + 0x40000 ))
        (( patch_end > max_sector )) && max_sector=$patch_end

        echo $(( max_sector + 0x1000 ))  # 4K对齐余量
    }

    safe_dd() {
        local src_file="$1"
        local dest_offset="$2"

        # 文件存在性校验
        [[ -f "$src_file" ]] || {
            echo -e "${RED}错误：缺失文件 ${src_file##*/}${NC}"
            return 1
        }

        # 计算实际需要的扇区数
        local -i required_sectors=$(( ($(stat -c%s "$src_file") + 511) / 512 ))

        echo -e "${CYAN}▶ 写入 ${src_file##*/} 到 0x$(printf '%x' $dest_offset)${NC}"
        dd if="$src_file" of="$data_img" bs=512 seek="$dest_offset" conv=notrunc status=progress || { echo "写入镜像失败"; exit 1; }
    }

    # ==================== 主流程 ====================
    echo -e "\n${BLUE}▌ 生成数据镜像 (基准偏移: 0x$(printf '%x' $BASE_OFFSET)) ▌${NC}"

    # 创建空白镜像
    local -i total_sectors=$(calculate_image_size)
    rm -f "$data_img"
    echo -e "总扇区数: ${YELLOW}${total_sectors}${NC} (约 $(( total_sectors * 512 / 1024 / 1024 )) MB)"
    dd if=/dev/zero of="$data_img" bs=512 count="$total_sectors" status=progress || { echo "创建空白镜像失败"; exit 1; }

    # 写入版本表 (新0扇区)
    safe_dd "${build_out}/version_table.bin" 0 || exit 1

    # 写入所有DTB
    for version in "${!dtb_entries[@]}"; do
        IFS=':' read -r offset file <<< "${dtb_entries[$version]}"
        safe_dd "${build_out}/${file}" "$offset" || exit 1
    done

    # 写入补丁文件
    safe_dd "${build_out}/${BOARD_NAME}_patch.tgz" $(( PATCH_OFFSET - BASE_OFFSET )) || exit 1

    # 写入所有内核
    for version in "${!kernel_entries[@]}"; do
        IFS=':' read -r offset sectors file <<< "${kernel_entries[$version]}"
        safe_dd "${build_out}/${file}" "$offset" || exit 1
    done

    # 验证镜像结构
    echo -e "\n${GREEN}✅ 镜像生成完成，结构验证：${NC}"
    for version in $(printf "%s\n" "${!KERNEL_VERSIONS[@]}" | sort -V); do
        eval "declare -A cfg=${KERNEL_VERSIONS[$version]}"
        printf "版本 %-3s → DTB:0x%05x 内核:0x%05x (原0x%x)\n" \
               "$version" \
               $(( ${cfg[dtb_offset]} - BASE_OFFSET )) \
               $(( ${cfg[kernel_offset]} - BASE_OFFSET )) \
               ${cfg[kernel_offset]}
    done
    ls -lh "$data_img"
}

build_clean() {
    echo -e "\n${CYAN}▶ 执行清理操作 [模式: ${CLEAN_MODE}]${NC}"

    # 公共清理部分
    local board_out="${BOARD_DIR}/build-out"
    if [[ -d "${board_out}" ]]; then
        echo -e "${RED}删除板级输出目录: ${board_out}${NC}"
        rm -rfv "${board_out}"
    fi

    # 根据模式处理
    case "${CLEAN_MODE}" in
        all)
            # 清理内核源码目录
            # for ver in "${!KERNEL_VERSIONS[@]}"; do
                # local kernel_dir="${SRC}/qnap-kernel/GPL_QTS-${ver}"
                # if [[ -d "${kernel_dir}" ]]; then
                    # echo -e "${RED}删除内核目录: ${kernel_dir}${NC}"
                    # rm -rf "${kernel_dir}"
                # fi
            # done

            for ver in "${!KERNEL_VERSIONS[@]}"; do
                local kernel_dir="${SRC}/qnap-kernel/GPL_QTS-${ver}/src/linux-5.10"
                if [[ -d "${kernel_dir}" ]]; then
                    (
                        cd "${kernel_dir}"
                        echo -e "${BLUE}▷ 重置: ${kernel_dir}${NC}"
                        #git reset --hard original-state
                        git reset --hard original-cfg-state
                        git clean -fdxq
                    )
                fi
            done

            # 清理固件目录
            local firmware_name="${QNAP_FIRMWARE_FILE%.*}"
            local firmware_dirs=(
                "${SRC}/qnap-firmware/${firmware_name}-BOOT"
                "${SRC}/qnap-firmware/${firmware_name}-INITRD"
            )
            for dir in "${firmware_dirs[@]}"; do
                if [[ -d "${dir}" ]]; then
                    echo -e "${RED}删除固件目录: ${dir}${NC}"
                    rm -rf "${dir}"
                fi
            done

            # 重置u-boot仓库
            if [[ -d "${UBOOT_SRC_DIR}" ]]; then
                echo -e "${CYAN}清理u-boot构建产物...${NC}"
                (
                    cd "${UBOOT_SRC_DIR}"
                    make clean 2>/dev/null || true
                    rm -rfv build-* *.img *.dtb 2>/dev/null
                )
            fi

            if [[ -d ""${LOG_DIR}"" ]]; then
                echo -e "${CYAN}删除日志目录...${NC}"
                rm -rf "${dir}"
            fi

            ;;
        board)
            echo -e "${YELLOW}仅清理板级配置${NC}"
            ;;
    esac
}

validate_board_dirs() {
    echo -e "\n${BLUE}▌ 验证板级目录结构 ▐${NC}"
    local missing_dirs=()
    local board_dir="${SRC}/boards/${BOARD_NAME}"

    # 基础板级目录检查
    [[ -d "${board_dir}" ]] || {
        echo -e "${RED}错误：板级目录不存在 ${board_dir}${NC}"
        exit 1
    }
	
    [[ -d "${SRC}/boards/dts-files" ]] || {
        echo -e "${RED}错误：dts目录不存在 ${SRC}/boards/dts-files${NC}"
        exit 1
    }

    # ==================== 强制校验 patch 目录 ====================
    local required_common_dirs=(
        "${board_dir}/patch"  # 新增补丁目录校验
    )

    # 校验通用目录
    for dir in "${required_common_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            missing_dirs+=("$(basename "$dir")")
            echo -e "${RED}✗ 缺失通用目录: ${dir#${SRC}/}${NC}"
        else
            echo -e "${GREEN}✓ 通用目录存在: ${dir#${SRC}/}${NC}"
        fi
    done

    # # ==================== 校验版本相关目录 ====================
    # for ver in "${!KERNEL_VERSIONS[@]}"; do
        # local clean_ver="${ver//[^0-9]/}"
        # local required_ver_dirs=(
            # "${board_dir}/kernel-build-${clean_ver}"
        # )

        # # 校验版本目录
        # for dir in "${required_ver_dirs[@]}"; do
            # if [[ ! -d "$dir" ]]; then
                # missing_dirs+=("$(basename "$dir")")
                # echo -e "${RED}✗ 缺失版本目录: ${dir#${SRC}/} (v${clean_ver})${NC}"
            # else
                # echo -e "${GREEN}✓ 版本目录存在: ${dir#${SRC}/} (v${clean_ver})${NC}"
            # fi
        # done
    # done

    if (( ${#missing_dirs[@]} > 0 )); then
        echo -e "\n${RED}错误：板级目录结构不完整！${NC}"
        echo -e "缺失的必需目录："
        printf "  • %-16s %s\n" "类型" "目录名称"

        # 分类显示缺失目录
        for dir in "${missing_dirs[@]}"; do
            if [[ "$dir" == "patch" ]]; then
                printf "  • %-16s %s\n" "[通用]" "patch/"
            else
                local ver_info=$(echo "$dir" | grep -oE '[0-9]{3}$')
                printf "  • %-16s %s\n" "[内核v${ver_info}]" "$dir"
            fi
        done

        echo -e "\n修复建议："
        echo -e "  1. 检查 boards/${BOARD_NAME} 目录结构"
        echo -e "  2. 确认需要以下目录结构："
        echo -e "     - patch/             # 补丁目录（必须）"
        echo -e "     - dts-qnap-{ver}/    # 设备树目录"
        echo -e "     - kernel-build-{ver} # 内核构建配置"
        exit 1
    fi
}

check_dependencies() {
    echo -e "\n${BLUE}▌ 检查系统依赖项 ▐${NC}"

    # 检查软件包依赖（新增parted/wget/patch）
    local required_packages=(
        build-essential gcc make cmake libssl-dev flex bison
        libncurses-dev libelf-dev bc rsync kmod lzop
        gcc-aarch64-linux-gnu git device-tree-compiler u-boot-tools
        python2 ccache pv gdisk unzip gzip
        parted wget patch gawk udev cpio vim
    )

    # 检查缺失的包
    local missing_packages=()
    for pkg in "${required_packages[@]}"; do
        if ! dpkg -l "$pkg" &>/dev/null; then
            missing_packages+=("$pkg")
        fi
    done

    if [[ ${#missing_packages[@]} -ne 0 ]]; then
        echo -e "${YELLOW}以下软件包未安装，尝试自动安装...${NC}"
        echo -e "缺失的包：${missing_packages[*]}"

        if ! sudo apt-get update; then
            echo -e "${RED}错误：更新软件包列表失败${NC}" >&2
            exit 1
        fi

        if ! sudo apt-get install -y "${missing_packages[@]}"; then
            echo -e "${RED}错误：安装软件包失败，请手动安装以下包后重试：${missing_packages[*]}${NC}" >&2
            exit 1
        fi
        echo -e "${GREEN}所有必需的软件包已成功安装${NC}"
    else
        echo -e "${GREEN}所有依赖的软件包已安装${NC}"
    fi

    # 检查命令是否存在（新增partprobe/wget/patch）
    local required_commands=(
        sgdisk udevadm partx pv git make gcc
        losetup parted dd mkfs.ext2 mount umount
        unzip gunzip partprobe wget patch
    )

    local missing_commands=()
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_commands+=("$cmd")
        fi
    done

    if [[ ${#missing_commands[@]} -ne 0 ]]; then
        echo -e "${RED}错误：以下命令未找到，请检查系统配置：${missing_commands[*]}${NC}" >&2
        exit 1
    else
        echo -e "${GREEN}所有必需的命令可用${NC}"
    fi
}



init_environment() {
    # ==================== 基础路径初始化 ====================
    declare -g SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    declare -g CONFIG_FILE="${SRC}/boards/qnap_build.conf"

    # ==================== 全局变量显式声明（关键！） ====================
    declare -g BOARD_NAME QNAP_FIRMWARE_FILE KERNEL_BOOT_MODE
    declare -g UBOOT_MODE DTB_MODE KERNEL_MODE
    declare -g CLEAN_MODE  # 新增清理模式变量

    # ==================== 初始参数解析（仅提取 BOARD_NAME） ====================
    # 目的：提前获取 BOARD_NAME 用于定位板级配置目录
    parse_arguments --init "$@"

    # ==================== 加载全局默认配置 ====================
    config_check "${CONFIG_FILE}"
    safe_source_config  # 包含 source "${CONFIG_FILE}"

    # ==================== 完整参数解析（覆盖所有配置） ====================
    parse_arguments "$@"

    # ==================== 加载板级自定义配置 ====================
    # 注意：此时 BOARD_NAME 可能来自命令行参数或全局配置
    declare -g BOARD_DIR="${SRC}/boards/${BOARD_NAME}"
    if [[ -f "${BOARD_DIR}/custom.conf" ]]; then
        config_check "${BOARD_DIR}/custom.conf"
        source "${BOARD_DIR}/custom.conf"
    fi

    declare -g LOG_DIR="${SRC}/build_logs"
    declare -g LOG_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    declare -g BUILD_LOG="${LOG_DIR}/${BOARD_NAME}_${LOG_TIMESTAMP}.log"
    mkdir -p "${LOG_DIR}"
    : > "${BUILD_LOG}"

    declare -g QNAP_FIRMWARE_NAME="${QNAP_FIRMWARE_FILE%.*}"
    declare -g QNAP_VER=$(basename "${QNAP_FIRMWARE_FILE}" | grep -oP '\d+\.\d+\.\d+' | tr -d '.' | cut -c1-3)

    # ==================== 派生路径配置（依赖最终 BOARD_NAME） ====================
    declare -g BOARD_DIR="${SRC}/boards/${BOARD_NAME}"
    declare -g QNAP_DOM_NAME="${SRC}/${BOARD_NAME}.img"
    #declare -g TMP_DIR=$(mktemp -d -p "${SRC}")
	declare -g TMP_DIR="${SRC}/tmp"

    # ==================== 工具链路径 ====================
    declare -g QNAP_PC1="${SRC}/qnap-tools/PC1"
    declare -g UBOOT_SRC_DIR="${SRC}/u-boot/u-boot-qnap"
    declare -g RKBIN_SRC_DIR="${SRC}/u-boot/rkbin"
    declare -g PREBUILTS_SRC_DIR="${SRC}/u-boot/prebuilts/gcc/linux-x86/aarch64/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu/"
}



main() {
    echo -e "\n\033[1;44m QNAP镜像构建工具 ${VERSION} \033[0m"
    local start_time=$(date +%s)

    # 初始化必须第一个执行
    init_environment "$@"
    exec > >(tee -a "${BUILD_LOG}") 2>&1
    echo -e "\n\033[1;44m [${BOARD_NAME}] 构建日志 @ $(date +'%Y-%m-%d %H:%M:%S') \033[0m"
    echo -e "日志文件: ${BUILD_LOG}\n"

	check_dependencies
    validate_board_dirs
    check_board_type

    if [[ -n "${CLEAN_MODE}" ]]; then
        build_clean
        exit 0
    fi

    # 清理历史构建
    echo -e "\n${CYAN}▶ 清理旧构建文件...${NC}"
    rm -rf "${QNAP_DOM_NAME}" "${TMP_DIR}" 2>/dev/null
    mkdir -p "${TMP_DIR}" "${BOARD_DIR}/build-out"

    # 核心流程
    {
        handle_only_mode  # 优先处理Only模式
        download_firmware
        uncompress_firmware

        # 编译三部曲
        compile_uboot
        compile_kernel
        compile_dtb

        # 镜像操作（调整顺序）
        create_qnap_dom          # 创建分区结构
        write_uboot_images       # 写入uboot
        write_dtb_and_patch      # 写入DTB和补丁
        write_custom_kernel      # 写入内核
        create_write_table       # 最后写入版本表
        create_data_image        # 生成数据镜像

    }

    # 错误处理
    if (( PIPESTATUS[0] != 0 )); then
        echo -e "\n${RED}构建失败！查看日志:${BUILD_LOG}${NC}"
        exit 1
    fi

    # 后续处理
	create_update
    compress_image

    # 耗时统计
    local end_time=$(date +%s)
    echo -e "\n${GREEN}构建成功！耗时: $(date -d@$((end_time - start_time)) -u +%H:%M:%S)${NC}"
    echo -e "输出文件: ${BLUE}$(ls -lh ${qnap_dom_zip})${NC}"
}

main "$@"
