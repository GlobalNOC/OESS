import { config } from '../config.jsx';


export const getEndpointsInReview = async () => {
  let url = `${config.base_url}/services/admin/admin.cgi?method=get_endpoints_in_review`;

  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();
  
  if (data.error_text) throw data.error_text;
  return data.results;
};

export const reviewEndpoint = async (approve, circuitEpId, vrfEpId) => {
  let url = `${config.base_url}/services/admin/admin.cgi?method=review_endpoint`;
  url += (approve) ? `&approve=1` : `&approve=0`;
  if (circuitEpId) {
    url += `&circuit_ep_id=${circuitEpId}`;
  } else if (vrfEpId) {
    url += `&vrf_ep_id=${vrfEpId}`;
  }

  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  if (!resp.ok) throw resp.statusText;
  const data = await resp.json();

  if (data.error_text) throw data.error_text;
  return data.results;
};
