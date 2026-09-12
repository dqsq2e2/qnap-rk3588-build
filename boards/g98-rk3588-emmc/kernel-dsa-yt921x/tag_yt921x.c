// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Motorcomm YT921x Switch Extended CPU Port Tagging
 *
 * Copyright (c) 2025 David Yang <mmyangfl@gmail.com>
 *
 * +----+----+-------+-----+----+---------
 * | DA | SA | TagET | Tag | ET | Payload ...
 * +----+----+-------+-----+----+---------
 *   6    6      2      6    2       N
 *
 * Tag Ethertype: CPU_TAG_TPID_TPID (default: ETH_P_YT921X = 0x9988)
 *   * Hardcoded for the moment, but still configurable. Discuss it if there
 *     are conflicts somewhere and/or you want to change it for some reason.
 * Tag:
 *   2: VLAN Tag
 *   2:
 *     15b: Rx Port Valid
 *     14b-11b: Rx Port
 *     10b-8b: Tx/Rx Priority
 *     7b: Tx/Rx Code Valid
 *     6b-1b: Tx/Rx Code
 *     0b: ? (unset)
 *   2:
 *     15b: Tx Port(s) Valid
 *     10b-0b: Tx Port(s) Mask
 *
 * Backported to QNAP 5.10 (5.10.60) DSA framework:
 *  - no net/dsa/tag.h there: EtherType header is moved by hand, in the same
 *    way as tag_rtl4_a.c (RX skb->data points 2 bytes into the tag);
 *  - rcv gains the legacy struct packet_type *pt argument;
 *  - dsa_user_to_port -> dsa_slave_to_port (dsa_priv.h);
 *  - dsa_conduit_find_user -> dsa_master_find_slave;
 *  - dsa_default_offload_fwd_mark -> skb->offload_fwd_mark = 1;
 *  - .needed_headroom -> .overhead;
 *  - MODULE_ALIAS_DSA_TAG_DRIVER takes a single argument.
 */

#include <linux/bitfield.h>
#include <linux/etherdevice.h>

#include <net/dsa.h>
#include "dsa_priv.h"

#ifndef DSA_TAG_PROTO_YT921X_VALUE
#define DSA_TAG_PROTO_YT921X_VALUE	30
#endif
#ifndef DSA_TAG_PROTO_YT921X
#define DSA_TAG_PROTO_YT921X		DSA_TAG_PROTO_YT921X_VALUE
#endif

#ifndef ETH_P_YT921X
#define ETH_P_YT921X	0x9988
#endif

#define YT921X_TAG_NAME	"yt921x"

#define YT921X_TAG_LEN	8

#define YT921X_TAG_PORT_EN		BIT(15)
#define YT921X_TAG_RX_PORT_M		GENMASK(14, 11)
#define YT921X_TAG_PRIO_M		GENMASK(10, 8)
#define  YT921X_TAG_PRIO(x)			FIELD_PREP(YT921X_TAG_PRIO_M, (x))
#define YT921X_TAG_CODE_EN		BIT(7)
#define YT921X_TAG_CODE_M		GENMASK(6, 1)
#define  YT921X_TAG_CODE(x)			FIELD_PREP(YT921X_TAG_CODE_M, (x))
#define YT921X_TAG_TX_PORTS_M		GENMASK(10, 0)
#define  YT921X_TAG_TX_PORTS(x)			FIELD_PREP(YT921X_TAG_TX_PORTS_M, (x))

/* Incomplete. Some are configurable via RMA_CTRL_CPU_CODE, the meaning of
 * others remains unknown.
 */
enum yt921x_tag_code {
	YT921X_TAG_CODE_FORWARD = 0,
	YT921X_TAG_CODE_UNK_UCAST = 0x19,
	YT921X_TAG_CODE_UNK_MCAST = 0x1a,
	YT921X_TAG_CODE_PORT_COPY = 0x1b,
	YT921X_TAG_CODE_FDB_COPY = 0x1c,
};

