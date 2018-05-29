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
 * @property {string} interface - Name of interface
 * @property {string} node - Name of node
 * @property {integer} tag - VLAN number
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
  let url = 'services/provisioning.cgi';

  let form = new FormData();
  form.append('method', 'provision_vrf');
  form.append('name', encodeURIComponent(name));
  form.append('description', encodeURIComponent(description));
  form.append('local_asn', 1);
  form.append('workgroup_id', workgroupID);
  form.append('provision_time', provisionTime);
  form.append('remove_time', removeTime);
  form.append('vrf_id', vrfID);

  endpoints.forEach(function(endpoint) {
    let e = {
      bandwidth: endpoint.bandwidth,
      interface: endpoint.interface,
      node:      endpoint.node,
      tag:       endpoint.tag,
      peerings:  []
    };

    endpoint.peerings.forEach(function(p) {
      e.peerings.push({
        asn: p.asn,
        key: p.key,
        local_ip: p.oessPeerIP,
        peer_ip:  p.yourPeerIP
      });
    });

    form.append('endpoint', JSON.stringify(e));
  });

  try {
    const resp = await fetch(url, {method: 'post', credentials: 'include', body: form});
    const data = await resp.json();

    if (typeof data.results.success !== undefined && data.results.success === 1) {
      return parseInt(data.results.vrf_id);
    }
  } catch(error) {
    console.log('Failure occurred in provisionVRF.');
    console.log(error);
  }

  return null;
}

async function getVRF(vrfID) {
  let url = 'services/admin.cgi';
}
