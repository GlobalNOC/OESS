/**
 * @typedef Peering
 * @property {integer} asn - BGP ASN number
 * @property {string} key - BGP authentication key
 * @property {string} oessPeerIP - IP Address of the OESS peering address
 * @property {integer} yourPeerIP - IP Address of the remote peering address
 */

/**
 * @typedef Endpoint
 * @property {integer} bandwidth - Maximum bandwidth allowed
 * @property {string} [interface=undefined] - Name of interface
 * @property {string} [entity=undefined] - Name of entity
 * @property {string} [node=undefined] - Name of node
 * @property {integer} tag - VLAN number
 * @property {integer} [cloud_account_id=undefined] - Cloud account owner for cloud interconnect
 * @property {boolean} [jumbo] - Jumbo frames enabled
 * @property {Peering[]} peerings - Peers on this endpoint
 */

/**
 * provisionVRF provisions a new L3VPN. Returns the vrf identifier on
 * success or null if an error occurred.
 *
 * @param {integer} workgroupID - Identifier of the current workgroup
 * @param {string} name - Unique human readable ID
 * @param {string} description - Circuit name as shown on frontend
 * @param {Endpoint[]} endpoints - An array of endpoint objects
 * @param {integer} provisionTime - When the circuit should be activated
 * @param {integer} removeTime - When the circuit should be deactivated
 * @param {integer} [vrfID=-1] - Identifier of VRF to modify
 */
async function provisionVRF(workgroupID, name, description, endpoints, provisionTime, removeTime, vrfID=-1) {
  let url = '[% path %]services/vrf.cgi';

  let form = new FormData();
  form.append('method', 'provision');
  form.append('name', name);
  form.append('description', description);
  form.append('local_asn', 1);
  form.append('workgroup_id', workgroupID);
  form.append('provision_time', provisionTime);
  form.append('remove_time', removeTime);
  form.append('vrf_id', vrfID);

  endpoints.forEach(function(endpoint) {
    let e = {
      vrf_endpoint_id: endpoint.vrf_endpoint_id,
      bandwidth: endpoint.bandwidth,
      tag:       endpoint.tag,
      jumbo:     (endpoint.jumbo) ? 1 : 0,
      peers:     [],
      cloud_account_id: endpoint.cloud_account_id
    };

    if (endpoint.cloud_gateway_type !== null) {
      e['cloud_gateway_type'] = endpoint.cloud_gateway_type;
    }

    if ('entity_id' in endpoint && endpoint.name === 'TBD' && endpoint.node === 'TBD') {
      e['entity'] = endpoint.entity;
    } else {
      e['interface'] = endpoint.interface;
      e['node']      = endpoint.node;
      e['entity']    = endpoint.entity;
    }

    if (endpoint.peers.length < 1) {
      throw('At least one peering on each endpoint must be specified.');
    }

    endpoint.peers.forEach(function(p) {
      e.peers.push({
        vrf_ep_peer_id: p.vrf_ep_peer_id,
        peer_asn: p.peer_asn,
        md5_key:  p.md5_key,
        local_ip: p.local_ip,
        peer_ip:  p.peer_ip,
        version:  p.ip_version,
        bfd:      (p.bfd) ? 1 : 0
      });
    });

    form.append('endpoint', JSON.stringify(e));
  });

  const resp = await fetch(url, {method: 'post', credentials: 'include', body: form});
  const data = await resp.json();

  if ('error_text' in data) throw(data.error_text);

  if (typeof data.results.success === 'undefined' || typeof data.results.vrf_id === 'undefined') {
    throw("Unexpected response format received from server.");
  }

  return parseInt(data.results.vrf_id);
}

async function getVRF(workgroupID, vrfID) {
  let url = `[% path %]services/vrf.cgi?method=get_vrf_details&vrf_id=${vrfID}&workgroup_id=${workgroupID}`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    console.log(data);
    return data.results[0];
  } catch(error) {
    console.log('Failure occurred in getVRF.');
    console.log(error);
    return null;
  }
}

async function deleteVRF(workgroupID, vrfID) {
  let url = `[% path %]services/vrf.cgi?method=remove&vrf_id=${vrfID}&workgroup_id=${workgroupID}`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    console.log(data);
    return data.results;
  } catch(error) {
    console.log('Failure occurred in deleteVRF.');
    console.log(error);
    return null;
  }
}

async function getVRFs(workgroupID) {
  let url = `[% path %]services/vrf.cgi?method=get_vrfs&workgroup_id=${workgroupID}`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    console.log(data);
    return data;
  } catch(error) {
    console.log('Failure occurred in getVRF.');
    console.log(error);
    return null;
  }
}