static struct sk_buff *
yt921x_tag_xmit(struct sk_buff *skb, struct net_device *netdev)
{
	struct dsa_port *dp = dsa_slave_to_port(netdev);
	__be16 *tag;
	u16 ctrl;

	skb_push(skb, YT921X_TAG_LEN);
	memmove(skb->data, skb->data + YT921X_TAG_LEN, 2 * ETH_ALEN);

	tag = (__be16 *)(skb->data + 2 * ETH_ALEN);

	tag[0] = htons(ETH_P_YT921X);
	/* VLAN tag unrelated when TX */
	tag[1] = 0;
	ctrl = YT921X_TAG_CODE(YT921X_TAG_CODE_FORWARD) | YT921X_TAG_CODE_EN |
	       YT921X_TAG_PRIO(skb->priority);
	tag[2] = htons(ctrl);
	ctrl = YT921X_TAG_TX_PORTS(BIT(dp->index)) | YT921X_TAG_PORT_EN;
	tag[3] = htons(ctrl);

	return skb;
}

static struct sk_buff *
yt921x_tag_rcv(struct sk_buff *skb, struct net_device *netdev,
	       struct packet_type *pt)
{
	unsigned int port;
	__be16 *tag;
	u16 rx;

	if (unlikely(!pskb_may_pull(skb, YT921X_TAG_LEN)))
		return NULL;

	/* skb->data points 2 bytes in, behind the tag EtherType */
	tag = (__be16 *)(skb->data - 2);

	if (unlikely(tag[0] != htons(ETH_P_YT921X))) {
		dev_warn_ratelimited(&netdev->dev,
				     "Unexpected EtherType 0x%04x\n",
				     ntohs(tag[0]));
		return NULL;
	}

	/* Locate which port this is coming from */
	rx = ntohs(tag[2]);
	if (unlikely((rx & YT921X_TAG_PORT_EN) == 0)) {
		dev_warn_ratelimited(&netdev->dev,
				     "Unexpected rx tag 0x%04x\n", rx);
		return NULL;
	}

	port = FIELD_GET(YT921X_TAG_RX_PORT_M, rx);
	skb->dev = dsa_master_find_slave(netdev, 0, port);
	if (unlikely(!skb->dev)) {
		dev_warn_ratelimited(&netdev->dev,
				     "Couldn't decode source port %u\n", port);
		return NULL;
	}

	skb->priority = FIELD_GET(YT921X_TAG_PRIO_M, rx);

	if (!(rx & YT921X_TAG_CODE_EN)) {
		dev_warn_ratelimited(&netdev->dev,
				     "Tag code not enabled in rx packet\n");
	} else {
		u16 code = FIELD_GET(YT921X_TAG_CODE_M, rx);

		switch (code) {
		case YT921X_TAG_CODE_FORWARD:
		case YT921X_TAG_CODE_PORT_COPY:
		case YT921X_TAG_CODE_FDB_COPY:
			/* Already forwarded by hardware */
			skb->offload_fwd_mark = 1;
			break;
		case YT921X_TAG_CODE_UNK_UCAST:
		case YT921X_TAG_CODE_UNK_MCAST:
			/* NOTE: hardware doesn't distinguish between TRAP (copy
			 * to CPU only) and COPY (forward and copy to CPU). In
			 * order to perform a soft switch, NEVER use COPY action
			 * in the switch driver.
			 */
			break;
		default:
			dev_warn_ratelimited(&netdev->dev,
					     "Unknown code 0x%02x\n", code);
			break;
		}
	}

	/* Remove YT921x tag and update checksum */
	skb_pull_rcsum(skb, YT921X_TAG_LEN);
	memmove(skb->data - ETH_HLEN, skb->data - ETH_HLEN - YT921X_TAG_LEN,
		2 * ETH_ALEN);

	return skb;
}

static const struct dsa_device_ops yt921x_netdev_ops = {
	.name	= YT921X_TAG_NAME,
	.proto	= DSA_TAG_PROTO_YT921X,
	.xmit	= yt921x_tag_xmit,
	.rcv	= yt921x_tag_rcv,
	.overhead = YT921X_TAG_LEN,
};

module_dsa_tag_driver(yt921x_netdev_ops);

MODULE_DESCRIPTION("DSA tag driver for Motorcomm YT921x switches");
MODULE_LICENSE("GPL");
MODULE_ALIAS_DSA_TAG_DRIVER(DSA_TAG_PROTO_YT921X);
