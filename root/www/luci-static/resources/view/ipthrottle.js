'use strict';
'require view';
'require form';
'require uci';
'require fs';
'require ui';

	return view.extend({
		load: function() {
			// ==========================================
			// 缓存破坏机制 v2（彻底解决浏览器刷新看不到新 UI 的问题）
			//
			// 问题根因:
			//   1. LuCI 用 RequireJS {cache:true} 加载 JS 模块，模块 URL 绑定 luci.js 编译时间戳
			//   2. 更新插件文件不改变时间戳 → 浏览器从 HTTP 缓存返回旧 JS
			//   3. window.location.reload(true) 在现代浏览器已废弃，不能可靠绕过缓存
			//   4. 即使 reload 成功，RequireJS 内存缓存仍可能返回旧模块
			//
			// 方案:
			//   postinstall 时生成新时间戳写入 ipthrottle.version 文件，
			//   JS 加载时 fetch 该文件（加 ?t= 防止自身被缓存），
			//   检测版本不一致时，用 location.href 跳转到带 _v 参数的新 URL，
			//   浏览器对全新 URL 不会使用任何缓存（HTTP 缓存、Service Worker 缓存、内存缓存）。
			// ==========================================
			var versionUrl = '/luci-static/resources/view/ipthrottle.version?t=' + Date.now();
			var storageKey = 'ipthrottle_version';

			// 并行加载版本检查和 UCI 配置
			// 实现原因: 同时获取版本信息和服务状态，减少等待时间
			var statusPromise = fs.exec('/usr/sbin/ipthrottle', ['status'])
				.then(function(res) { return res.stdout || ''; })
				.catch(function() { return ''; });

			return fetch(versionUrl)
				.then(function(res) { return res.text(); })
				.then(function(serverVersion) {
					serverVersion = serverVersion.trim();
					var localVersion = localStorage.getItem(storageKey);

					// 版本号不一致 → 插件已更新，需要强制加载新代码
					if (localVersion && localVersion !== serverVersion) {
						// 1. 先更新 localStorage 版本号
						// 原因: 新页面加载后会读到新版本号，避免再次触发刷新循环
						localStorage.setItem(storageKey, serverVersion);

						// 2. 清除 RequireJS 内存中的模块缓存
						// 原因: LuCI 用 {cache:true} 加载模块，旧模块在内存中缓存
						if (window.L && window.L.classes) {
							delete window.L.classes['view.ipthrottle'];
						}
						// 清除 RequireJS 定义的模块，下次 require 时会重新加载
						if (window.require && window.require.s) {
							var moduleKey = 'view/ipthrottle';
							// 删除 RequireJS 模块缓存和定义记录
							delete window.require.s.contexts._._defined[moduleKey];
							delete window.require.s.contexts._._loaded[moduleKey];
						}

						// 3. 用 location.href 跳转到带 _v 参数的新 URL
						// 原因: reload(true) 已废弃不可靠；带新查询参数的 URL 是全新资源，
						//       浏览器不会使用任何缓存（HTTP 缓存 / Service Worker / 内存缓存），
						//       这是唯一能彻底绕过所有缓存层的可靠方法。
						var url = window.location.pathname;
						// 去掉旧的 _v 参数（如果存在）
						url = url.replace(/[?&]_v=[^&]+/, '');
						// 添加新 _v 参数
						url += '?_v=' + serverVersion;
						window.location.href = url;

						// 返回永不 resolve 的 Promise，阻止页面继续渲染旧内容
						return new Promise(function() {});
					}

					// 首次访问或版本一致，记录版本号
					localStorage.setItem(storageKey, serverVersion);

					// 正常加载 UCI 配置，同时等待状态查询完成
					return Promise.all([
						uci.load('ipthrottle'),
						statusPromise
					]).then(function(results) {
						return { status: results[1] };
					});
				})
				.catch(function() {
					// 版本文件读取失败（可能是旧版插件），继续正常加载
					return uci.load('ipthrottle').then(function() {
						return { status: '' };
					});
				});
		},

	render: function(data) {
		var m, s, o;
		var statusText = (data && data.status) ? data.status : '';

		// 注入CSS：让placeholder文字颜色变暗，避免太亮太显眼
		// 同时定义状态栏样式
		var style = document.createElement('style');
		style.textContent = '::placeholder { color: #999 !important; opacity: 1 !important; }' +
			'.ipthrottle-status-bar { padding: 10px 15px; margin-bottom: 15px; border-radius: 5px; font-weight: bold; font-size: 14px; }' +
			'.ipthrottle-status-running { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }' +
			'.ipthrottle-status-stopped { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }';
		document.head.appendChild(style);

		m = new form.Map('ipthrottle', _('IPThrottle - 内网IP限速'),
			_('按IP限制上传/下载带宽，支持独立/共享限速、IP范围、协议过滤、多WAN和时间计划'));

		// ==========================================
		// 运行状态横幅
		// 实现原因: 用户进入页面时一眼就能看到服务是否在运行，
		//          避免配置了规则但服务未启动导致限速不生效的问题。
		// ==========================================
		var statusSection = m.section(form.NamedSection, '__status__', '');
		statusSection.render = function() {
			var div = E('div', { 'class': 'ipthrottle-status-bar' });
			if (statusText.indexOf('running') !== -1) {
				div.className += ' ipthrottle-status-running';
				// 提取规则数量
				var ruleMatch = statusText.match(/Active IP throttle rules:\s*(\d+)/);
				var ruleCount = ruleMatch ? ruleMatch[1] : '?';
				div.appendChild(E('span', {}, '✅ IPThrottle ' + _('运行中') + ' — ' + _('活跃规则') + ': ' + ruleCount));
			} else {
				div.className += ' ipthrottle-status-stopped';
				div.appendChild(E('span', {}, '❌ IPThrottle ' + _('未运行') + ' — ' + _('请检查是否启用规则')));
			}
			return div;
		};

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

		// ==========================================
		// 优先级（列表+弹窗均显示）
		// 实现原因: 用户在首页规则列表中需要直观看到每条规则的优先级，
		//          方便调整规则执行顺序（数字越小优先级越高）。
		// 注意: 移除 modalonly 使其同时在 GridSection 列表和编辑弹窗中显示。
		// ==========================================
		o = s.option(form.Value, 'priority', _('优先级'));
		o.rmempty = false;
		o.datatype = 'uinteger';
		o.placeholder = '10';
		o.default = '10';

		// 规则名称
		o = s.option(form.Value, 'name', _('规则名称'));
		o.rmempty = false;
		o.placeholder = '例：客厅电视';

		// 内网IP地址（支持单IP和IP范围，如 192.168.1.100 或 192.168.1.100-192.168.1.200）
		o = s.option(form.DynamicList, 'ip_entry', _('内网IP'));
		o.rmempty = false;
		o.placeholder = '192.168.1.100 或 192.168.1.100-200';

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
