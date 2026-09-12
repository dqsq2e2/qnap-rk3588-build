# G98 × QNAP 适配 — 交接文档（2026-09-12）

目标：把 BDY G98 (RK3588) 适配进 qnap-rk3588-build，构建可刷的 QTS(TS-AI642) 固件。

---

## 1. 已完成（可直接采信）

### 1.1 构建体系与板型骨架
- `boards/g98-rk3588-emmc/` 已建好：`custom.conf` / `patch/etc/model.conf` /
  `patch/etc/fw_env.config` / `patch/sbin/` / `board-org/`（原厂参考资料归档）/
  `README-g98.md` / `kernel-yt9215/`（见 1.4 sw 方案存档）
- `boards/qnap_build.conf` 的 BOARD_NAME 已切到 `g98-rk3588-emmc`
- U-Boot 用通用 `rk3588_defconfig`（已带 QNAP 尾巴：115200、BOOTARGS
  qnap_model=ts642、RK3588_115200MINIALL.ini、ENV_IS_IN_MMC），**零改动**
- 串口遵循 QNAP 约定 **115200**（注意：与该项目平时的 1500000 不同）

### 1.2 原厂 dtb 提取（硬件事实来源）
- 从 `G98的原厂SPI备份-标签G98.img` 提取反编译：内核 dtb @0x300800
  （compatible `rk3588-nvr-demo-v10-spi-nor`，170KB）；uboot dtb @0x2FA200
  （原版 rk3588-evb，证明通用 defconfig 可用）
- 反编译工具已沉淀为 skill：`.workbuddy/skills/rk-dtb-extract/`
- 产物：`_work/factory_g98.dts`（反编译 dts）+ `board-org/factory-kernel.dtb`

### 1.3 内核 dts（主交付物）
- `boards/dts-files/rk3588-bdy-g98-emmc.dts`
- 蓝本 = develop-6.6 已验证 dts（`board-org/rk3588-bdy-g98-develop-6.6.dts`），
  非原厂 dts（原厂很多外设没开，如 HDMI）
- 全部标签已在 QNAP 5.10 内核树（GPL_QTS 5.2.3，已下载解包于 WSL
  `~/qnap-dl/src`）逐一核对存在
- 要点：pcie30phy=PHY_MODE_PCIE_NANBNB（双 M.2 命门）；**pcie2x1l0 PERST#
  已纠正为 GPIO4_PB4**（曾误记 GPIO1_PB4，uart7 冲突说法随之作废，uart7
  仅因未使用而 disabled）；HDMI 用 i2c-gpio bitbang DDC（硬件缺陷 workaround）

### 1.4 交换芯片驱动 — sw 方案（已被 DSA 方案取代，存档备用）
- `boards/g98-rk3588-emmc/kernel-yt9215/yt9215.c`（baidxi swconfig 驱动剥框架版，
  835 行）+ `qnap-kernel/kernel-patchs-523/0032`（本体）+ `0033`（Makefile 挂钩）
- **用户已拍板改走 DSA**，custom.conf 的 KERNEL_PATCH_SET 已换成 DSA 版
  0032/0033（2026-09-12 完成，见第 2 节）；sw 版补丁文件已随 custom.conf
  切换而弃用，源文件留 kernel-yt9215/ 存档

### 1.5 关键调研结论
- QNAP 5.10 内核树**无任何 YT9215 交换机驱动**（仅 motorcomm PHY 驱动）
- YT9215 DSA 主线驱动 = David Yang (mmyangfl) 的 net-next 系列，已合并：
  `git.zx2c4.com/wireguard-linux/commit?id=186623f4aa72...`（2891+504 行）
- 参考 `.ko`（`dsa驱动参考/yt921x_driver.ko`）vermagic=**6.1.141** → 证明该驱动
  可编 6.1，回移 5.10 工作量可控
- tag 协议需要 `DSA_TAG_PROTO_YT921X=30`、`ETH_P_YT921X=0x9988`；kdev 树有
  现成兼容垫片 `net/dsa/port_fnos.h`

---

## 2. DSA 驱动回移 5.10 — ✅ 已完成并编译验证（2026-09-12）

WSL 已恢复可用，三个待核实项已在 QNAP 5.10.60 树（`~/qnap-dl/src/GPL_QTS/src/linux-5.10`）
逐一查实，且 **yt921x.o/tag_yt921x.o 已用 aarch64-linux-gnu-gcc 13.3 实编译通过、
dts 已在树内编成 dtb**（验证后树保持打补丁状态，.config 为 TS-X42 配置 + DSA=m）。
**原 6.x→5.10 对照表有多处错误，以此节为准**：

