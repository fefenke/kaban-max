import { validPreRoutingResolveDomains } from '../../../validators/validatePreRoutingResolve';

export function addPreRoutingResolveOptions(section: CBISection) {
  const mode = section.option(
    form.ListValue,
    'pre_routing_resolve_mode',
    _('Resolve domains before routing'),
    _(
      'Resolve real IP addresses through main DNS before applying section rules. Rules keep their priority: an IP rule wins only when the resolved address matches.',
    ),
  );
  mode.value('disabled', _('Disabled'));
  mode.value('all', _('All domains'));
  mode.value('selected', _('Selected domains'));
  mode.default = 'disabled';
  mode.rmempty = false;

  const domains = section.option(
    form.TextValue,
    'pre_routing_resolve_domains',
    _('Domains to resolve before routing'),
    _(
      'example.org includes subdomains; full:example.org matches only that domain. Separate entries with a new line, comma or space.',
    ),
  );
  domains.depends('pre_routing_resolve_mode', 'selected');
  domains.rows = 5;
  domains.placeholder = 'example.org\nfull:only.example.org';
  domains.validate = (_sectionId: string, value: string) =>
    validPreRoutingResolveDomains(`${value || ''}`)
      ? true
      : _('Enter at least one valid domain or full:domain');
}
