// SPDX-License-Identifier: GPL-2.0+
/*
 * QNAP Custom Boot Command for RK3588 (v2.0)
 */

#include <common.h>
#include <command.h>
#include <environment.h>
#include <fdt_support.h>
#include <vsprintf.h>
#include <linux/kernel.h>
#include "qnap_boot.h"
#define __STDC_FORMAT_MACROS
#include <inttypes.h>
#include <mmc.h>

#include <dm/uclass.h> 
#include <dm/device.h>    // 设备模型相关
#include <misc.h>          // misc_read/misc_write
#include <u-boot/crc.h>   // crc32_no_comp
#include <net.h>           // MAC地址处理
#include <linux/kernel.h>  // 字符串操作



#define VERSION_TABLE_SECTOR       0x219000
#define MAX_TABLE_ENTRIES          16
const struct qnap_storage_config qnap_cfg = QNAP_STORAGE_LAYOUT;

#pragma pack(push, 1)
struct version_table_header {
    __be32 magic;            // 大端32位 (使用内核定义的类型)
    __be32 crc32;
    __be16 header_version;   // 大端16位
    __be16 entry_count;    // 2字节 条目总数
    __be32 reserved;       // 4字节 保留字段
};

struct version_entry {       // 全部使用大端存储
    __be16 version_min;      // 大端16位
    __be16 version_max;
    __be32 kernel_sector;    // 大端32位
    __be32 fdt_sector;
    __be32 reserved;
};
#pragma pack(pop)

static int write_pre_intrd(void)
{
    volatile uint8_t *addr = (volatile uint8_t *)PRE_INTRD_ADDR;
    const volatile uint8_t *end_addr = (volatile uint8_t *)INITRD_ADDR;

    /* 1. 写入预初始化数据 */
    for (int i = 0; i < ARRAY_SIZE(pre_intrd); i++) {
        const char *str = pre_intrd[i];
        size_t len = strlen(str);

        /* 十六进制有效性验证 */
        if (len != 16) {
            printf("Invalid hex length at index %d\n", i);
            return CMD_RET_FAILURE;
        }

        /* 逐字节写入 */
        for (int j = 14; j >= 0; j -= 2) {
            char byte_str[3] = {str[j], str[j+1], '\0'};
            *addr++ = (uint8_t)simple_strtoul(byte_str, NULL, 16);
        }
    }

    /* 2. 填充零值区域 */
/*     printf("Zero-filling 0x%p-0x%p (%lu bytes)\n", 
          addr, end_addr, (ulong)(end_addr - addr)); */
    while (addr < end_addr) {
        *addr++ = 0x00;
    }

    return CMD_RET_SUCCESS;
}

static int initialize_environment(void)
{
    int ret;
    char version_str[16];

    if (env_get("env_saved") == NULL) {
        printf("First boot: Saving default environment to eMMC...\n");

        /* 设置默认环境变量 */
        snprintf(version_str, sizeof(version_str), "%d", QNAP_KERNEL_VERSION);
        env_set("qnap_kernel_version", version_str);
        env_set("qnap_kernel", QNAP_KERNEL_TYPE);

        /* 持久化保存环境 */
        if ((ret = env_save())) {
            printf("Environment save failed! (err=%d)\n", ret);
            return CMD_RET_FAILURE;
        }

        /* 设置保存标记 */
        env_set("env_saved", "1");
        if ((ret = env_save())) {
            printf("Failed to save env_saved flag! (err=%d)\n", ret);
            return CMD_RET_FAILURE;
        }
    }
    return CMD_RET_SUCCESS;
}

