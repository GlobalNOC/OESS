async function loadCommands(vrf) {
    let commands = await getCommands();

    let options = '';
    commands.forEach(function(cmd) {
            options += `<option data-type="${cmd.type}" value="${cmd.command_id}">${cmd.name}</option>`
    });
    document.querySelector('#command-select').innerHTML = options;

    loadCommandParams(vrf);
    // Load sub-selectors
    commandSelectChangeHandler(document.querySelector('#command-select'));
}

/**
 * loadCommandParams loads all switch, interface, and peers into
 * session storage. This is then used to populate the various
 * selectors in renderCommandParams.
 */
async function loadCommandParams(vrf) {
    let info = {};

    vrf.endpoints.forEach(function(e) {
            if (!(e.node in info)) {
                info[e.node] = {};
            }

            if (!(e.interface in info[e.node])) {
                info[e.node][e.interface] = {};
            }

            if (!(e.tag in info[e.node][e.interface])) {
                info[e.node][e.interface][e.unit] = {};
            }

            e.peers.forEach(function(p) {
                    if (!(p.peer_ip in info[e.node][e.interface][e.unit])) {
                        info[e.node][e.interface][e.unit][p.peer_ip] = 1;
                    }
            });
    });
    sessionStorage.setItem('commandParams', JSON.stringify(info));
}

async function loadCommandResult() {
    let select = document.querySelector('#command-select');
    let cmdID = select.options[select.selectedIndex].value;
    let cmdType = select.options[select.selectedIndex].dataset.type;

    let url = new URL(window.location.href);
    let vrfID = url.searchParams.get('vrf_id');

    let node = document.querySelector('#command-node');
    let intf = document.querySelector('#command-intf');
    let unit = document.querySelector('#command-unit');
    let peer = document.querySelector('#command-peer');

    let options = {};
    if (cmdType === 'node') {
        options['node'] = node.options[node.selectedIndex].value;
    }
    else if (cmdType === 'intf') {
        options['node'] = node.options[node.selectedIndex].value;
        options['interface'] = intf.options[intf.selectedIndex].value;
    }
    else if (cmdType === 'unit') {
        options['node'] = node.options[node.selectedIndex].value;
        options['interface'] = intf.options[intf.selectedIndex].value;
        options['unit'] = unit.options[unit.selectedIndex].value;
    }
    else if (cmdType === 'peer') {
        options['node'] = node.options[node.selectedIndex].value;
        options['interface'] = intf.options[intf.selectedIndex].value;
        options['unit'] = unit.options[unit.selectedIndex].value;
        options['peer'] = peer.options[peer.selectedIndex].value;
    }
    else {
        console.error(`Unable to run command for unknown command type '${cmdType}'.`);
        return null;
    }

    let results = await runCommand(session.data.workgroup_id, cmdID, options);
    if (!results) {
        document.querySelector('#command-result').innerHTML = 'Something went wrong. Please try again later.';;
    } else {
        document.querySelector('#command-result').innerHTML = results[0];
    }

    document.querySelector('#command-result-toggle').innerHTML = 'Collapse';
    document.querySelector('#command-result').style.display = 'block';
}

async function toggleCommandResult() {
    if (document.querySelector('#command-result-toggle').innerHTML === 'Expand') {
        document.querySelector('#command-result-toggle').innerHTML = 'Collapse';
        document.querySelector('#command-result').style.display = 'block';
    } else {
        document.querySelector('#command-result-toggle').innerHTML = 'Expand';
        document.querySelector('#command-result').style.display = 'none';
    }
}

