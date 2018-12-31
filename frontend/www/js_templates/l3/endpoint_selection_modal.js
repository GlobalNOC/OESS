/**
 *
 */
class EndpointSelectionModal extends Component {
  constructor(props) {
    super();
    this.props = props || {};

    this.props.index = -1;
    this.props.entity = null;

    console.log('EndpointSelectionModal:', this.props);

    this.entityForm = new EntityForm({
      onSubmit: this.onSubmitEntity.bind(this),
      onCancel: this.onCancelEntity.bind(this),
      onEntityChange: this.onEntityChange.bind(this)
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

  onEntityChange(entity) {
    this.props.entity = entity;
    this.props.vlan = null;
    update();
  }

  onCancelEntity(e) {

  }

  onSubmitEntity(e) {

  }

  onInterfaceChange(intf) {
    this.props.interface = intf;
    this.props.vlan = null;
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
    console.log('EndpointSelectionModal.render:');

    let entityIsActive =  this.props.entity_id ? 'active': '';
    let intfIsActive = this.props.entity_id ? '' : 'active';

    let [entityForm, interfaceForm] = await Promise.all([
      this.entityForm.render({}),
      this.interfaceForm.render({
        interface:         this.props.interface,
        vlan:              this.props.vlan
      })
    ]);

    return `
      <div class="modal-dialog" role="document">
        <div class="modal-content">
          <div class="modal-header">
            <h4 id="endpoint-select-header" class="modal-title">Add Network Endpoint</h4>
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