static int load_version_table(struct version_table_header *hdr, struct version_entry *entries)
{
    struct mmc *mmc;
    struct blk_desc *blk;
    int ret;
    ulong total_size;

    // 1. 初始化MMC设备（复用kread逻辑）
    mmc = init_mmc_device(QNAP_BOOT_DEV, false);
    if (!mmc) {
        printf("MMC init failed for device %d\n", QNAP_BOOT_DEV);
        return CMD_RET_FAILURE;
    }

    // 2. 获取块设备描述符
    if (!(blk = mmc_get_blk_desc(mmc))) {
        printf("Failed to get block descriptor\n");
        return CMD_RET_FAILURE;
    }

    // 3. 直接读取版本表头（复用kread的header处理）
    ret = blk_dread(blk, VERSION_TABLE_SECTOR, 1, hdr);
    if (ret != 1) {
        printf("Header read error (sector %lu)\n", (ulong)VERSION_TABLE_SECTOR);
        return CMD_RET_FAILURE;
    }

    // 4. 校验Magic（与kread完全一致）
    uint32_t actual_magic = be32_to_cpu(hdr->magic);
    if (actual_magic != GET_MAGIC(KREAD_MAGIC)) {
        printf("Invalid magic: 0x%08X (%s) (expected 0x%08X %s)\n",
            actual_magic,
            MAGIC_TO_STR(actual_magic),
            GET_MAGIC(KREAD_MAGIC),
            MAGIC_TO_STR(GET_MAGIC(KREAD_MAGIC)));
        return CMD_RET_FAILURE;
    }

    // 5. 计算总数据尺寸（header + entries）
    uint16_t entry_count = be16_to_cpu(hdr->entry_count);
    total_size = sizeof(struct version_table_header) +
                entry_count * sizeof(struct version_entry);

    // 6. 直接读取完整数据结构（无需中间地址）
    ret = blk_dread(blk, VERSION_TABLE_SECTOR,
                   (total_size + blk->blksz - 1) / blk->blksz,
                   hdr); // 直接写入目标结构体

    // 7. 内存拷贝entries部分（自动计算偏移量）
    memcpy(entries, (char*)hdr + sizeof(struct version_table_header),
           entry_count * sizeof(struct version_entry));

    return (ret == (total_size + blk->blksz - 1)/blk->blksz) ?
           CMD_RET_SUCCESS : CMD_RET_FAILURE;
}

static int get_sectors(uint32_t target_ver, uint32_t *kernel_sector, uint32_t *fdt_sector)
{
    struct version_table_header hdr;
    struct version_entry entries[MAX_TABLE_ENTRIES];
    int ret;

    if ((ret = load_version_table(&hdr, entries)) != CMD_RET_SUCCESS) {
        return ret;
    }

    // 遍历条目寻找匹配版本
    for (int i = 0; i < hdr.entry_count; i++) {
        uint32_t entry_min = be16_to_cpu(entries[i].version_min);
        uint32_t entry_max = be16_to_cpu(entries[i].version_max);

        if (target_ver >= entry_min &&
            target_ver <= entry_max)
        {
			*kernel_sector = be32_to_cpu(entries[i].kernel_sector); // 转换为小端
			*fdt_sector = be32_to_cpu(entries[i].fdt_sector);
            /* 新增调试打印 */
/*             printf("[DEBUG] TargetVer=%-5u | Entry %02d: min=%-5u max=%-5u | kernel=%-10u (0x%08x) fdt=%-10u (0x%08x)\n",
                  target_ver,
                  i,
                  entry_min,  // 使用转换后的值
                  entry_max,  // 使用转换后的值
                  *kernel_sector, *kernel_sector,  // 同时显示十进制和十六进制
                  *fdt_sector, *fdt_sector); */
            return CMD_RET_SUCCESS;
        }
    }

    printf("No entry matches version %u\n", target_ver);
    return CMD_RET_FAILURE;
}

