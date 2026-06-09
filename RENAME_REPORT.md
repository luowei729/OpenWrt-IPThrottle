# IPThrottle 命名规范统一报告

**时间**: 2026-06-10 00:26  
**状态**: ✅ 已完成

## 一、命名规范

### 1. 小写形式 (用于代码标识符)
- 包名: `ipthrottle`
- 命令: `ipthrottle`
- 配置: `ipthrottle`
- 服务: `ipthrottle`
- 路径: `/usr/lib/ipthrottle/`

### 2. 驼峰形式 (品牌显示)
- 品牌名: `IPThrottle`
- 用于: LuCI 界面标题、文档标题、README 等

### 3. 日志标签
- 格式: `ipthrottle-模块名`
- 示例: `ipthrottle-core`, `ipthrottle-ip`, `ipthrottle-wan`, `ipthrottle-schedule`

## 二、已完成的修改

### 1. 文件重命名 ✅
```
✓ files/usr/lib/iptest/ → files/usr/lib/ipthrottle/
✓ files/etc/config/iptest → files/etc/config/ipthrottle
✓ files/etc/init.d/iptest → files/etc/init.d/ipthrottle
✓ files/usr/sbin/iptest → files/usr/sbin/ipthrottle
✓ files/usr/lib/ipthrottle/iptest-daemon → files/usr/lib/ipthrottle/ipthrottle-daemon
✓ root/usr/share/luci/menu.d/iptest.json → root/usr/share/luci/menu.d/luci-app-ipthrottle.json
✓ root/usr/share/rpcd/acl.d/luci-app-iptest.json → root/usr/share/rpcd/acl.d/luci-app-ipthrottle.json
✓ root/www/luci-static/resources/view/iptest.js → root/www/luci-static/resources/view/ipthrottle.js
✓ files/etc/cron.d/iptest → files/etc/cron.d/ipthrottle
✓ files/etc/uci-defaults/50-iptest → files/etc/uci-defaults/50-ipthrottle
✓ files/etc/hotplug.d/iface/90-iptest → files/etc/hotplug.d/iface/90-ipthrottle
```

### 2. 代码引用替换 ✅
```
✓ UCI 配置: config iptest → config ipthrottle
✓ UCI 调用: uci show iptest → uci show ipthrottle
✓ 临时文件: /tmp/iptest_* → /tmp/ipthrottle_*
✓ 日志标签: iptest-* → ipthrottle-*
✓ 变量名: IPT_TEST_* → IPT_*
✓ nftables 表: table ip iptest → table ip ipthrottle
```

### 3. 文档更新 ✅
```
✓ DESIGN.md - 所有技术文档引用
✓ DEVELOPMENT.md - 开发文档引用
✓ CHANGELOG.md - 变更记录
✓ TODO.md - 待办清单
✓ PROJECT_SUMMARY.md - 项目总结
✓ README.md - 用户手册（品牌名 IPThrottle）
```

### 4. Makefile 更新 ✅
```makefile
PKG_NAME:=ipthrottle
Package/ipthrottle
```

### 5. LuCI 配置更新 ✅
```json
// luci-app-ipthrottle.json
{
  "admin/network/ipthrottle": {
    "title": "IPThrottle",
    ...
  }
}
```

## 三、文件结构确认

### 核心脚本 (`/usr/lib/ipthrottle/`)
- `core.sh` - 核心逻辑（TC/HTB 管理）
- `ip.sh` - IP 地址解析
- `wan.sh` - WAN 接口管理
- `schedule.sh` - 时间计划管理
- `ipthrottle-daemon` - 配置文件监控

### 服务与配置
- `/usr/sbin/ipthrottle` - CLI 工具
- `/etc/init.d/ipthrottle` - 服务脚本
- `/etc/config/ipthrottle` - UCI 配置模板
- `/etc/hotplug.d/iface/90-ipthrottle` - 网络接口热插拔
- `/etc/cron.d/ipthrottle` - 定期调度检查
- `/etc/uci-defaults/50-ipthrottle` - 默认配置

### LuCI Web 界面
- `/www/luci-static/resources/view/ipthrottle.js` - 前端视图
- `/usr/share/luci/menu.d/luci-app-ipthrottle.json` - 菜单定义
- `/usr/share/rpcd/acl.d/luci-app-ipthrottle.json` - ACL 权限

## 四、命令示例

```bash
# 服务管理
/etc/init.d/ipthrottle start
/etc/init.d/ipthrottle stop
/etc/init.d/ipthrottle restart
/etc/init.d/ipthrottle reload

# CLI 操作
ipthrottle status
ipthrottle reload
ipthrottle clear

# 查看日志
logread | grep ipthrottle
```

## 五、测试结果

✅ Shell 脚本语法测试通过  
✅ 文件引用检查通过  
✅ 命名规范统一验证通过  

## 六、注意事项

1. **配置兼容性**: 如果从旧版 `iptest` 升级，需要手动迁移 `/etc/config/iptest` 到 `/etc/config/ipthrottle`
2. **服务依赖**: 其他依赖此插件的脚本需要更新引用为 `ipthrottle`
3. **LuCI 缓存**: 更新后需要清除 LuCI 缓存：`rm -rf /tmp/luci-*`

## 七、下一步

- ✅ 代码重构完成
- ✅ 文件重命名完成
- ✅ 文档更新完成
- ⏭ 建议在实际设备上测试
- ⏭ 建议创建升级脚本处理配置迁移
