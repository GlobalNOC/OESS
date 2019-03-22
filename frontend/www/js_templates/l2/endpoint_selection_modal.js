class EndpointSelectionModal2 {
  constructor(query) {
    let template = document.querySelector('#endpoint-selection-modal2');
    this.element = document.importNode(template.content, true);

    this.searchTimeout = null;

    this.parent = document.querySelector(query);
    this.parent.appendChild(this.element);
  }

  display(endpoint) {
    if (endpoint !== null && endpoint.interface === 'TBD') {
      this.populateEntityForm(endpoint);
    } else {
      this.populateEntityForm(endpoint);
      this.populateInterfaceForm(endpoint);
    }
    $('#add-endpoint-modal2').modal('show');
  }

  async populateInterfaceForm(endpoint) {
    let interfaces   = await getInterfacesByWorkgroup(session.data.workgroup_id);
    let interface_id = (interfaces.length === 0) ? -1 : interfaces[0].interface_id;

    let index = -1;

    if (endpoint !== null) {
      interface_id = endpoint.interface_id;
      index = endpoint.index;
    }

    let interfaceSelector = this.parent.querySelector('.endpoint-select-interface');
    let vlanSelector = this.parent.querySelector('.endpoint-select-vlan');

    interfaceSelector.innerHTML = '';
    interfaces.forEach((i) => {
      let o = document.createElement('option');
      o.innerText = `${i.node} ${i.name}`;
      o.setAttribute('value', i.interface_id);
      o.dataset.name = i.name;
      o.dataset.node = i.node;
      o.dataset.description = i.description;

      if (i.interface_id == interface_id) {
        o.setAttribute('selected', true);
      }

      interfaceSelector.appendChild(o);
    });

    let loadVlanSelector = async function(e) {
      let interface_id = -1;
      if ('target' in e) {
        interface_id = e.target.options[e.target.selectedIndex].value;
      } else {
        interface_id = e.interface_id;
      }

      let vlans = await getAvailableVLANs(session.data.workgroup_id, interface_id);
      let vlan = (vlans.length === 0) ? -1 : vlans[0];

      if (endpoint !== null) {
        vlan = endpoint.tag;

        if (!vlans.includes(endpoint.tag)) {
          vlans.unshift(endpoint.tag);
        }
      }

      vlanSelector.innerHTML = '';
      vlans.forEach((v) => {
        let o = document.createElement('option');
        o.innerText = `${v}`;
        o.setAttribute('value', v);

        if (v == vlan) {
          o.setAttribute('selected', true);
        }

        vlanSelector.appendChild(o);
      });
    };

    // If the interface is changed we need reload the vlan selection
    interfaceSelector.onchange = loadVlanSelector;

    // Setup interface-add and interface-cancel callbacks
    this.parent.querySelector('.add-endpoint-submit').onclick = function(e) {
      let endpoint = {
        index:            index,
        bandwidth:        this.parent.querySelector('.endpoint-bandwidth').value,
        interface:        interfaceSelector.options[interfaceSelector.selectedIndex].dataset.name,
        interface_id:     interfaceSelector.options[interfaceSelector.selectedIndex].value,
        interface_description: interfaceSelector.options[interfaceSelector.selectedIndex].dataset.description,
        node:             interfaceSelector.options[interfaceSelector.selectedIndex].dataset.node,
        entity:           null, // entity,
        entity_id:        null, // entity_id,
        peerings:         [],
        cloud_account_id: '',
        tag:              vlanSelector.options[vlanSelector.selectedIndex].value
      };

      state.updateEndpoint(endpoint);
      $('#add-endpoint-modal2').modal('hide');
    }.bind(this);

    this.parent.querySelector('.add-endpoint-cancel').onclick = function(e) {
      $('#add-endpoint-modal2').modal('hide');
    };

    // Perform initial form population
    loadVlanSelector({interface_id: interface_id});
  }

  async populateEntityForm(endpoint) {
    let entity_id = 1;
    let index = -1;

    if (endpoint !== null) {
      entity_id = endpoint.entity_id;
      index = endpoint.index;
    }

    this.parent.querySelector('.entity-search').oninput = function(search) {
      if (search.target.value.length < 2) {
        let list = this.parent.querySelector('.entity-search-list');
        list.innerHTML = '';
        return null;
      }

      // If entity search hasn't yet executed restart the countdown; The
      // search query was updated.
      clearTimeout(this.searchTimeout);

      // TODO FIX THIS
      this.searchTimeout = setTimeout(function() {
        getEntitiesAll(session.data.workgroup_id, search.target.value).then(function(entities) {
          let list = this.parent.querySelector('.entity-search-list');
          list.innerHTML = '';

          for (let i = 0; i < entities.length; i++) {
            let l = document.createElement('a');
            l.setAttribute('href', '#');
            l.setAttribute('class', 'list-group-item');
            l.innerText = entities[i].name;
            l.onclick = (e) => {
              search.target.value = '';
              list.innerHTML = '';

              entities[i].index = index;
              this.populateEntityForm(entities[i]);
            };
            list.appendChild(l);
          }
        }.bind(this));
      }.bind(this), 800);

      return 1;
    }.bind(this);

    let options = {};
    let entity = await getEntities(session.data.workgroup_id, entity_id, options);

    let list = this.parent.querySelector('.entity-list');
    list.innerHTML = '';

    if (entity === null) {
      list.innerHTML = `<div class="form-group"></div>`;
      return null;
    }

    let parent = null;
    if ('parents' in entity && entity.parents.length > 0) {
      parent = entity.parents[0];
    }

    let entities = '';
    let spacer = '';

    if (parent) {
      let elem = document.createElement('button');
      elem.setAttribute('type', 'button');
      elem.setAttribute('class', 'list-group-item active');
      elem.innerHTML = `<span class="glyphicon glyphicon-menu-up"></span>&nbsp;&nbsp; ${entity.name}`;
      elem.addEventListener('click', function(e) {
        parent.index = index;
        this.populateEntityForm(parent);
      }.bind(this));

      list.appendChild(elem);
      spacer = '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;';
    }

    if ('children' in entity && entity.children.length > 0) {
      for (let i = 0; i < entity.children.length; i++) {
        let child = entity.children[i];

        let elem = document.createElement('button');
        elem.setAttribute('type', 'button');
        elem.setAttribute('class', 'list-group-item');
        elem.innerHTML = `${spacer}${child.name} <span class="glyphicon glyphicon-menu-right" style="float: right;"></span>`;
        elem.addEventListener('click', function(e) {
          child.index = index;
          this.populateEntityForm(child);
        }.bind(this));

        list.appendChild(elem);
      }
    }

    // Once the user has selected a leaf entity it's expected that we
    // display all its associated ports.
    if ('children' in entity && entity.children.length === 0) {
      for (let i = 0; i < entity.interfaces.length; i++) {
        let child = entity.interfaces[i];

        let elem = document.createElement('button');
        elem.setAttribute('type', 'button');
        elem.setAttribute('class', 'list-group-item');
        elem.innerHTML = `${spacer}<b>${child.node}</b> ${child.name}`;
        elem.addEventListener('click', function(e) {
          // PopulateEntityForm(child.entity_id);
        });

        list.appendChild(elem);
      }
    }

    // VLAN Select
    let vlanSelector = this.parent.querySelector('.entity-vlans');
    vlanSelector.innerHTML = '';

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

    let vlan = -1;
    if (vlans.length > 0) {
      vlan = vlans[0];
    }
    if (endpoint !== null && 'tag' in endpoint) {
      vlan = endpoint.tag;
    }
    if (vlan !== -1 && !vlans.includes(vlan)) {
      vlans.unshift(vlan);
    }

    vlans.forEach((v) => {
      let o = document.createElement('option');
      o.innerText = `${v}`;
      o.setAttribute('value', v);

      if (v == vlan) {
        o.setAttribute('selected', true);
      }

      vlanSelector.appendChild(o);
    });

    if (vlan === -1) {
      vlanSelector.setAttribute('disabled', '');
    } else {
      vlanSelector.removeAttribute('disabled');
    }

    // Cloud Connection Input
    for (let i = 0; i < entity.interfaces.length; i++) {
      if (typeof entity.interfaces[i].cloud_interconnect_id === 'undefined') {
        continue;
      }
      entity.cloud_interconnect_id = entity.interfaces[i].cloud_interconnect_id;
      entity.cloud_interconnect_type = entity.interfaces[i].cloud_interconnect_type;
    }

    let cloudAccountLabel = this.parent.querySelector('.entity-cloud-account-label');
    cloudAccountLabel.innerText = 'AWS Account Owner';
    let cloudAccountInput = this.parent.querySelector('.entity-cloud-account');
    // TODO Set cloudAccountInput placeholder to something resembling
    // the expected input.

    if (!('cloud_interconnect_id' in entity) || entity.cloud_interconnect_id === null || entity.cloud_interconnect_id === 'null' || entity.cloud_interconnect_id === '') {
      entity.cloud_interconnect_id = null;
      entity.cloud_interconnect_type = '';
    } else {
      if (entity.cloud_interconnect_type === 'gcp-partner-interconnect') {
        cloudAccountLabel.innerText = 'GCP Pairing Key';
      } else if (entity.cloud_interconnect_type === 'azure-express-route') {
        cloudAccountLabel.innerText = 'ExpressRoute Service Key';
      }
    }

    let cloudAccount = this.parent.querySelector('.entity-cloud-account');
    if (entity.cloud_interconnect_id === null) {
      cloudAccount.style.display = 'none';
    } else {
      cloudAccount.style.display = 'block';
    }

    // Max Bandwidth
    let bandwidthSelector = this.parent.querySelector('.entity-bandwidth');
    bandwidthSelector.innerHTML = '';

    let bandwidthOptions  = [[0, 'Unlimited']];
    if (entity.cloud_interconnect_type === 'aws-hosted-connection') {
      bandwidthOptions = [
        [50, '50 Mb/s'],
        [100, '100 Mb/s'],
        [200, '200 Mb/s'],
        [300, '300 Mb/s'],
        [400, '400 Mb/s'],
        [500, '500 Mb/s'],
      ];
    } else if (entity.cloud_interconnect_type === 'gcp-partner-interconnect') {
      bandwidthOptions = [
        [50, '50 Mb/s'],
        [100, '100 Mb/s'],
        [200, '200 Mb/s'],
        [300, '300 Mb/s'],
        [400, '400 Mb/s'],
        [500, '500 Mb/s'],
        [1000, '1 Gb/s'],
        [2000, '2 Gb/s'],
        [5000, '5 Gb/s'],
        [10000, '10 Gb/s']
      ];
    }

    bandwidthOptions.forEach((b, i) => {
      let o = document.createElement('option');
      o.innerText = `${b[1]}`;
      o.setAttribute('value', b[0]);

      if (i == 0) {
        o.setAttribute('selected', true);
      }

      bandwidthSelector.appendChild(o);
    });

    if (vlan === -1) {
      bandwidthSelector.setAttribute('disabled', '');
    } else {
      bandwidthSelector.removeAttribute('disabled');
    }

    // TODO Buttons
    // if no interfaces no request access
    //    disabled add endpoint
    // else
    //   if no vlans request access
    //      disabled add endpoint

    let addButton = this.parent.querySelector('.add-entity-submit');
    addButton.onclick = function(e) {
      console.log('endpoint:', endpoint);
      console.log('entity:', entity);

      endpoint.bandwidth = bandwidthSelector.options[bandwidthSelector.selectedIndex].value;
      endpoint.tag = vlanSelector.options[vlanSelector.selectedIndex].value;
      endpoint.cloud_account_id = cloudAccountInput.value;
      endpoint.entity = entity.name;
      endpoint.name = 'TBD';
      endpoint.node = 'TBD';
      endpoint.interface = 'TBD';

      state.updateEndpoint(endpoint);
      $('#add-endpoint-modal2').modal('hide');
    };

    let cancelButton =this.parent.querySelector('.add-entity-cancel');
    cancelButton.onclick = function(e) {
      $('#add-endpoint-modal2').modal('hide');
    };

    let requestButton = this.parent.querySelector('.add-entity-request-access');
    if (entity.interfaces.length === 0) {
      addButton.setAttribute('disabled', '');
      requestButton.style.display = 'none';
    }
    if (vlans.length === 0) {
      addButton.setAttribute('disabled', '');

      if (entity.entity_id == 1 ) {
        requestButton.style.display = 'none';
      } else {
        requestButton.style.display = 'inline-block';
      }
    } else {
      addButton.removeAttribute('disabled');
      requestButton.style.display = 'none';
    }

    return 1;
  }
}

