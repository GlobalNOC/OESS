async function loadCommands(vrf) {
    let commands = await getCommands();

    let options = '';
    commands.forEach(function(cmd) {
            options += `<option data-type="${cmd.type}" value="${cmd.command_id}">${cmd.name}</option>`
    });
    document.querySelector('#command-select').innerHTML = options;

    loadCommandParams(vrf);
    renderCommandParams();
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
                info[e.node][e.interface][e.tag] = {};
            }

            e.peers.forEach(function(p) {
                    if (!(p.peer_ip in info[e.node][e.interface][e.tag])) {
                        info[e.node][e.interface][e.tag][p.peer_ip] = 1;
                    }
            });
    });
    sessionStorage.setItem('commandParams', JSON.stringify(info));
}

async function renderCommandParams() {
    let info = JSON.parse(sessionStorage.getItem("commandParams"));
    let select = document.querySelector('#command-select');
    let option = select.options[select.selectedIndex];
    if (option === undefined) {
        return null;
    }

    document.querySelector('#command-node-selector').style.display = 'block';
    document.querySelector('#command-intf-selector').style.display = 'block';
    document.querySelector('#command-unit-selector').style.display = 'block';
    document.querySelector('#command-peer-selector').style.display = 'block';

    let options = '';

    if (option.dataset.type === 'node') {
        document.querySelector('#command-intf-selector').style.display = 'none';
        document.querySelector('#command-unit-selector').style.display = 'none';
        document.querySelector('#command-peer-selector').style.display = 'none';

        Object.keys(info).forEach(function(k) {
                options += `<option value="${k}">${k}</option>`;
        });
        document.querySelector('#command-node').innerHTML = options;
    } else if (option.dataset.type === 'intf') {
        document.querySelector('#command-unit-selector').style.display = 'none';
        document.querySelector('#command-peer-selector').style.display = 'none';

        let node = document.querySelector('#command-node');
        if (!node.value) {
            let loptions = '';
            Object.keys(info).forEach(function(k) {
                    options += `<option value="${k}">${k}</option>`;
            });
            node.innerHTML = loptions;
        }

        Object.keys(info[node.value]).forEach(function(k) {
                options += `<option value="${k}">${k}</option>`;
        });
        document.querySelector('#command-intf').innerHTML = options;
    } else if (option.dataset.type === 'unit') {
        document.querySelector('#command-peer-selector').style.display = 'none';

        let node = document.querySelector('#command-node');
        if (!node.value) {
            let loptions = '';
            Object.keys(info).forEach(function(k) {
                    loptions += `<option value="${k}">${k}</option>`;
            });
            node.innerHTML = loptions;
        }
        let intf = document.querySelector('#command-intf');
        if (!intf.value) {
            let loptions = '';
            Object.keys(info[node.value]).forEach(function(k) {
                    loptions += `<option value="${k}">${k}</option>`;
            });
            intf.innerHTML = loptions;
        }

        Object.keys(info[node.value][intf.value]).forEach(function(k) {
                options += `<option value="${k}">${k}</option>`;
        });
        document.querySelector('#command-unit').innerHTML = options;
    } else {
        let node = document.querySelector('#command-node');
        if (!node.value) {
            let loptions = '';
            Object.keys(info).forEach(function(k) {
                    loptions += `<option value="${k}">${k}</option>`;
            });
            node.innerHTML = loptions;
        }
        let intf = document.querySelector('#command-intf');
        if (!intf.value) {
            let loptions = '';
            Object.keys(info[node.value]).forEach(function(k) {
                    loptions += `<option value="${k}">${k}</option>`;
            });
            intf.innerHTML = loptions;
        }
        let unit = document.querySelector('#command-unit');
        if (!unit.value) {
            let loptions = '';
            Object.keys(info[node.value][intf.value]).forEach(function(k) {
                    loptions += `<option value="${k}">${k}</option>`;
            });
            unit.innerHTML = loptions;
        }

        Object.keys(info[node.value][intf.value][unit.value]).forEach(function(k) {
                options += `<option value="${k}">${k}</option>`;
        });
        document.querySelector('#command-peer').innerHTML = options;
    }
}

async function loadCommandResult() {
    let select = document.querySelector('#command-select');
    let cmdID = select.options[select.selectedIndex].value;

    let url = new URL(window.location.href);
    let vrfID = url.searchParams.get('vrf_id');

    // let results = await runCommand(session.data.workgroup_id, cmdID, vrfID);

    let options = {};
    if (document.querySelector('#command-node-selector').style.display == 'block') {
        options['node'] = document.querySelector('#command-node').value;
    }
    if (document.querySelector('#command-intf-selector').style.display == 'block') {
        options['interface'] = document.querySelector('#command-intf').value;
    }
    if (document.querySelector('#command-unit-selector').style.display == 'block') {
        options['unit'] = document.querySelector('#command-unit').value;
    }
    if (document.querySelector('#command-peer-selector').style.display == 'block') {
        options['peer'] = document.querySelector('#command-peer').value;
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
