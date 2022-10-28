function NewEndpoint(endpoint) {
  let t = document.querySelector('#template-l2-endpoint');
  let e = document.importNode(t.content, true);

  if (endpoint.state == 'in-review') {
    e.querySelector('.panel').classList.remove('panel-default')
    e.querySelector('.panel').classList.add('panel-warning')
    e.querySelector('.panel-heading').innerHTML = 'This endpoint is pending approval. Please contact <a href="mailto: [% approval_email %]">[% approval_email %]</a> for additional information.';
  } else {
    e.querySelector('.panel-heading').style.display = 'none';
  }

  e.querySelector('.l2vpn-entity').innerHTML = endpoint.entity || 'NA';
  e.querySelector('.l2vpn-node').innerHTML = endpoint.node;
  e.querySelector('.l2vpn-interface').innerHTML = endpoint.interface;
  e.querySelector('.l2vpn-interface-description').innerHTML = endpoint.description;
  e.querySelector('.l2vpn-tag').innerHTML = endpoint.tag;
  e.querySelector('.l2vpn-inner-tag').innerHTML = endpoint.inner_tag || null;
  e.querySelector('.l2vpn-bandwidth').innerHTML = (endpoint.bandwidth == null || endpoint.bandwidth == 0) ? 'Unlimited' : `${endpoint.bandwidth} Mb/s`;
  e.querySelector('.l2vpn-graph').setAttribute('src', `[% g_l2_port %]&from=now-1h&to=now&var-node=${endpoint.node}&var-interface=${endpoint.interface}.${endpoint.tag}&refresh=30s`);

  if ('mtu' in endpoint) {
    e.querySelector('.l2vpn-mtu').innerHTML = endpoint.mtu;
  } else {
    e.querySelector('.l2vpn-mtu').innerHTML = (endpoint.jumbo) ? 'Jumbo' : 'Standard';
  }

  if (endpoint.inner_tag === undefined || endpoint.inner_tag === null || endpoint.inner_tag === '') {
    Array.from(e.querySelectorAll('.d1q')).map(e => e.style.display = 'block');
    Array.from(e.querySelectorAll('.qnq')).map(e => e.style.display = 'none');
  } else {
    Array.from(e.querySelectorAll('.d1q')).map(e => e.style.display = 'none');
    Array.from(e.querySelectorAll('.qnq')).map(e => e.style.display = 'block');
  }

  e.querySelector('.l2vpn-endpoint-buttons').style.display = (endpoint.editable) ? 'block' : 'none';

  e.querySelector('.l2vpn-modify-button').addEventListener('click', function(e) {
    modal.display(endpoint);
  });

  e.querySelector('.l2vpn-delete-button').addEventListener('click', function(e) {
    state.deleteEndpoint(endpoint.index);
    update();
  });

  return e;
}