/**
 * EndpointSelectionModal populates #add-endpoint-modal with an entity
 * and interface selection form.
 *
 * let modal = new EndpointSelectionModal({
 *   index: 0,
 *   onEndpointSubmit: (e) => { }
 * });
 *
 */
class EndpointSelectionModal extends Component {
  constructor(props) {
    super();
    this.props = props || {};

    this.index = -1;
    this.props.index  = -1;
    this.props.entity = null;
    this.props.entityName = 'TBD';
    this.props.entityNode = 'TBD';

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

    // After Submit is called on the interface or entity
    // form. this.endpoint is populated with the endpoint. This can
    // later be referenced to get the state of the last selected
    // endpoint via this modal.
    this.endpoint = null;

    if ('onEndpointSubmit' in this.props) {
      this.onEndpointSubmit = this.props.onEndpointSubmit;
    } else {
      this.onEndpointSubmit = function(e) { console.log('Selected endpoint:', e); };
    }

    // Endpoints are also stored in sessionStorage. If the 'endpoints'
    // array hasn't yet been initialized, we create it here.
    let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
    if (endpoints === null) {
      sessionStorage.setItem('endpoints', JSON.stringify([]));
    }
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
        index: this.index
    };

    let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
    if (this.props.index >= 0) {
        entity.peerings = endpoints[this.props.index].peerings;
        endpoints[this.props.index] = entity;
    } else {
        endpoints.push(entity);
    }