### 5.10 实测结论（推翻原对照表的部分）
- tag 驱动注册是**链表制**（`dsa_tag_drivers_register`），proto=30 不用动
  `include/net/dsa.h` 枚举，`#define DSA_TAG_PROTO_YT921X 30` 垫片即可；
  `dsa_tag_driver_get()` 里 `request_module("dsa_tag-%d")` 与
  `MODULE_ALIAS_DSA_TAG_DRIVER` 的 `dsa_tag-30` 对上，模块可自动加载
- **`get_tag_protocol` 在 5.10 就是三参** `(ds, port, mprot)`，不用改
- 5.10 **有** `port_change_mtu`/`port_max_mtu`/`port_mirror_add/del`（4参无 extack）/
  `port_mdb_add/del`（switchdev_obj_port_mdb，无 dsa_db）/`port_egress_floods`，保留
- 5.10 **有** `port_vlan_filtering`（第 4 参是 switchdev_trans）与 `port_vlan_prepare`；
  `port_vlan_add` 是 **void**（错误只能 dev_err）
- 5.10 **无** tag.h/etype 助手：tag RX 时 `skb->data` 已越过头 2 字节
  （tag=skb->data-2，同 tag_rtl4_a.c 手法手工搬移 MAC 头）
- 5.10 **无** `dsa_cpu_ports`/`dsa_switch_for_each_user_port`/`dsa_port_is_cpu`/
  `dsa_port_bridge_dev_get`/`dsa_port_offloads_bridge_dev`/`container_of_const`/
  `ethtool_puts`/`dsa_switch_shutdown`/`disable_delayed_work_sync`/`phylink_get_caps`/
  `ds->phylink_mac_ops`/`ds->assisted_learning_on_cpu_port`/eth_*_stats/rmon/pause/
  stats64/`port_pre_bridge_flags`/`port_bridge_flags`/`port_setup` op —— 均已改写/删除
- **5.10 用 gnu89**：for 循环声明全部外提（主线 6.x 源码是 gnu11 写法）
- CPU 口 phylink 走 `dsa_port_phylink_mac_ops` 分发到 dsa_switch_ops 的
  phylink_mac_config/link_up/link_down（无 adjust_link 时），`phylink_validate`
  取代了 get_caps
- **dsa,member 不能删**：5.10 一样解析它；两颗交换机无互联 link，必须分属两棵树
  （<0 0>/<1 0>），缺省会同进 tree 0 导致 CPU 口配错
- CPU 口是 **RGMII**（rgmii-txid）：主线精简版驱动不支持 XMII，已从 kdev 全功能版
  搬入 RGMII port_config（TX 2ns/RX 1.95ns 延迟）
- 内部 PHY 挂接用 5.10 经典路数：驱动实现 `phy_read/phy_write`（intif），
  DSA 核心建 slave_mii_bus 按端口号探测；**删掉**了 6.x 的自注册 mdio 总线，
  dts 不写 mdio 子节点/phy-handle

### 实编译抓到并修掉的问题（第一轮手写版未过编）
- `switchdev_obj_port_vlan` 在 5.10 是**范围**（vid_begin/vid_end）——VLAN add/del
  改为按范围循环
