
const getDevice = async (nodeId) => {
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

export { getDevice };
