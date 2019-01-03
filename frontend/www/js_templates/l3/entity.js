class EntityForm extends Component {
  constructor(props) {
    super();
    this.props = {
      onCancel:       props.onCancel,
      onSubmit:       props.onSubmit,
      onEntityChange: props.onEntityChange,
      onEntityInterfaceChange: props.onEntityInterfaceChange
    };
  }

  async loadEntitySearchList(search) {
    let entities = await getEntitiesAll(session.data.workgroup_id, search.value);

    let items = '';
    for (let i = 0; i < entities.length; i++) {
      let e = entities[i];
      items += `
      <a href="#"
         class="list-group-item"
         onclick="document.components[${this._id}].props.onEntityChange(${e.entity_id})">${e.name}</a>
      `;
    }

    let list = document.querySelector('#entity-search-list');
    list.innerHTML = items;
  }

  async render(props) {
    console.log('EntityForm:', props);
    let options = {};
    let entity = await getEntities(session.data.workgroup_id, props.entity, options);

    if (entity === null) {
      return `<div class="form-group"></div>`;
    }

    let parent = null;
    if ('parents' in entity && entity.parents.length > 0) {
      parent = entity.parents[0];
    }

    let entities = '';
    let spacer = '';

    if (parent) {
      entities += `
      <button type="button" class="list-group-item active"
              onclick="document.components[${this._id}].props.onEntityChange(${parent.entity_id})">
        <span class="glyphicon glyphicon-menu-up"></span>&nbsp;&nbsp;
        ${entity.name}
      </button>
      `;
      spacer = '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;';
    }

    if ('children' in entity && entity.children.length > 0) {
      for (let i = 0; i < entity.children.length; i++) {
        let child = entity.children[i];
        entities += `
        <button type="button" class="list-group-item"
                onclick="document.components[${this._id}].props.onEntityChange(${child.entity_id})">
          ${spacer}${child.name}
          <span class="glyphicon glyphicon-menu-right" style="float: right;"></span>
        </button>
        `;
      }
    }

    // Once the user has selected a leaf entity it's expected that we
    // display all its associated ports.
    if ('children' in entity && entity.children.length === 0) {
      for (let i = 0; i < entity.interfaces.length; i++) {
        let child = entity.interfaces[i];
        entities += `
        <button type="button"
                class="list-group-item"
                onclick="document.components[${this._id}].props.onEntityInterfaceChange('${child.name}', '${child.node}')">
          ${spacer}<b>${child.node}</b> ${child.name}
        </button>
        `;
      }
    }

    if (entities === '') {
      entities += `
      <button type="button" class="list-group-item">
        Placeholder<span class="glyphicon glyphicon-menu-right" style="float: right;"></span>
      </button>
      `;
    }

    let vlans = [];
    let vlanH = {};
    for (let i = 0; i < entity.interfaces.length; i++) {
        for (let j = 0; j < entity.interfaces[i].available_vlans.length; j++) {
            vlanH[entity.interfaces[i].available_vlans[j]] = 1;
        }
    }
    let key;
    for (key in vlanH) {
        vlans.push(key);
    }
    if (!props.vlan) {
      props.vlan = vlans[0];
    } else if (!vlans.includes(props.vlan)) {
      vlans.unshift(props.vlan);
    }

    let accessRequestable = false;
    let vlanSelectable = true;
    let vlanOptions = '';
    for (let i = 0; i < vlans.length; i++) {
      let selected = vlans[i] == props.vlan ? 'selected' : '';
      vlanOptions += `<option ${selected}>${vlans[i]}</option>`;
    }
    if (vlanOptions === '') {
      accessRequestable = true;
      vlanSelectable = false;
      vlanOptions = '<option>VLANs not available for the selected Entity</option>';
    }

    for (let i = 0; i < entity.interfaces.length; i++) {
      if (typeof entity.interfaces[i].cloud_interconnect_id === 'undefined') {
        continue;
      }

      entity.cloud_interconnect_id = entity.interfaces[i].cloud_interconnect_id;
      entity.cloud_interconnect_type = entity.interfaces[i].cloud_interconnect_type;
    }

    let cloudAccountLabel = 'AWS Account Owner';
    if (entity.cloud_interconnect_id === null || entity.cloud_interconnect_id === 'null' || entity.cloud_interconnect_id === '') {
      entity.cloud_interconnect_id = null;
    } else {
      if (entity.cloud_interconnect_type === 'gcp-partner-interconnect') {
        cloudAccountLabel = 'GCP Pairing Key';
      }
    }

    let bandwidthOptions = `<option value="0" selected>Unlimited</option>`;
    if (entity.cloud_interconnect_type === 'aws-hosted-connection') {
      bandwidthOptions = `
      <option value="50" selected>50 Mb/s</option>
      <option value="100">100 Mb/s</option>
      <option value="200">200 Mb/s</option>
      <option value="300">300 Mb/s</option>
      <option value="400">400 Mb/s</option>
      <option value="500">500 Mb/s</option>
      `;
    } else if (entity.cloud_interconnect_type === 'gcp-partner-interconnect') {
      bandwidthOptions = `
      <option value="50" selected>50 Mb/s</option>
      <option value="100">100 Mb/s</option>
      <option value="200">200 Mb/s</option>
      <option value="300">300 Mb/s</option>
      <option value="400">400 Mb/s</option>
      <option value="500">500 Mb/s</option>
      <option value="1000">1 Gb/s</option>
      <option value="2000">2 Gb/s</option>
      <option value="5000">5 Gb/s</option>
      <option value="10000">10 Gb/s</option>
      `;
    }

    return `
    <div class="form-group">
      <input id="entity-search" class="form-control" type="text" placeholder="Search"
             oninput="document.components[${this._id}].loadEntitySearchList(this)"/>
      <div id="entity-search-list" class="list-group" style="max-height:250px; overflow-y:scroll; position: absolute; width: 95%; z-index: 100; box-shadow: 0 4px 8px 0 rgba(0, 0, 0, 0.2), 0 6px 20px 0 rgba(0, 0, 0, 0.19);"></div>
    </div>
    <div style="height: 200px; overflow-y: scroll; margin-bottom: 15px;">
      <div id="entity-list" class="list-group">
        ${entities}
      </div>
    </div>
    <div class="form-group">
      <label class="control-label">VLAN</label>
      <select id="entity-vlans" class="form-control" ${vlanSelectable ? '' : 'disabled'}>${vlanOptions}</select>
    </div>
    <div class="form-group">
      <label class="control-label">Max Bandwidth (Mb/s)</label>
      <select id="entity-bandwidth" class="form-control" ${vlanSelectable ? '' : 'disabled'}>
        ${bandwidthOptions}
      </select>
    </div>
    <div class="form-group" id="entity-cloud-account" style="display: ${entity.cloud_interconnect_id ? 'block' : 'none'};">
      <label id="entity-cloud-account-label" class="control-label">${cloudAccountLabel}</label>
      <input id="entity-cloud-account-id" class="form-control" type="text" placeholder="123456789">
    </div>
    <div class="form-group">
      <input id="entity-cloud-account-type" class="form-control" type="hidden" value="${entity.cloud_interconnect_type}">
    </div>
    <div class="form-group">
      <input id="entity-index" class="form-control" type="hidden" value="">
    </div>
    <div class="form-group">
      <input id="entity-id" class="form-control" type="hidden" value="${entity.entity_id}">
    </div>
    <div class="form-group">
      <input id="entity-name" class="form-control" type="hidden" value="${entity.name}">
    </div>
    <!-- BEGIN If an entity's interface is selected we must track it -->
    <div class="form-group">
      <input id="entity-interface" class="form-control" type="hidden" value="">
    </div>
    <div class="form-group">
      <input id="entity-node" class="form-control" type="hidden" value="">
    </div>
    <!-- END If an entity's interface is selected we must track it -->
    <button id="add-entity-submit"
            class="btn btn-success"
            type="submit"
            style="display: ${vlanSelectable ? 'inline-block' : 'none'}"
            onclick="document.components[${this._id}].props.onSubmit(this)">
      Add Endpoint
    </button>
    <button id="add-entity-request-access"
            class="btn btn-info"
            type="button"
            style="display: ${accessRequestable ? 'inline-block' : 'none'}"
            onclick="location.href='mailto:[% admin_email %]?SUBJECT=System Support: NDDI/OS3E Entity Access Request';">
      Request Access
    </button>
    <button id="add-entity-cancel"
            class="btn btn-danger"
            type="button"
            onclick="document.components[${this._id}].props.onCancel(this)">
      Cancel
    </button>
    `;
  }
}
