'use strict';
'require view';
'require form';
'require uci';

	return view.extend({
		load: function() {
			// ==========================================
			// 缓存破坏机制
			// 原因: LuCI 框架用 {cache:true} 加载 JS 模块，版本号绑定 luci.js 编译时间戳，
			//       更新插件文件不会改变版本号，导致浏览器一直返回缓存。
			// 方案: postinstall 时生成新时间戳写入静态文件，JS 加载时对比版本号，
			//       不一致则强制刷新页面，确保用户看到最新版。
			// ==========================================
			var versionUrl = '/luci-static/resources/view/ipthrottle.version?t=' + Date.now();
			var storageKey = 'ipthrottle_version';
			
			return fetch(versionUrl)
				.then(function(res) { return res.text(); })
				.then(function(serverVersion) {
					serverVersion = serverVersion.trim();
					var localVersion = localStorage.getItem(storageKey);
					
					// 版本号不一致 -> 插件已更新，强制刷新
					if (localVersion && localVersion !== serverVersion) {
						// 清除 LuCI 模块缓存（内存中的 classes 对象）
						if (window.L && window.L.classes) {
							delete window.L.classes['view.ipthrottle'];
						}
						// 更新本地版本号
						localStorage.setItem(storageKey, serverVersion);
						// 强制刷新页面，绕过浏览器 HTTP 缓存
						window.location.reload(true);
						// 返回一个永不 resolve 的 Promise，阻止页面继续渲染
						return new Promise(function() {});
					}
					
					// 首次访问或版本一致，记录版本号
					localStorage.setItem(storageKey, serverVersion);
					
					// 正常加载 UCI 配置
					return uci.load('ipthrottle');
				})
				.catch(function() {
					// 版本文件读取失败（可能是旧版插件），继续正常加载
					return uci.load('ipthrottle');
				});
		},

	render: function() {
		var m, s, o;

		// 注入CSS：让placeholder文字颜色变暗，避免太亮太显眼
		var style = document.createElement('style');
		style.textContent = '::placeholder { color: #999 !important; opacity: 1 !important; }';
		document.head.appendChild(style);

		m = new form.Map('ipthrottle', _('IP限速设置'),
			_('配置内网IP的限速规则'));

		// ==========================================
		// 规则列表（GridSection）- 精简版
		// ==========================================
		s = m.section(form.GridSection, 'rule', _('规则列表'));
		s.addremove = true;
		s.anonymous = true;
		s.sortable  = true;

		// 启用开关
		o = s.option(form.Flag, 'enabled', _('启用'));
		o.rmempty = false;
		o.default = '1';

		// 规则名称
		o = s.option(form.Value, 'name', _('规则名称'));
		o.rmempty = false;
		o.placeholder = '例：客厅电视';

		// 内网IP地址（支持单IP和IP范围，如 192.168.1.100 或 192.168.1.100-192.168.1.200）
		o = s.option(form.DynamicList, 'ip_entry', _('内网IP'));
		o.rmempty = false;
		o.placeholder = '192.168.1.100 或 192.168.1.100-200';
		o.description = _('支持单个IP或IP范围（用-连接），每行一个');

		// 上传限速 - 标题带单位
		o = s.option(form.Value, 'upload_kbps', _('上传<br/><small style="color:#999">Kbps</small>'));
		o.rmempty = false;
		o.datatype = 'uinteger';
		o.placeholder = '1024';
		o.default = '1024';

		// 下载限速 - 标题带单位
		o = s.option(form.Value, 'download_kbps', _('下载<br/><small style="color:#999">Kbps</small>'));
		o.rmempty = false;
		o.datatype = 'uinteger';
		o.placeholder = '4096';
		o.default = '4096';

		// 生效时间
		o = s.option(form.ListValue, 'schedule_type', _('生效时间'));
		o.value('always', _('全天'));
		o.value('weekly', _('自定义'));
		o.default = 'always';
		o.rmempty = false;

		// ==========================================
		// 编辑弹窗中的详细字段（modalonly）
		// ==========================================

		// WAN线路选择
		o = s.option(form.ListValue, 'wan_mask', _('网络接口'));
		o.value('all', _('所有接口'));
		o.value('eth0.2', _('WAN1'));
		o.value('eth1.2', _('WAN2'));
		o.value('eth2.2', _('WAN3'));
		o.value('eth3.2', _('WAN4'));
		o.default = 'all';
		o.rmempty = false;
		o.modalonly = true;

		// 协议选择
		o = s.option(form.ListValue, 'proto', _('协议'));
		o.value('any', _('全部协议'));
		o.value('tcp', _('TCP'));
		o.value('udp', _('UDP'));
		o.value('tcp+udp', _('TCP+UDP'));
		o.default = 'any';
		o.rmempty = false;
		o.modalonly = true;

		// 限速模式
		o = s.option(form.ListValue, 'mode', _('限速模式'));
		o.value('independent', _('独立限速(每个IP独立)'));
		o.value('shared', _('共享限速(所有IP共享)'));
		o.default = 'independent';
		o.rmempty = false;
		o.modalonly = true;

		// 优先级
		o = s.option(form.Value, 'priority', _('优先级'));
		o.rmempty = false;
		o.datatype = 'uinteger';
		o.placeholder = '10';
		o.default = '10';
		o.modalonly = true;
		o.description = _('数字越小优先级越高 (1-99)');

		// ==========================================
		// 自定义时间设置（modalonly）
		// ==========================================

		// 生效星期 - 使用独立 Flag 复选框
		o = s.option(form.Flag, 'schedule_day_mon', _('周一'));
		o.depends('schedule_type', 'weekly');
		o.rmempty = true;
		o.default = '0';
		o.modalonly = true;

		o = s.option(form.Flag, 'schedule_day_tue', _('周二'));
		o.depends('schedule_type', 'weekly');
		o.rmempty = true;
		o.default = '0';
		o.modalonly = true;

		o = s.option(form.Flag, 'schedule_day_wed', _('周三'));
		o.depends('schedule_type', 'weekly');
		o.rmempty = true;
		o.default = '0';
		o.modalonly = true;

		o = s.option(form.Flag, 'schedule_day_thu', _('周四'));
		o.depends('schedule_type', 'weekly');
		o.rmempty = true;
		o.default = '0';
		o.modalonly = true;

		o = s.option(form.Flag, 'schedule_day_fri', _('周五'));
		o.depends('schedule_type', 'weekly');
		o.rmempty = true;
		o.default = '0';
		o.modalonly = true;

		o = s.option(form.Flag, 'schedule_day_sat', _('周六'));
		o.depends('schedule_type', 'weekly');
		o.rmempty = true;
		o.default = '0';
		o.modalonly = true;

		o = s.option(form.Flag, 'schedule_day_sun', _('周日'));
		o.depends('schedule_type', 'weekly');
		o.rmempty = true;
		o.default = '0';
		o.modalonly = true;

		// 开始时间
		o = s.option(form.Value, 'schedule_start', _('开始时间'));
		o.depends('schedule_type', 'weekly');
		o.rmempty = true;
		o.placeholder = '08:00';
		o.modalonly = true;
		o.description = _('格式 HH:MM，不填默认 00:00');

		// 结束时间
		o = s.option(form.Value, 'schedule_end', _('结束时间'));
		o.depends('schedule_type', 'weekly');
		o.rmempty = true;
		o.placeholder = '22:00';
		o.modalonly = true;
		o.description = _('格式 HH:MM，不填默认 23:59');

		return m.render();
	}
});
