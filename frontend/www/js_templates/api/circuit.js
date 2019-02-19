/**
 * provisionCircuit provisions a new L3VPN. Returns the vrf identifier on
 * success or null if an error occurred.
 *
 * @param {integer} workgroupID - Identifier of the current workgroup
 * @param {string} description - Circuit name as shown on frontend
 * @param {Endpoint[]} endpoints - An array of endpoint objects
 * @param {integer} start - When the circuit should be activated
 * @param {integer} end - When the circuit should be deactivated
 * @param {integer} [circuitID=-1] - Identifier of VRF to modify
 */
async function provisionCircuit(workgroupID, description, endpoints, staticMAC, start=-1, end=-1, circuitID=-1) {
  let url = '[% path %]services/provisioning.cgi';

  let form = new FormData();
  form.append('method', 'provision_circuit');
  form.append('workgroup_id', workgroupID);
  form.append('description', description);
  form.append('static_mac', staticMAC);
  form.append('provision_time', start);
  form.append('remove_time', end);
  form.append('restore_to_primary', 0);
  form.append('type', 'mpls');
  form.append('state', 'active');
  form.append('circuit_id', circuitID);

  let bandwidth = 0;
  endpoints.forEach(function(endpoint) {
    bandwidth = (endpoint.bandwidth > bandwidth) ? endpoint.bandwidth : bandwidth;

    let e = {
      bandwidth: endpoint.bandwidth,
      tag:       endpoint.tag,
      cloud_account_id: endpoint.cloud_account_id
    };

    if ('entity_id' in endpoint && endpoint.name === 'TBD' && endpoint.interface === 'TBD') {
      e['entity'] = endpoint.entity;
    } else {
      e['interface'] = endpoint.interface;
      e['node']      = endpoint.node;
    }

    form.append('endpoint', JSON.stringify(e));
  });
  form.append('bandwidth', bandwidth);

  try {
    const resp = await fetch(url, {method: 'post', credentials: 'include', body: form});
    const data = await resp.json();

    if ('error_text' in data) throw(data.error_text);
    if (typeof data.results.success === 'undefined' || typeof data.results.circuit_id === 'undefined') {
      throw("Unexpected response format received from server:", data);
    }

    console.log(data.results);
    return data.results;
  } catch(error) {
    console.log('Failure occurred in updateCircuit:', error);
    return null;
  }
}

async function getCircuit(id) {
  let url = `[% path %]services/data.cgi?method=get_circuit_details&circuit_id=${id}`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    return data.results;
  } catch(error) {
    console.log('Failure occurred in getCircuit:', error);
    return null;
  }
}

async function getCircuitEvents(id) {
  let url = `[% path %]services/data.cgi?method=get_circuit_scheduled_events&circuit_id=${id}`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    return data.results;
  } catch(error) {
    console.log('Failure occurred in getCircuit.');
    console.log(error);
    return null;
  }
}

async function getCircuitHistory(id) {
  let url = `[% path %]services/data.cgi?method=get_circuit_history&circuit_id=${id}`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    return data.results;
  } catch(error) {
    console.log('Failure occurred in getCircuit.');
    console.log(error);
    return null;
  }
}

async function getRawCircuit(id) {
  let url = `[% path %]services/data.cgi?method=generate_clr&circuit_id=${id}`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();

    if ('error_text' in data) throw(data.error_text);

    return data.results.clr;
  } catch(error) {
    console.log('Failure occurred in getRawCircuit:', error);
    return null;
  }
}
