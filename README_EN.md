# OpenWrt IP Throttle Plugin (IPThrottle)

**🌐 Language / 语言**: [English](README_EN.md) | [中文](README.md)

---

**Precisely control network bandwidth for every device, say goodbye to network congestion.**

Based on a hybrid architecture of nftables + tc htb, it achieves precise IP-based traffic throttling with independent/shared bandwidth modes.  
**Compatible with passwall transparent proxy**, both proxy and direct traffic can be throttled, covering all network scenarios.  
Supports multi-WAN, IP ranges, protocol filtering, and time schedules to meet complex network environment requirements.

### Core Features

- 🎯 **Precise Throttling**: Independent upload/download limits with ±1% accuracy (direct) / ±20% (proxy)
- 🌐 **passwall Compatible**: Automatically identifies proxy traffic, no extra configuration needed
- 📊 **Dual Throttling Modes**: Independent (per-IP bandwidth) / Shared (multi-IP bandwidth pool)
- ⏰ **Time Scheduling**: Auto-activation by day of week/time period, flexible network usage control
- 🚀 **Multi-WAN Support**: Independent rules for different WAN interfaces
- 🔧 **LuCI Interface**: Visual configuration with priority sorting, clear at a glance

## Core Functions

### Precise Traffic Throttling
- **Independent Throttling**: Allocate dedicated bandwidth limit for each IP
- **Shared Throttling**: Multiple IPs share the same bandwidth pool
- **Precise Control**: Separate upload and download limits (KB/s)

### Flexible Rule Configuration
- **Multi-target Support**:
  - Single IP address
  - IP address range (e.g., 192.168.1.10-192.168.1.20)
  - Mixed target lists
- **Protocol Filtering**: Supports TCP, UDP, or any protocol
- **Multi-WAN Support**: Set different rules for different WAN interfaces

### Time Scheduling
- **24-hour Schedule**: Set start and end times
- **Weekly Cycle**: Support weekdays, weekends, or custom day combinations
- **Flexible Combinations**: Set different time periods for different days

### Priority Management
- **Rule Priority**: Supports priority settings from 1-100
- **Conflict Resolution**: Automatically handles IP conflicts, prioritizes higher-priority rules

## System Requirements

- **OpenWrt Version**: 23.05 and above
- **Architecture Support**: All architectures supported by OpenWrt
- **Required Dependencies**:
  - tc (Traffic Control)
  - nftables
  - kmod-sched-core
  - kmod-sched-htb

## Installation

### OpenWrt 23.05 / 24.10 (opkg + .ipk)

**Web UI Installation**: LuCI → System → Software → Upload Package → Select `.ipk` file → Install

**SSH Installation**:
```bash
# Download .ipk file to router, or use wget
opkg install ipthrottle-x86_64-24.10.0.ipk
```

### OpenWrt 25.12+ (apk + .apk)

⚠️ **Important**: OpenWrt 25 uses the apk package manager and **does not support Web UI upload installation** (will report signature verification error). Must install via SSH.

**SSH Installation**:
```bash
# 1. Download .apk file to router, or use wget
# 2. Use --allow-untrusted parameter to skip signature verification
apk add --allow-untrusted ipthrottle-x86_64-25.12.0.apk
```

**Parameter Explanation**:
- `--allow-untrusted`: Allows installation of unsigned or mismatched signature packages (this project uses self-signed keys)

### Automatic Dependency Installation

After plugin installation, the service will automatically detect and install missing dependencies (tc, nftables, kmod-sched, etc.) on startup. **No manual installation required**.

### Source Compilation

```bash
# Clone source code
git clone https://github.com/luowei729/OpenWrt-IPThrottle.git

# Enter directory
cd OpenWrt-IPThrottle

# Compile (requires OpenWrt SDK environment)
make package/ipthrottle/compile V=s
```

## Quick Start

### 1. Start Service

```bash
/etc/init.d/IPThrottle start
/etc/init.d/IPThrottle enable
```

### 2. Access Web Interface

Open browser and visit:
```
http://192.168.1.1/cgi-bin/luci/admin/network/IPThrottle
```

Default location: **Network → IP Throttle**

### 3. Create First Rule

1. Click "Add New Rule"
2. Fill in rule information:
   - **Rule Name**: e.g., "Limit Download"
   - **WAN Interface**: Select wan1 (or all)
   - **IP Address**: Enter 192.168.1.100
   - **Download Limit**: Enter 1024 (KB/s)
   - **Upload Limit**: Enter 512 (KB/s)
   - **Time Schedule**: Set active time
3. Click "Save & Apply"

## Configuration Examples

### Example 1: Limit Single Device

