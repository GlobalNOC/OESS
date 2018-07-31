async function loadCommands() {
    let commands = await getCommands();

    let options = '';
    commands.forEach(function(cmd) {
            options += `<option value="${cmd.id}">${cmd.name}</option>`
    });
    document.querySelector('#command-select').innerHTML = options;
}

async function loadCommandResult() {
    let select = document.querySelector('#command-select');
    let cmdID = select.options[select.selectedIndex].value;

    let url = new URL(window.location.href);
    let vrfID = url.searchParams.get('vrf_id');

    let results = await runCommand(session.data.workgroup_id, cmdID, vrfID);
    document.querySelector('#command-result').innerHTML = results[0];

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