static int generate_mac_serial(uint8_t *cpuid, char *mac1, char *mac2, char *sn)
{
    uint8_t low[8], high[8];
    uint32_t crc_low, crc_high;

    /* 计算CRC校验值 */
    for (int i = 0; i < 8; i++) {
        low[i] = cpuid[1 + (i << 1)];
        high[i] = cpuid[i << 1];
    }

    crc_low = crc32_no_comp(0, low, 8);
    crc_high = crc32_no_comp(crc_low, high, 8);

    /* 生成MAC地址 */
    uint8_t mac_bytes[3] = {
        (crc_low >> 16) & 0xFF,
        (crc_low >> 8) & 0xFF,
        crc_low & 0xFF
    };

    snprintf(mac1, 18, "%s:%02x:%02x:%02x",
            MAC_PREFIX, mac_bytes[0], mac_bytes[1], mac_bytes[2]);
    snprintf(mac2, 18, "%s:%02x:%02x:%02x",
            MAC_PREFIX, mac_bytes[0], mac_bytes[1], mac_bytes[2] + 1);

    /* 生成序列号 */
    uint32_t sn_suffix = (crc_high ^ crc_low) % 100000;
    sn_suffix = (sn_suffix == 0) ? (crc_high % 99999) + 1 : sn_suffix;
    snprintf(sn, 11, "%s%05u", SN_PREFIX, sn_suffix);

    return 0;
}

static int write_mac_sn_to_emmc(void)
{
    struct udevice *dev;
    uint8_t cpuid[16] = {0};
    char mac1[18], mac2[18], sn[11];
    char new_buf[qnap_cfg.sector_size], old_buf[qnap_cfg.sector_size];
    int ret, need_write = 0;
    struct blk_desc *desc;

    /* 初始化缓冲区 */
    memset(new_buf, 0, sizeof(new_buf));
    memset(old_buf, 0, sizeof(old_buf));

    /* 获取硬件设备 */
    if ((ret = uclass_get_device_by_driver(UCLASS_MISC,
                    DM_GET_DRIVER(rockchip_otp), &dev)) ||
        (ret = misc_read(dev, CFG_CPUID_OFFSET, cpuid, sizeof(cpuid)))) {
        printf("Device error: %d\n", ret);
        return ret;
    }

    /* 生成新数据 */
    generate_mac_serial(cpuid, mac1, mac2, sn);

    /* 读取现有数据 */
    if (!(desc = blk_get_devnum_by_type(IF_TYPE_MMC, QNAP_BOOT_DEV)) ||
        blk_dread(desc, SERIAL_SECTOR << (desc->log2blksz - 9), 1, old_buf) != 1) {
        need_write = 1;
    } else {
        /* 二进制数据比较 */
        need_write |= memcmp(old_buf + qnap_cfg.sn_offset, sn, 11);
        need_write |= memcmp(old_buf + qnap_cfg.mac1_offset, mac1, 17);
        need_write |= memcmp(old_buf + qnap_cfg.mac2_offset, mac2, 17);
    }

    /* 准备新数据 */
    memcpy(new_buf + qnap_cfg.sn_offset, sn, 11);
    memcpy(new_buf + qnap_cfg.mac1_offset, mac1, 17);
    memcpy(new_buf + qnap_cfg.mac2_offset, mac2, 17);

    /* 条件写入 */
    if (need_write && blk_dwrite(desc, SERIAL_SECTOR << (desc->log2blksz -9), 1, new_buf) != 1) {
        printf("Write failed at 0x%x\n", SERIAL_SECTOR);
        return CMD_RET_FAILURE;
    }

    return CMD_RET_SUCCESS;
}



