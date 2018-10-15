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

async function runCommand(workgroupID, commandID, options={}) {
    let url = `[% path %]services/command.cgi?method=run_command&workgroup_id=${workgroupID}&command_id=${commandID}`;
    Object.keys(options).forEach(function(k) {
            url += `&${k}=${options[k]}`;
    });

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