    sessionStorage.setItem('endpoints', JSON.stringify(endpoints));
    this.onEndpointSubmit(entity);

    let entityAlert = document.querySelector('#entity-alert');
    entityAlert.innerHTML = '';
    entityAlert.style.display = 'none';
    let entityAlertOK = document.querySelector('#entity-alert-ok');
    entityAlertOK.innerHTML = '';
    entityAlertOK.style.display = 'none';

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
        tag: document.querySelector('#endpoint-vlans').value,
        index: this.index
    };

    let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
    if (this.props.index >= 0) {
        endpoint.peerings = endpoints[this.props.index].peerings;
        endpoints[this.props.index] = endpoint;
    } else {
        endpoints.push(endpoint);
    }

    sessionStorage.setItem('endpoints', JSON.stringify(endpoints));
    this.onEndpointSubmit(endpoint);

    let addEndpointModal = $('#add-endpoint-modal');
    addEndpointModal.modal('hide');
  }

  // props => { index: -1, endpoint: {} }
  // props => { index:  0, endpoint: { name: '...', node: '...' }
  async render(props) {
    this.index = ('index' in props) ? props.index : -1;

    let entityIsActive =  props.entity ? 'active': '';
    let intfIsActive = props.entity ? '' : 'active';
    if (props.entity === undefined) {
      props.entity = {};
    }

    let [entityForm, interfaceForm] = await Promise.all([
      this.entityForm.render({
        entity: props.entity.entity_id,
        vlan:   props.tag
      }),
      this.interfaceForm.render({
        interface: props.interface_id,
        vlan:      props.tag
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
