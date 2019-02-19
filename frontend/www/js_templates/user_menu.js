async function loadUserMenu() {
  let user = await getCurrentUser();

  let userMenuActiveWorkgroup = document.querySelector(`#active_workgroup_name`);
  let userMenuWorkgroups = document.querySelector(`#user-menu-workgroups`);
  let html = `
<li>
  <a href="#">
    <b>${user.first_name} ${user.last_name}</b><br/>
    ${user.username}<br/>
    ${user.email}
  </a>
</li>
<li role="separator" class="divider"></li>
`;

  session.data.isAdmin = (user.is_admin === 1) ? true : false;
  session.data.isReadOnly = (user.type === 'read-only') ? true : false;
  session.data.username = user.username;

  user.workgroups.forEach(function(group) {
      if (session.data.workgroup_id === undefined) {
          session.data.workgroup_id = group.workgroup_id;
      }

      if (session.data.workgroup_id == group.workgroup_id) {
          userMenuActiveWorkgroup.innerHTML = user.username + ' / ' + group.name;
      }
      html += `<li><a onclick="selectWorkgroup(${group.workgroup_id})" href="#">${group.name}</a></li>`;
  });

  session.save();

  userMenuWorkgroups.innerHTML += html;
}

async function selectWorkgroup(workgroupID) {
    session.data.workgroup_id = workgroupID;
    session.save();
    location.reload();
}
