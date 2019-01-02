class EntityForm extends Component {
  constructor(props) {
    super();
    this.props = {
      onCancel:       props.onCancel,
      onSubmit:       props.onSubmit,
      onEntityChange: props.onEntityChange
    };
  }
  
  onCancel(e) {
    addEntityCancelCallback(e);
  }

  onSubmit(e) {
    addEntitySubmitCallback(e);
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

    // loadEntities(${parent.entity_id})
    // loadEntities(${child.entity_id})
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
      entity.interfaces.forEach(function(child) {
        entities += `
        <button type="button"
                class="list-group-item"
                onclick="setEntityEndpoint(${entity.entity_id}, '${entity.name}', '${child.node}', '${child.name}')">
          ${spacer}<b>${child.node}</b> ${child.name}
        </button>
        `;
      });
    }

    if (entities === '') {
      entities += `
      <button type="button" class="list-group-item">
        Placeholder<span class="glyphicon glyphicon-menu-right" style="float: right;"></span>
      </button>
      `;
    }

    return `
    <div class="form-group">
      <input id="entity-search" class="form-control" type="text" placeholder="Search" oninput="loadEntitySearchList(this)"/>
      <div id="entity-search-list" class="list-group" style="max-height:250px; overflow-y:scroll; position: absolute; width: 95%; z-index: 100; box-shadow: 0 4px 8px 0 rgba(0, 0, 0, 0.2), 0 6px 20px 0 rgba(0, 0, 0, 0.19);"></div>
    </div>
    <div style="height: 200px; overflow-y: scroll; margin-bottom: 15px;">
      <div id="entity-list" class="list-group">
        ${entities}
      </div>
    </div>
    <div class="form-group">
      <label class="control-label">VLAN</label>
      <select id="entity-vlans" class="form-control"></select>
    </div>
    <div class="form-group">
      <label class="control-label">Max Bandwidth (Mb/s)</label>
      <select id="entity-bandwidth" class="form-control">
        <option value="0" selected>Unlimited</option>
        <option value="50">50 Mb/s</option>
        <option value="100">100 Mb/s</option>
        <option value="200">200 Mb/s</option>
        <option value="300">300 Mb/s</option>
        <option value="400">400 Mb/s</option>
        <option value="500">500 Mb/s</option>
        <option value="1000">1 Gb/s</option>
        <option value="2000">2 Gb/s</option>
        <option value="5000">5 Gb/s</option>
        <option value="10000">10 Gb/s</option>
      </select>
    </div>
    <div class="form-group" id="entity-cloud-account" style="display: none;">
      <label id="entity-cloud-account-label" class="control-label"></label>
      <input id="entity-cloud-account-id" class="form-control" type="text" placeholder="123456789">
    </div>
    <div class="form-group">
      <input id="entity-cloud-account-type" class="form-control" type="hidden" value="">
    </div>
    <div class="form-group">
      <input id="entity-index" class="form-control" type="hidden" value="">
    </div>
    <div class="form-group">
      <input id="entity-id" class="form-control" type="hidden" value="">
    </div>
    <div class="form-group">
      <input id="entity-name" class="form-control" type="hidden" value="">
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
            onclick="document.components[${this._id}].onSubmit(this)">
      Add Endpoint
    </button>
    <button id="add-entity-request-access"
            class="btn btn-info"
            type="button"
            style="display: inline-block;"
            onclick="location.href='mailto:[% admin_email %]?SUBJECT=System Support: NDDI/OS3E Entity Access Request';">
      Request Access
    </button>
    <button id="add-entity-cancel"
            class="btn btn-danger"
            type="button"
            onclick="document.components[${this._id}].onCancel(this)">
      Cancel
    </button>
    `;
  }
}