static int do_qnap_boot(cmd_tbl_t *cmdtp, int flag, int argc, char *const argv[])
{
    int ret;
    char cmd_buf[64];
    ulong fdt_addr, kernel_addr;
    const char *kernel_mode;
    const int emmc_dev = QNAP_BOOT_DEV; // 从宏定义获取设备号

    /* 环境初始化 */
    if ((ret = initialize_environment()) != CMD_RET_SUCCESS) {
        return ret;
    }

    /* +++ 新增代码 +++ */
    if ((ret = write_mac_sn_to_emmc()) != CMD_RET_SUCCESS) {
        return ret;
    }

    /* 获取地址参数 */
    if (!(fdt_addr = env_get_hex("fdt_addr_r", 0)) ||
        !(kernel_addr = env_get_hex("kernel_addr_r", 0))) {
        printf("Missing required environment:\n");
        printf("  fdt_addr_r=%#lx\n  kernel_addr_r=%#lx\n", fdt_addr, kernel_addr);
        return CMD_RET_FAILURE;
    }

    /* 初始化MMC设备 */
    snprintf(cmd_buf, sizeof(cmd_buf), "mmc dev %d", emmc_dev);
    if ((ret = run_command(cmd_buf, 0))) {
        printf("eMMC%d init failed: %d\n", emmc_dev, ret);
        return ret;
    }


   /* 获取内核版本 */
    const char *ver_str = env_get("qnap_kernel_version");
    uint32_t target_ver = ver_str ? simple_strtoul(ver_str, NULL, 10) : QNAP_KERNEL_VERSION;

    uint32_t kernel_sector, fdt_sector;
    if ((ret = get_sectors(target_ver, &kernel_sector, &fdt_sector)) != CMD_RET_SUCCESS) {
        return ret;
    }

    /******************** 设备树加载 ********************/
    snprintf(cmd_buf, sizeof(cmd_buf),
            "mmc kread 0x%lx 0x%" PRIx32,
            fdt_addr, fdt_sector);

    if ((ret = run_command(cmd_buf, 0))) {
        printf("FDT read failed: %s (%d)\n", cmd_buf, ret);
        return ret;
    }

    if (fdt_check_header((void *)fdt_addr) != 0) {
        printf("Invalid FDT header at 0x%lx\n", fdt_addr);
        return CMD_RET_FAILURE;
    }

    /******************** 内核加载 ********************/
    kernel_mode = env_get("qnap_kernel");
    if (!kernel_mode) {
        printf("Using default kernel mode\n");
        kernel_mode = QNAP_KERNEL_TYPE;
    }

    if (strcmp(kernel_mode, "qnap") == 0) {
        snprintf(cmd_buf, sizeof(cmd_buf),
                "ext2load mmc %d:%d 0x%lx /boot/Image",
                emmc_dev, EMMC_PART, kernel_addr);
    } 
    else if (strcmp(kernel_mode, "custom") == 0) {
        snprintf(cmd_buf, sizeof(cmd_buf),
                "mmc kread 0x%lx 0x%" PRIx32,
                kernel_addr, kernel_sector);
    }
    else {
        printf("Invalid kernel mode: %s\n", kernel_mode);
        return CMD_RET_USAGE;
    }

    if ((ret = run_command(cmd_buf, 0))) {
        printf("Kernel load failed: %d\n", ret);
        return ret;
    }

    /* 写入预初始化内存盘 */
    if ((ret = write_pre_intrd()) != CMD_RET_SUCCESS) {
        printf("Pre-initrd write failed: %d\n", ret);
        return ret;
    }

    /* 加载主内存盘 */
    snprintf(cmd_buf, sizeof(cmd_buf),
            "ext2load mmc %d:%d 0x%lx /boot/initrd.boot",
            emmc_dev, EMMC_PART, INITRD_ADDR);
    if ((ret = run_command(cmd_buf, 0))) {
        printf("Initrd load failed: %d\n", ret);
        return ret;
    }

    /* 打印启动配置信息 */
	printf("==============================================\n");
	printf("Booting: %s kernel version %u from eMMC %d\n",
        kernel_mode, target_ver, QNAP_BOOT_DEV);
    printf("==============================================\n");

    /* 启动内核 */
    snprintf(cmd_buf, sizeof(cmd_buf),
            "booti 0x%lx 0x%lx:0x%lx 0x%lx",
            kernel_addr, PRE_INTRD_ADDR, INITRD_SIZE, fdt_addr);
    return run_command(cmd_buf, 0);
}

U_BOOT_CMD(
    qnap_boot, 1, 0, do_qnap_boot,
    "QNAP Custom Boot Sequence",
    "\nBoot Process:\n"
    "1. Load FDT \n"
    "2. Load kernel \n"
    "3. Load initrd and boot kernel"
);
