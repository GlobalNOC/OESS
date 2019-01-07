/**
 * getEntities returns a list of all entities.
 *
 * @param {integer} workgroupID - Identifier of the relevant workgroup
 */
// async function getEntities(workgroupID) {
//   let url = `[% path %]services/entity.cgi?method=get_entities&workgroup_id=${workgroupID}`;

//   try {
//     const resp = await fetch(url, {method: 'get', credentials: 'include'});
//     const data = await resp.json();
//     if (data.error_text) throw data.error_text;
//     return data.results;
//   } catch(error) {
//     console.log('Failure occurred in getEntities.');
//     console.log(error);
//     return [];
//   }
// }
