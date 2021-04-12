import { config } from '.././config.jsx';

/**
 * @param {object} node Node object
 * @param {string} node.name Name of this node
 * @param {string} node.shortName Short name of this node
 * @param {string} node.longitude Longitude of this node
 * @param {string} node.latitude Latitude of this node
 * @param {string} node.vlanRange VLAN range of this node
 * @param {string} node.ipAddress IP address of this node
 * @param {string} node.tcpPort TCP port of this node
 * @param {string} node.make Hardare make of this node
 * @param {string} node.model Hardware model of this node
 * @param {string} node.controller Controller of this node. Valid arguments are 'netconf', 'nso', and 'openflow'
 * 
 * @returns {object} resp
 * @returns {number} resp.success Set to 1 if request was successful
 * @returns {number} resp.node_id NodeId of the created node
 */
export const createNode = async (node) => {
  let validControllers = ['netconf', 'nso', 'openflow'];
  if (!validControllers.includes(node.controller)) {
    throw `Invalid controller '${node.controller}' used in createNode.`;
  }

  let url = `${config.base_url}services/node.cgi?method=create_node`;
  url += `&name=${node.name}`;
  url += `&short_name=${node.shortName}`;
  url += `&longitude=${node.longitude}`;
  url += `&latitude=${node.latitude}`;
  url += `&vlan_range=${node.vlanRange}`;
  url += `&ip_address=${node.ipAddress}`;
  url += `&tcp_port=${node.tcpPort}`;
  url += `&make=${node.make}`;
  url += `&model=${node.model}`;
  url += `&controller=${node.controller}`;

  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();
  if (data.error_text) throw data.error_text;
  return data.results[0];
}

export const getNode = async (nodeId) => {
  return {
    longitude: 10,
    short_name: "mx960-1",
    sw_ver: "13.3R3",
    name: "mx960-1.sdn-test.grnoc.iu.edu",
    model: "MX",
    port: 830,
    latitude: 10,
    ip_address: "192.168.1.1",
    vendor: "Juniper",
    node_id: nodeId
  };
};

export const getNodes = async () => {
  return [
    {
      longitude: 10,
      short_name: "mx960-1",
      sw_ver: "13.3R3",
      name: "mx960-1.sdn-test.grnoc.iu.edu",
      model: "MX",
      port: 830,
      latitude: 10,
      ip_address: "192.168.1.1",
      vendor: "Juniper",
      node_id: nodeId
    }
  ];
};