```json
{
  "name": "Limit Download",
  "wan_mask": "wan1",
  "ip_entry": ["192.168.1.100"],
  "proto": "any",
  "mode": "independent",
  "upload_kbps": "512",
  "download_kbps": "1024",
  "priority": "10",
  "schedule_type": "weekly",
  "schedule_json": [{"d": [1,2,3,4,5], "s": "09:00", "e": "18:00"}],
  "comment": "Limit download during work hours",
  "enabled": "1"
}
```

### Example 2: Limit IP Range (Shared Throttling)

```json
{
  "name": "Network Segment Limit",
  "wan_mask": "wan1",
  "ip_entry": ["192.168.1.50-192.168.1.100"],
  "proto": "any",
  "mode": "shared",
  "upload_kbps": "2560",
  "download_kbps": "5120",
  "priority": "20",
  "schedule_type": "always",
  "comment": "Limit total bandwidth for entire network segment",
  "enabled": "1"
}
```

## Configuration Parameters

### Basic Parameters

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| name | string | Yes | Rule name | "Download Limit" |
| wan_mask | string | Yes | WAN interface | "wan1", "wan2", "all" |
| ip_entry | list | Yes | IP address list | ["192.168.1.100"] |
| proto | string | Yes | Protocol | "any", "tcp", "udp" |
| mode | string | Yes | Throttling mode | "independent", "shared" |
| upload_kbps | integer | Yes | Upload limit (KB/s) | 512 |
| download_kbps | integer | Yes | Download limit (KB/s) | 2048 |
| priority | integer | No | Priority (1-100) | 10 |
| comment | string | No | Comment | "Work hours limit" |
| enabled | string | Yes | Whether enabled | "1"(enabled), "0"(disabled) |

### Time Schedule Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| schedule_type | Schedule type | "always"(all day), "weekly"(scheduled) |
| schedule_json | Time configuration JSON | [{"d":[1,2,3,4,5], "s":"09:00", "e":"18:00"}] |

**schedule_json Format Details**:
```json
[
  {
    "d": [1,2,3,4,5],
    "s": "09:00",
    "e": "18:00"
  }
]
```

- d: Active days of week (0=Sunday, 1=Monday, ..., 6=Saturday)
- s: Start time (24-hour format)
- e: End time (24-hour format)

## Command Line Tools

### Basic Operations

```bash
/etc/init.d/IPThrottle start
/etc/init.d/IPThrottle stop
/etc/init.d/IPThrottle restart
/etc/init.d/IPThrottle status
/etc/init.d/IPThrottle enable
/etc/init.d/IPThrottle disable
```

### Advanced Operations

```bash
/usr/sbin/IPThrottle apply
/usr/sbin/IPThrottle clear
/usr/sbin/IPThrottle reload
/usr/sbin/IPThrottle status
/usr/sbin/IPThrottle schedule
```

## Troubleshooting

### Issue 1: Service Cannot Start

```bash
# Check if dependencies are installed
opkg list-installed | grep -E "tc|nftables"

# Install missing dependencies
opkg install tc nftables kmod-sched-core kmod-sched-htb

# View startup logs
logread | grep IPThrottle
```

### Issue 2: LuCI Interface Not Found

```bash
# Reinstall LuCI component
opkg install luci-app-IPThrottle

# Restart web server
/etc/init.d/uhttpd restart
```

### Issue 3: Rules Not Taking Effect

```bash
# Confirm service is running
/etc/init.d/IPThrottle status

# Check if rules are loaded correctly
/usr/sbin/IPThrottle status

# View nftables rules
nft list ruleset | grep IPThrottle

# View tc queues
tc qdisc show

# Check logs
logread | grep IPThrottle
```

## Performance Metrics

### Supported Rule Count
- **Recommended**: 10-20 rules
- **Maximum**: 50 rules (depends on router performance)

### Performance Impact
- **CPU Usage**: 2% (when applying rules)
- **Memory Usage**: 5MB
- **Startup Time**: 3 seconds (20 rules)

### Throttling Accuracy
- **Minimum Throttle Unit**: 1 KB/s
- **Time Schedule Accuracy**: 1 minute
- **Application Latency**: 100ms

## ☕ Support the Developer

If this project has been helpful to you, feel free to buy the author a coffee ☕

Your support is the motivation for continuous maintenance and improvement!

| Alipay | WeChat Pay |
|:---:|:---:|
| <img src="https://raw.githubusercontent.com/luowei729/OpenWrt-IPThrottle/main/Alipay.png" width="200" alt="Alipay Donation"> | <img src="https://raw.githubusercontent.com/luowei729/OpenWrt-IPThrottle/main/WeChatPay.png" width="200" alt="WeChat Donation"> |

> Thank you to every supporter for your generous encouragement 🙏

## License

This project is licensed under the MIT License
