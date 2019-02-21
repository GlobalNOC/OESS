/**
 * getAvailableVLANs returns a list of all VLANs not in use on
 * interfaceID.
 *
 * @param {integer} workgroupID - Identifier of the current workgroup
 * @param {integer} interfaceID - Identifier of the relevant interface
 */
async function getAvailableVLANs(workgroupID, interfaceID, vrfID, circuitID) {
    if (interfaceID === -1) {
        return [];
    }

    let url = `[% path %]services/interface.cgi?method=get_available_vlans&interface_id=${interfaceID}&workgroup_id=${workgroupID}`;

    if(! vrfID == undefined){
        url += "&vrf_id=" + vrfId;
    }

    if(! circuitID == undefined){
        url += "&circuit_id=" + circuitId;
    }

    try {
        const resp = await fetch(url, {method: 'get', credentials: 'include'});
        const data = await resp.json();
        if (data.error_text) throw data.error_text;

        return data.results.available_vlans;
    } catch(error) {
        console.log('Failure occurred in getAvailableVLANs.');
        console.log(error);
        return [];
    }
}
