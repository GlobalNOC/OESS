/**
 * getInterfaces returns a list of all interfaces on nodeName that may
 * be used for provisioning by workgroupID.
 *
 * @param {integer} workgroupID - Identifier of the current workgroup
 * @param {string} name - Unique human readable ID
 * @param {string} description - Circuit name as shown on frontend
 * @param {object[]} endpoints - An array of endpoint objects
 * @param {integer} provisionTime - When the circuit should be activated
 * @param {integer} removeTime - When the circuit should be deactivated
 * @param {integer} [vrfID=-1] - Identifier of VRF to modify
 *
 * Endpoint object:
 * {
 *   bandwidth: 10,
 *   interface: 'xe-7/0/2',
 *   node:      'mx960-1.sdn-test.grnoc.iu.edu',
 *   tag:       300,
 *   peerings: [{
 *     asn: 10,
 *     key: '',
 *     oessPeerIP: '198.162.1.1/24',
 *     yourPeerIP: '198.162.1.2/24'
 *   }]
 * }
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
      form.append('endpoint', encodeURIComponent(JSON.stringify(e)));
    });

    try {
      const resp = await fetch(url, {method: 'post', credentials: 'include', body: form});
      const data = await resp.json();
      return data.results;
    } catch(error) {
      console.log('Failure occurred in get_node_interfaces.');
      console.log(error);
      return [];
    }
}
