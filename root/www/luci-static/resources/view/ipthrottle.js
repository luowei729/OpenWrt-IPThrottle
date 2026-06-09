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

		// 内网IP地址
		o = s.option(form.DynamicList, 'ip_list', _('内网IP地址'));
		o.rmempty = false;
		o.placeholder = '192.168.1.100';
		o.datatype = 'ip4addr("true")';

		// IP范围
		o = s.option(form.Value, 'ip_range', _('IP范围(可选)'));
		o.placeholder = '192.168.1.100-192.168.1.200';
		o.rmempty = true;

		// 协议选择
		o = s.option(form.ListValue, 'protocol', _('协议'));
		o.value('all', _('全部协议'));
		o.value('tcp', _('TCP'));
		o.value('udp', _('UDP'));
		o.value('tcp+udp', _('TCP+UDP'));
		o.default = 'all';
		o.rmempty = false;

		// 限速模式
		o = s.option(form.ListValue, 'limite_mode', _('限速模式'));
		o.value('independ', _('独立限速(每个IP独立限速)'));
		o.value('share', _('共享限速(所有IP共享带宽)'));
		o.default = 'independ';
		o.rmempty = false;

		// 上传限速
		o = s.option(form.Value, 'up_mbps', _('上传限速(Mbps)'));
		o.rmempty = false;
		o.datatype = 'uinteger';
		o.placeholder = '100';
		o.default = '100';

		// 下载限速
		o = s.option(form.Value, 'down_mbps', _('下载限速(Mbps)'));
		o.rmempty = false;
		o.datatype = 'uinteger';
		o.placeholder = '1000';
		o.default = '1000';

		// 优先级
		o = s.option(form.Value, 'priority_order', _('优先级'));
		o.rmempty = false;
		o.datatype = 'uinteger';
		o.placeholder = '100';
		o.default = '100';
		o.description = _('数字越小优先级越高');

		// 时间限制
		o = s.option(form.DynamicList, 'time_condition', _('生效时间'));
		o.rmempty = true;
		o.placeholder = '[{"d":[1,2,3,4,5],"s":"08:00","e":"22:00"}]';
		o.description = _('JSON格式：d=星期(0周日,1-6周一到周六), s=开始时间, e=结束时间');

		return m.render();
	}
});
