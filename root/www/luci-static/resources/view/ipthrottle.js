'use strict';
'require view';
'require form';
'require uci';

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('ipthrottle')
		]);
	},

	render: function() {
		var m, s, o;

		m = new form.Map('ipthrottle', _('IP限速设置'),
			_('配置内网IP的限速规则'));

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

		// WAN线路选择
		o = s.option(form.ListValue, 'wan_mask', _('网络接口'));
		o.value('all', _('所有接口'));
		o.value('eth0.2', _('WAN1'));
		o.value('eth1.2', _('WAN2'));
		o.value('eth2.2', _('WAN3'));
		o.value('eth3.2', _('WAN4'));
		o.default = 'all';
		o.rmempty = false;

		// 内网IP地址（后端字段名: ip_entry）
		o = s.option(form.DynamicList, 'ip_entry', _('内网IP地址'));
		o.rmempty = false;
		o.placeholder = '192.168.1.100';
		o.datatype = 'ip4addr("true")';

		// IP范围（可选，后端直接读取 ip_range）
		o = s.option(form.Value, 'ip_range', _('IP范围(可选)'));
		o.placeholder = '192.168.1.100-192.168.1.200';
		o.rmempty = true;

		// 协议选择（后端字段名: proto）
		o = s.option(form.ListValue, 'proto', _('协议'));
		o.value('any', _('全部协议'));
		o.value('tcp', _('TCP'));
		o.value('udp', _('UDP'));
		o.value('tcp+udp', _('TCP+UDP'));
		o.default = 'any';
		o.rmempty = false;

		// 限速模式（后端字段名: mode）
		o = s.option(form.ListValue, 'mode', _('限速模式'));
		o.value('independent', _('独立限速(每个IP独立限速)'));
		o.value('shared', _('共享限速(所有IP共享带宽)'));
		o.default = 'independent';
		o.rmempty = false;

		// 上传限速（后端字段名: upload_kbps，单位 Kbps）
		o = s.option(form.Value, 'upload_kbps', _('上传限速(Kbps)'));
		o.rmempty = false;
		o.datatype = 'uinteger';
		o.placeholder = '1024';
		o.default = '1024';
		o.description = _('单位: Kbps (1 Mbps = 1024 Kbps)');

		// 下载限速（后端字段名: download_kbps，单位 Kbps）
		o = s.option(form.Value, 'download_kbps', _('下载限速(Kbps)'));
		o.rmempty = false;
		o.datatype = 'uinteger';
		o.placeholder = '4096';
		o.default = '4096';
		o.description = _('单位: Kbps (1 Mbps = 1024 Kbps)');

		// 优先级（后端字段名: priority）
		o = s.option(form.Value, 'priority', _('优先级'));
		o.rmempty = false;
		o.datatype = 'uinteger';
		o.placeholder = '10';
		o.default = '10';
		o.description = _('数字越小优先级越高 (1-99)');

		// ==========================================
		// 生效时间设置
		// ==========================================

		// 时间类型选择：全天生效 / 自定义时间
		o = s.option(form.ListValue, 'schedule_type', _('生效时间'));
		o.value('always', _('全天生效(默认)'));
		o.value('weekly', _('自定义时间'));
		o.default = 'always';
		o.rmempty = false;
		o.description = _('选择"全天生效"则规则始终生效；选择"自定义时间"可指定每周哪几天、几点到几点生效');

		// 生效星期 - 使用多个独立 Flag 复选框，兼容性最好
		// 后端会将这些合并为 schedule_days list
		o = s.option(form.Flag, 'schedule_day_mon', _('周一'));
		o.depends('schedule_type', 'weekly');
		o.rmempty = true;
		o.default = '0';

		o = s.option(form.Flag, 'schedule_day_tue', _('周二'));
		o.depends('schedule_type', 'weekly');
		o.rmempty = true;
		o.default = '0';

		o = s.option(form.Flag, 'schedule_day_wed', _('周三'));
		o.depends('schedule_type', 'weekly');
		o.rmempty = true;
		o.default = '0';

		o = s.option(form.Flag, 'schedule_day_thu', _('周四'));
		o.depends('schedule_type', 'weekly');
		o.rmempty = true;
		o.default = '0';

		o = s.option(form.Flag, 'schedule_day_fri', _('周五'));
		o.depends('schedule_type', 'weekly');
		o.rmempty = true;
		o.default = '0';

		o = s.option(form.Flag, 'schedule_day_sat', _('周六'));
		o.depends('schedule_type', 'weekly');
		o.rmempty = true;
		o.default = '0';

		o = s.option(form.Flag, 'schedule_day_sun', _('周日'));
		o.depends('schedule_type', 'weekly');
		o.rmempty = true;
		o.default = '0';

		// 开始时间（仅当 schedule_type=weekly 时显示）
		o = s.option(form.Value, 'schedule_start', _('开始时间'));
		o.depends('schedule_type', 'weekly');
		o.rmempty = true;
		o.placeholder = '08:00';
		o.description = _('格式 HH:MM，不填默认 00:00');

		// 结束时间（仅当 schedule_type=weekly 时显示）
		o = s.option(form.Value, 'schedule_end', _('结束时间'));
		o.depends('schedule_type', 'weekly');
		o.rmempty = true;
		o.placeholder = '22:00';
		o.description = _('格式 HH:MM，不填默认 23:59');

		return m.render();
	}
});
