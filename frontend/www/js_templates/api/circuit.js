async function getCircuit(id) {
  let url = `[% path %]services/data.cgi?method=get_circuit_details&circuit_id=${id}`;

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
    return data.results.clr;
  } catch(error) {
    console.log('Failure occurred in getCircuit.');
    console.log(error);
    return null;
  }
}