- 5.10 **无** `PHY_INTERFACE_MODE_100BASEX`（5.13 才加）——SGMII/*BASEX/RGMII 即可
- `port_mdb_add` 在 5.10 是 **void**（del 才是 int）
- `clamp(msecs/5000, 1, U16_MAX)` 类型混搭触发 -Werror——改 `clamp_t(unsigned int,...)`
- **QNAP 官方 config：IPV6=m → BRIDGE 封顶 =m → NET_DSA 只能 =m**。DSA 三件套
  按模块走（custom.conf 已写 =m）：dsa_core/tag_yt921x/yt921x 均可被 QTS 正常
  modprobe，tag 由 `dsa_tag-30` 别名自动加载。**不要强改 =y**（需连 IPV6=y 一起翻）

### 产出物（均已落位）
- 修改版源留档：`boards/g98-rk3588-emmc/kernel-dsa-yt921x/`（yt921x.c/yt921x.h/tag_yt921x.c）
- 补丁：`qnap-kernel/kernel-patchs-523/0032-add-yt921x-dsa-driver.patch`（三个新文件）
  + `0033-yt921x-dsa-build-hooks.patch`（4 个 Kconfig/Makefile 挂钩）——
  **均已对真实 QNAP 树 `patch -p1 --dry-run` 通过**（生成脚本 `_work/gen_dsa_patches.py`）
- `custom.conf`：补丁集已换 0032/0033 DSA 版；config_matrix 换成
  `CONFIG_NET_DSA=m`/`CONFIG_NET_DSA_YT921X=m`/`CONFIG_NET_DSA_TAG_YT921X=m`
  （IPV6=m 限制只能模块，见上节）
- dts 交换机节点已改 DSA 绑定：`switch@1d`（compatible 改 `motorcomm,yt9215`）+
  `dsa,member` 双树 + `ethernet-ports{port@1-4 lan、port@9 cpu}`，**gmac 侧删掉了
  fixed-link**（DSA master 不带），lan 编号 mdio1/gmac1 侧 lan1-4、mdio0/gmac0 侧 lan5-8
- `model.conf`：Network 段已重排 10 口（2x RTL8125 + lan1-8；DSA 从口无独立总线设备，
  DEV_BUS 写宿主 gmac、DEV_PORT 写用户口序号 1-4，**此写法为推测，需刷机后用
  hwinfo --netcard/hal_util 实测校正**）

### 后续验证步骤
编译已在 WSL 过掉（.o + dtb），构建机 `./create_dom.sh kernel=only` 应直接过；
重点是刷机后核对：dsa_core/tag_yt921x/yt921x 三模块是否自动加载、lan1-8 是否
全部生成、`bridge fdb show` 是否硬件卸载、`ip link` 看 lanX@gmacX。
若 5.10 stmmac 在 gmac 无 phy-handle/fixed-link 时 probe 失败（phylink 兜底行为
待验证），备选方案是 gmac 侧恢复 fixed-link（与交换机 CPU 口的并存不冲突）。

---

## 3. 未开始：固件从 NVMe 启动（用户点名"顺手实现"）

启动链已确认（2026-09-12 用户拍板）：BootROM → **SPI 主线 u-boot**（uboot-mainline
项目，已支持 NVMe 引导）→ 直接加载 DOM 上的内核/initrd。**不经过 u-boot-qnap**，
QNAP BSP uboot 的 PCI/NVMe/qnap_boot 设备选择均无需折腾，本节原调查方向作废。

剩下的工作只在固件盘（DOM）侧：
1. **create_dom.sh 无需扩展**：产出的 DOM 镜像通用，用户直接写入 NVMe 盘即可，
   SPI 主线 u-boot 负责引导（与写 eMMC/SD 同一镜像，无新增板型）
2. model.conf `[Boot Disk 1]` DISK_DRV_TYPE 从 MMC 改为 NVMe 的写法
   （仓库内无先例，参 rock-5c model.conf 的 `[System Disk N]` NVMe 盘
   PCIe 寻址写法类推；QTS HAL 是否接受 Boot Disk 用 NVME 需实测）
3. SPI 主线 u-boot 侧零改动：PCIe/NVMe 引导已支持，pcie30phy NANBNB 在主线
   写法是 `data-lanes = <1 1 2 2>`（uboot-mainline dts 已修，2026-09-10）

---

## 4. 构建与验证流程（本机 wsl.exe 已被安全中心拉黑，须到 Ubuntu 22.04 构建机）

```bash
./create_dom.sh uboot=only    # 1. 先验证 uboot
./create_dom.sh dtb=only      # 2. dts 编译（最先暴露标签/语法问题）
./create_dom.sh kernel=only   # 3. 内核+模块（验证 DSA 补丁编译）
./create_dom.sh               # 4. 全量出 zip
```

刷机后迭代（README-g98.md 待办详单）：
- model.conf 用 `hwinfo --disk --netcard` 和 /sys 实际路径校正
  （System Disk DEV_DOMAIN/DEV_BUS、SATA 写法、Network/USB 端口路径）
- RTL8125 LED：r8125,ledN 属性需 QNAP r8125 驱动支持才生效（否则只是灯不亮）
- eMMC 里的 fnOS 会被 DOM 覆盖，刷前用刷机助手备份

---

## 5. 环境/账号备忘

- G98 串口 COM7；QTS 构建后波特率 **115200**（平时项目习惯 1500000，别搞混）
- 刷机助手 root/root；fnOS root/root；Debian pi/pi；MAC 随机 → IP 每次变
- QNAP 内核源码本机位置：WSL `~/qnap-dl/src/GPL_QTS/src/linux-5.10`
  （md5 已校验与 qnap_build.conf 一致；构建机上 create_dom.sh 会自动重下）
- 项目记忆：`.workbuddy/memory/MEMORY.md` + `2026-09-12.md`（含完整决策史）
