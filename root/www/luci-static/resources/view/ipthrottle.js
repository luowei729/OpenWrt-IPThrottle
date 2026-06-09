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

		// ==========================================
		// 规则列表（GridSection）
		// 只显示关键字段，避免列太多导致显示不全
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

		// 内网IP地址
		o = s.option(form.DynamicList, 'ip_entry', _('内网IP地址'));
		o.rmempty = false;
		o.placeholder = '192.168.1.100';
		o.datatype = 'ip4addr("true")';

		// 上传限速
		o = s.option(form.Value, 'upload_kbps', _('上传(Kbps)'));
		o.rmempty = false;
		o.datatype = 'uinteger';
		o.placeholder = '1024';
		o.default = '1024';

		// 下载限速
		o = s.option(form.Value, 'download_kbps', _('下载(Kbps)'));
		o.rmempty = false;
		o.datatype = 'uinteger';
		o.placeholder = '4096';
		o.default = '4096';

		// 生效时间（列表页只显示类型）
		o = s.option(form.ListValue, 'schedule_type', _('生效时间'));
		o.value('always', _('全天生效'));
		o.value('weekly', _('自定义时间'));
		o.default = 'always';
		o.rmempty = false;

		// ==========================================
		// 以下为编辑表单中的详细字段（不在列表中显示）
		// 使用 modal 编辑时显示
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
		o.modalonly = true; // 仅在编辑弹窗中显示

		// IP范围（可选）
		o = s.option(form.Value, 'ip_range', _('IP范围(可选)'));
		o.placeholder = '192.168.1.100-192.168.1.200';
		o.rmempty = true;
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

		// ==========================================
		// 自定义时间设置（modalonly，仅编辑时显示）
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

		// 结束时间
		o = s.option(form.Value, 'schedule_end', _('结束时间'));
		o.depends('schedule_type', 'weekly');
		o.rmempty = true;
		o.placeholder = '22:00';
		o.modalonly = true;

		return m.render();
	}
});
