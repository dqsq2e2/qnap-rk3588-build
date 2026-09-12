# BDY G98 (RK3588) 适配 QNAP TS-AI642 构建

## 硬件清单（与原厂 dtb / 6.6 已验证 dts 核对）

| 外设 | 控制器/总线 | 说明 |
|---|---|---|
| 2x M.2 NVMe | pcie3x4(fe150000) + pcie3x2(fe160000) | 共享 pcie30phy，**必须 NANBNB(x2+x2)**，vcc3v3 供电 gpio3_PD5 |
| 1x SATA | sata0(fe210000) | combphy0_ps，pm-reset gpio0_PD5 |
| 2x 2.5G 网口 | RTL8125 @ pcie2x1l0(fe170000)/pcie2x1l1(fe180000) | endpoint 0002:21:00.0 / 0003:31:00.0 |
| 8x 千兆网口 | 2x YT9215 交换机（各4口） | RGMII 挂 gmac0/gmac1，DSA 驱动（lan1-8），见「已知待办」 |
| 2x USB3.0 | usbdrd3_0(fc000000) + usbdrd3_1(fc400000) | 均 host 模式 |
| 1x HDMI | hdmi0 | DDC 硬件通路坏，用 i2c-gpio bitbang（GPIO4_B7/C0） |
| RTC | hym8563 @ i2c6 | 中断 gpio0_PB2 |
| PMIC | rk806 @ spi2 | CPU 大核 rk8602/rk8603 @ i2c0，NPU rk8602 @ i2c2 |
| 音频 | es8311 @ i2c3 | 原厂开启，保留 |
| 风扇 | **无 PWM 风扇**（原厂与 6.6 dts 均无） | model.conf MAX_FAN_NUM=0 |
| SD/wifi | 无 | sdmmc/sdio disabled |

串口：uart2，**115200**（遵循 QNAP 构建约定；fiq-debugger + RK3588_115200MINIALL.ini）。

## 关键适配决策

1. **U-Boot 用通用 `rk3588_defconfig`**：已带 QNAP 尾巴（BOOTARGS qnap_model=ts642、
   ENV_IS_IN_MMC、LOADER_INI=RK3588_115200MINIALL.ini），且原厂 uboot dtb 即为
   rk3588-evb（eMMC/SFC/UART2 都有），无需新 defconfig。
2. **dts 以 develop-6.6 已验证的 rk3588-bdy-g98.dts 为蓝本**（board-org 有归档），
   不直接编译原厂反编译 dts——原厂 dts 很多外设没开（HDMI 等），且是
   rk3588-nvr-demo-v10-spi-nor 的派生物。所有标签已逐一核对 QNAP 5.10 内核树存在。
3. **pcie30phy = PHY_MODE_PCIE_NANBNB**（=0，x2+x2 拆分），这是双 M.2 的命门，
   与主线 data-lanes=<1 1 2 2> 等价。
4. **uart7 保持 disabled**：本板未使用。（早期注释称 uart7m2 与 pcie2x1l0 PERST#
   冲突，那是 PERST# 误记为 GPIO1_PB4 时的结论；实际 PERST# 是 **GPIO4_PB4**，无冲突。）
5. **YT9215 交换机走 DSA 方案**（2026-09-12 起，取代早期 sw 非管理方案）：
   主线 mmyangfl 版 yt921x DSA 驱动回移 QNAP 5.10，补丁
   `kernel-patchs-523/0032`（驱动本体+tag 驱动，必应用）+ `0033`（Kconfig/Makefile
   挂钩，锚点不匹配会被警告跳过，需手工补）。修改版源留档
   `boards/g98-rk3588-emmc/kernel-dsa-yt921x/`，回移细节见 HANDOFF.md 第 2 节。
   每颗交换机的 4 个用户口以 DSA 从口形式出现（lan1-8）；sw 版存档在
   `kernel-yt9215/`（已弃用）。

## 构建

```bash
# boards/qnap_build.conf: BOARD_NAME="g98-rk3588-emmc"
./create_dom.sh uboot=only   # 先单独验证 uboot
./create_dom.sh dtb=only     # 再验证 dtb
./create_dom.sh kernel=only
./create_dom.sh              # 全量
```

## 已知待办（刷机后按 README 第 6/8 步实测迭代）

1. **DSA 交换机刷机验证**：lan1-8 是否全部生成（`ip link` 看 lanX@gmacX）、
   `bridge fdb show` 是否硬件卸载、dmesg 里 yt921x 的 chipid/probe 日志。
   风险点：5.10 stmmac 在 gmac 无 phy-handle/fixed-link 时的 probe 行为未验证
   （若 gmac 起不来，备选：gmac 侧恢复 fixed-link）。
2. **model.conf 实测校正**：System Disk 的 DEV_DOMAIN/DEV_BUS（当前按
   bus-range 推算：槽1 domain0/B00、槽2 domain1/B16）、SATA 的 DEV_BUS
   写法、Network/USB 端口的 DEV_BUS/DEV_PATH（Network 3-10 的 DSA 从口写法
   为推测），用 `hwinfo --disk --netcard` 和 /sys 实际路径校正。
3. **RTL8125 LED**：dts 带了 r8125,ledN=0x22b 修复节点，但需 QNAP r8125
   驱动支持解析才生效（不支持则 2.5G 下网口灯不亮，纯外观问题）。
4. **原厂 SPI 里 fnOS 的 eMMC 会被 DOM 全盘覆盖**，刷机前如有需要先用
   刷机助手备份 eMMC。

## 参考归档（board-org/）

- `rk3588-bdy-g98-develop-6.6.dts`：6.6 BSP 已验证适配（本次 dts 的蓝本）
- `factory-spi-nvr-demo-v10-spi-nor.decompiled.dts`：原厂 SPI 备份反编译 dts
- `factory-kernel.dtb`：原厂内核 dtb 原件
- `rk3588_defconfig`：使用的 uboot 配置备份
