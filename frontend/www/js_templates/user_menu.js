async function loadUserMenu() {
  let workgroups = await getWorkgroups();

  let userMenuActiveWorkgroup = document.querySelector(`#active_workgroup_name`);
  let userMenuWorkgroups = document.querySelector(`#user-menu-workgroups`);
  let html = `
<li>
  <a href="#">
    <b>Jonathan Stout</b><br/>
    GlobalNOC<br/>
    jonstout@globolnoc.iu.edu
  </a>
</li>
<li role="separator" class="divider"></li>
`;

  workgroups.forEach(function(group) {
      if (session.data.workgroup_id === undefined) {
          session.data.workgroup_id = group.workgroup_id;
          session.save();
      }

      if (session.data.workgroup_id == group.workgroup_id) {
          userMenuActiveWorkgroup.innerHTML = group.name;
      }
      html += `<li><a onclick="selectWorkgroup(${group.workgroup_id})" href="#">${group.name}</a></li>`;
  });

  userMenuWorkgroups.innerHTML += html;
}

async function selectWorkgroup(workgroupID) {
    session.data.workgroup_id = workgroupID;
    session.save();
    location.reload();
}