function commandSelectChangeHandler(e) {
  let cmd = e.options[e.selectedIndex];
  let cmdType = cmd.dataset.type;

  // display sub-selectors based on selected cmdType
  let intf = document.querySelector('#command-intf-selector');
  let unit = document.querySelector('#command-unit-selector');
  let peer = document.querySelector('#command-peer-selector');

  if (cmdType === 'node') {
    loadNodeSelect();
    intf.style.display = 'none';
    unit.style.display = 'none';
    peer.style.display = 'none';
  }
  else if (cmdType === 'intf') {
    loadNodeSelect();
    loadIntfSelect();
    intf.style.display = 'block';
    unit.style.display = 'none';
    peer.style.display = 'none';
  }
  else if (cmdType === 'unit') {
    loadNodeSelect();
    loadIntfSelect();
    loadUnitSelect();
    intf.style.display = 'block';
    unit.style.display = 'block';
    peer.style.display = 'none';
  }
  else if (cmdType === 'peer') {
    loadNodeSelect();
    loadIntfSelect();
    loadUnitSelect();
    loadPeerSelect();
    intf.style.display = 'block';
    unit.style.display = 'block';
    peer.style.display = 'block';
  }
  else {
    console.error(`Unable to render form for unknown command type '${cmdType}'.`);
  }
}

function loadNodeSelect() {
  let info = JSON.parse(sessionStorage.getItem("commandParams"));

  let options = '';
  Object.keys(info).forEach(function(nodeName) {
    options += `<option value="${nodeName}">${nodeName}</option>`;
  });
  document.querySelector('#command-node').innerHTML = options;

  return loadIntfSelect();
}

function nodeSelectChangeHandler(e) {
  let cmdSelect = document.querySelector('#command-select');
  let cmd = cmdSelect.options[cmdSelect.selectedIndex];

  if (cmd.dataset.type === 'node') {
    return 1;
  }

  return loadIntfSelect();
}

function loadIntfSelect() {
  let info = JSON.parse(sessionStorage.getItem("commandParams"));

  let nodeSelect = document.querySelector('#command-node');
  let node = nodeSelect.options[nodeSelect.selectedIndex].value;

  let options = '';
  Object.keys(info[node]).forEach(function(k) {
    options += `<option value="${k}">${k}</option>`;
  });
  document.querySelector('#command-intf').innerHTML = options;

  return loadUnitSelect();
}

function intfSelectChangeHandler(e) {
  let cmdSelect = document.querySelector('#command-select');
  let cmd = cmdSelect.options[cmdSelect.selectedIndex];

  if (cmd.dataset.type === 'node') {
    return 1;
  }
  if (cmd.dataset.type === 'intf') {
    return 1;
  }

  return loadUnitSelect();
}

function loadUnitSelect() {
  let info = JSON.parse(sessionStorage.getItem("commandParams"));

  let nodeSelect = document.querySelector('#command-node');
  let node = nodeSelect.options[nodeSelect.selectedIndex].value;

  let intfSelect = document.querySelector('#command-intf');
  let intf = intfSelect.options[intfSelect.selectedIndex].value;

  let options = '';
  Object.keys(info[node][intf]).forEach(function(k) {
    options += `<option value="${k}">${k}</option>`;
  });
  document.querySelector('#command-unit').innerHTML = options;

  return loadPeerSelect();
}

function unitSelectChangeHandler(e) {
  let cmdSelect = document.querySelector('#command-select');
  let cmd = cmdSelect.options[cmdSelect.selectedIndex];

  if (cmd.dataset.type === 'node') {
    return 1;
  }
  if (cmd.dataset.type === 'intf') {
    return 1;
  }
  if (cmd.dataset.type === 'unit') {
    return 1;
  }

  return loadPeerSelect();
}

function loadPeerSelect() {
  let info = JSON.parse(sessionStorage.getItem("commandParams"));

  let nodeSelect = document.querySelector('#command-node');
  let node = nodeSelect.options[nodeSelect.selectedIndex].value;

  let intfSelect = document.querySelector('#command-intf');
  let intf = intfSelect.options[intfSelect.selectedIndex].value;

  let unitSelect = document.querySelector('#command-unit');
  let unit = unitSelect.options[unitSelect.selectedIndex].value;

  let options = '';
  Object.keys(info[node][intf][unit]).forEach(function(k) {
    options += `<option value="${k}">${k}</option>`;
  });
  document.querySelector('#command-peer').innerHTML = options;

  return 1;
}
