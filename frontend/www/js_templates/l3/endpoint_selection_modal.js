/**
 *
 */
class EndpointSelectionModal extends Component {
  constructor(props) {
    super();
    this.props = props || {};

    this.props.index  = -1;
    this.props.entity = null;
    this.props.entityName = 'TBD';
    this.props.entityNode = 'TBD';
    this.props.jumbo = true;

    this.props.interface = (this.props.interface === null) ? -1 : this.props.interface.interface_id;

    this.entityForm = new EntityForm({
      onSubmit: this.onSubmitEntity.bind(this),
      onCancel: this.onCancelEntity.bind(this),
      onEntityChange: this.onEntityChange.bind(this),
      onEntityInterfaceChange: this.onEntityInterfaceChange.bind(this)
    });
    this.interfaceForm = new InterfaceForm({
      onSubmit: this.onSubmitInterface.bind(this),
      onCancel: this.onCancelInterface.bind(this),
      onInterfaceChange: this.onInterfaceChange.bind(this)
    });
  }

  setIndex(i) {
    this.props.index = i;
  }

  setEntity(i) {
    this.props.entity = i;
  }

  setInterface(i) {
    this.props.interface = i;
  }

  setVLAN(i) {
    this.props.vlan = i;
  }

  setEntity(i) {
    this.props.entity = i;
  }

  setJumbo(i) {
    this.props.jumbo = i;
  }

  onEntityChange(entity) {
    this.props.entity = entity;
    this.props.vlan = null;
    update();
  }

  onEntityInterfaceChange(name, node) {
    this.props.entityName = name;
    this.props.entityNode = node;
  }

  onCancelEntity(e) {
    let entityAlert = document.querySelector('#entity-alert');
    entityAlert.innerHTML = '';
    entityAlert.style.display = 'none';
    let entityAlertOK = document.querySelector('#entity-alert-ok');
    entityAlertOK.innerHTML = '';
    entityAlertOK.style.display = 'none';

    let addEndpointModal = $('#add-endpoint-modal');
    addEndpointModal.modal('hide');
  }

  onSubmitEntity(e) {
    let name = document.querySelector('#entity-name').value;
    if (name === '') {
        document.querySelector('#entity-alert').style.display = 'block';
        return null;
    }

    if (!document.querySelector('#entity-bandwidth').validity.valid) {
        document.querySelector('#entity-bandwidth').reportValidity();
        return null;
    }

    let entity = {
        bandwidth: document.querySelector('#entity-bandwidth').value,
        name: this.props.entityName,
        node: this.props.entityNode,
        peerings: [],
        tag: document.querySelector('#entity-vlans').value,
        entity_id: document.querySelector('#entity-id').value,
        entity: document.querySelector('#entity-name').value,
        cloud_account_id: document.querySelector('#entity-cloud-account-id').value,
        cloud_account_type: document.querySelector('#entity-cloud-account-type').value,
        jumbo: document.querySelector('#entity-jumbo-frames').checked
    };

    let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
    if (this.props.index >= 0) {
        entity.peerings = endpoints[this.props.index].peerings;
        endpoints[this.props.index] = entity;
    } else {
        endpoints.push(entity);
    }

    sessionStorage.setItem('endpoints', JSON.stringify(endpoints));
    loadSelectedEndpointList();

    let entityAlert = document.querySelector('#entity-alert');
    entityAlert.innerHTML = '';
    entityAlert.style.display = 'none';
    let entityAlertOK = document.querySelector('#entity-alert-ok');
    entityAlertOK.innerHTML = '';
    entityAlertOK.style.display = 'none';
    
    this.props.entityName = 'TBD';
    this.props.entityNode = 'TBD';

    let addEndpointModal = $('#add-endpoint-modal');
    addEndpointModal.modal('hide');
    return 1;
  }

  onInterfaceChange(intf) {
    this.props.interface = intf;
    this.props.vlan = null;
    this.props.entity = null;
    update();
  }

  onCancelInterface(e) {
    let addEndpointModal = $('#add-endpoint-modal');
    addEndpointModal.modal('hide');
  }

  onSubmitInterface(e) {
    let select = document.querySelector('#endpoint-select-interface');
    let node = select.options[select.selectedIndex].getAttribute('data-node');
    let intf = select.options[select.selectedIndex].getAttribute('data-interface');
    let intf_id = select.options[select.selectedIndex].value;
    let entity = select.options[select.selectedIndex].getAttribute('data-entity');
    let entity_id = select.options[select.selectedIndex].getAttribute('data-entity_id');
    if(entity == "undefined" || entity == "" || entity == null || entity == undefined){
        entity = "NA";
    }
    if(entity_id == "undefined" || entity_id == "" || entity_id == null || entity_id == undefined){
        entity_id = null;
    }

    let endpoint = {
        bandwidth: document.querySelector('#endpoint-bandwidth').value,
        name: intf,
        interface_id: intf_id,
        node: node,
        entity: entity,
        entity_id: entity_id,
        peerings: [],
        cloud_account_id: '',
        tag: document.querySelector('#endpoint-vlans').value
    };

    let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
    if (this.props.index >= 0) {
        endpoint.peerings = endpoints[this.props.index].peerings;
        endpoints[this.props.index] = endpoint;
    } else {
        endpoints.push(endpoint);
    }

    sessionStorage.setItem('endpoints', JSON.stringify(endpoints));
    loadSelectedEndpointList();

    let addEndpointModal = $('#add-endpoint-modal');
    addEndpointModal.modal('hide');
  }

  async render() {
    let entityIsActive =  this.props.entity ? 'active': '';
    let intfIsActive = this.props.entity ? '' : 'active';

    let [entityForm, interfaceForm] = await Promise.all([
      this.entityForm.render({
        entity: this.props.entity,
        vlan: this.props.vlan,
        jumbo: this.props.jumbo
      }),
      this.interfaceForm.render({
        interface: this.props.interface,
        vlan:      this.props.vlan
      })
    ]);

    let header = this.props.index === -1 ? 'Add Network Endpoint' : 'Modify Network Endpoint';

    return `
      <div class="modal-dialog" role="document">
        <div class="modal-content">
          <div class="modal-header">
            <h4 id="endpoint-select-header" class="modal-title">${header}</h4>
          </div>
          <div class="modal-body">
            <div style="margin-bottom: 15px;">
             <div id="entity-alert" class="alert alert-danger" role="alert" style="display: none;"></div>
             <div id="entity-alert-ok" class="alert alert-info" role="alert" style="display: none;"></div>

              <ul class="nav nav-tabs">
                <li role="presentation" class="${entityIsActive}">
                  <a id="basic" href="#basic-content" aria-controls="basic" role="tab" data-toggle="tab">By Entity</a>
                </li>
                <li role="presentation" class="${intfIsActive}">
                  <a id="advanced" href="#advanced-content" aria-controls="advanced" role="tab" data-toggle="tab">My Interfaces</a>
                </li>
              </ul>

              <div class="tab-content">
                <div role="tabpanel" id="basic-content" class="tab-pane ${entityIsActive}">
                  <div style="margin-bottom: 15px;"></div>
                  ${entityForm}
                </div>
                <div role="tabpanel" id="advanced-content" class="tab-pane ${intfIsActive}">
                  <div style="margin-bottom: 15px;"></div>
                  ${interfaceForm}
                </div>
              </div>

            </div>
          </div>
        </div>
      </div>
    `;
  }
}
