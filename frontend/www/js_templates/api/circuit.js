async function deleteCircuit(workgroupID, circuitID, end=-1) {
  let url = '[% path %]services/circuit.cgi?method=remove';
  url += `&circuit_id=${circuitID}`;
  url += `&workgroup_id=${workgroupID}`;
  
  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();

  if ('error_text' in data) throw(data.error_text);
  return data.results;
  
}

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
async function provisionCircuit(workgroupID, description, endpoints, start=-1, end=-1, circuitID=-1) {
  let url = '[% path %]services/circuit.cgi';

  let form = new FormData();
  form.append('method', 'provision');
  form.append('workgroup_id', workgroupID);
  form.append('description', description);
  form.append('static_mac', 0);
  form.append('provision_time', start     || -1);
  form.append('remove_time',    end       || -1);
  form.append('restore_to_primary', 0);
  form.append('circuit_id', circuitID);

  let bandwidth = 0;
  endpoints.forEach(function(endpoint) {
    bandwidth = (endpoint.bandwidth > bandwidth) ? endpoint.bandwidth : bandwidth;

    let e = {
      bandwidth:        endpoint.bandwidth,
      tag:              endpoint.tag,
      cloud_account_id: endpoint.cloud_account_id,
      circuit_ep_id:    endpoint.circuit_ep_id,
      jumbo:            (endpoint.jumbo) ? 1 : 0
    };

    if (endpoint.cloud_gateway_type !== null) {
      e['cloud_gateway_type'] = endpoint.cloud_gateway_type;
    }

    if ('entity_id' in endpoint && endpoint.name === 'TBD' && endpoint.interface === 'TBD') {
      e['entity'] = endpoint.entity;
    } else {
      e['interface'] = endpoint.interface;
      e['node']      = endpoint.node;
      e['entity']    = endpoint.entity;
    }

    form.append('endpoint', JSON.stringify(e));
  });

  const resp = await fetch(url, {method: 'post', credentials: 'include', body: form});
  const data = await resp.json();
  if ('error_text' in data) throw data.error_text;
  return data;
}

async function getCircuit(id, workgroupId) {
  let url = `[% path %]services/circuit.cgi?method=get&circuit_id=${id}&workgroup_id=${workgroupId}`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    if ('error_text' in data) throw(data.error_text);
    if (data.results.length == 0) throw('Circuit not found.');
    return data.results[0];
  } catch(error) {
    console.log('Failure occurred in getCircuit:', error);
    return null;
  }
}

async function getCircuits(workgroupID) {
  let url = `[% path %]services/circuit.cgi?method=get&workgroup_id=${workgroupID}`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    if ('error_text' in data) throw(data.error_text);
    return data.results;
  } catch(error) {
    console.log('Failure occurred in getCircuits:', error);
    return [];
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
