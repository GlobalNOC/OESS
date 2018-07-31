async function getCommands() {
  let url = `[% path %]services/command.cgi?method=get_commands`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    return data.results;
  } catch(error) {
    console.log('Failure occurred in getCommands.');
    console.log(error);
    return null;
  }
}

async function runCommand(workgroupID, commandID, vrfID) {
    let url = `[% path %]services/command.cgi?method=run_command&workgroup_id=${workgroupID}&command_id=${commandID}&vrf_id=${vrfID}`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    return data.results;
  } catch(error) {
    console.log('Failure occurred in getCommands.');
    console.log(error);
    return null;
  }
}
