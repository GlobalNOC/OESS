class EndpointSelectionModal2 {
  constructor(query) {
    let template = document.querySelector('#endpoint-selection-modal2');
    this.element = document.importNode(template.content, true);

    this.searchTimeout = null;

    this.parent = document.querySelector(query);
    this.parent.appendChild(this.element);
  }

  display(endpoint) {
    if (endpoint !== undefined && endpoint !== null && endpoint.interface === 'TBD') {
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

    if (endpoint !== undefined && endpoint !== null) {
      interface_id = endpoint.interface_id;
      index = endpoint.index;
    }

    let interfaceSelector = this.parent.querySelector('.endpoint-select-interface');
    let vlanSelector = this.parent.querySelector('.endpoint-select-vlan');
    let bandwidthSelector = this.parent.querySelector('.endpoint-bandwidth');
    let jumboCheckbox = this.parent.querySelector('.endpoint-jumbo-frames');

    interfaceSelector.innerHTML = '';
    interfaces.forEach((i) => {
      let o = document.createElement('option');
      o.innerText = `${i.node} ${i.name}`;
      o.setAttribute('value', i.interface_id);
      o.dataset.name = i.name;
      o.dataset.node = i.node;
      o.dataset.description = i.description;
      o.dataset.cloud_interconnect_type = i.cloud_interconnect_type;

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

      if (endpoint !== undefined && endpoint !== null) {
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

      // Max Bandwidth
      bandwidthSelector.innerHTML = '';

      let cloud_interconnect_type = interfaceSelector.options[interfaceSelector.selectedIndex].dataset.cloud_interconnect_type;

      let bandwidthOptions  = [[0, 'Unlimited']];
      if (cloud_interconnect_type === 'aws-hosted-connection') {
        bandwidthOptions = [
          [50, '50 Mb/s'],
          [100, '100 Mb/s'],
          [200, '200 Mb/s'],
          [300, '300 Mb/s'],
          [400, '400 Mb/s'],
          [500, '500 Mb/s'],
          [1000, '1 Gb/s'],
          [2000, '2 Gb/s'],
          [5000, '5 Gb/s']
        ];
      } else if (cloud_interconnect_type === 'gcp-partner-interconnect') {
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

      // Jumbo Frames
      if (cloud_interconnect_type === 'aws-hosted-connection') {
        jumboCheckbox.checked = true;
        jumboCheckbox.removeAttribute('disabled');
      } else if (cloud_interconnect_type === 'aws-hosted-vinterface') {
        jumboCheckbox.checked = true;
        jumboCheckbox.removeAttribute('disabled');
      } else if (cloud_interconnect_type === 'gcp-partner-interconnect') {
        jumboCheckbox.checked = false;
        jumboCheckbox.setAttribute('disabled', '');
      } else if (cloud_interconnect_type === 'azure-express-route') {
        jumboCheckbox.checked = false;
        jumboCheckbox.setAttribute('disabled', '');
      } else {
        jumboCheckbox.checked = true;
        jumboCheckbox.removeAttribute('disabled');
      }

      if (endpoint !== undefined && endpoint !== null && 'jumbo' in endpoint) {
        if (endpoint.jumbo == 1 || endpoint.jumbo == true) {
          jumboCheckbox.checked = true;
        } else {
          jumboCheckbox.checked = false;
        }
      }
    };

    // If the interface is changed we need reload the vlan selection
    interfaceSelector.onchange = loadVlanSelector;

    // Setup interface-add and interface-cancel callbacks
    this.parent.querySelector('.add-endpoint-submit').onclick = function(e) {
      let interconnectType = interfaceSelector.options[interfaceSelector.selectedIndex].dataset.cloud_interconnect_type;
      if (interconnectType === 'null') {
        interconnectType = null;
      }

      let endpoint = {
        index:            index,
        bandwidth:        this.parent.querySelector('.endpoint-bandwidth').value,
        interface:        interfaceSelector.options[interfaceSelector.selectedIndex].dataset.name,
        interface_id:     interfaceSelector.options[interfaceSelector.selectedIndex].value,
        description:      interfaceSelector.options[interfaceSelector.selectedIndex].dataset.description,
        node:             interfaceSelector.options[interfaceSelector.selectedIndex].dataset.node,
        entity:           null, // entity,
        entity_id:        null, // entity_id,
        peerings:         [],
        cloud_account_id: '',
        tag:              vlanSelector.options[vlanSelector.selectedIndex].value,
        jumbo:            this.parent.querySelector('.endpoint-jumbo-frames').checked,
        cloud_interconnect_type: interconnectType
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
    let selectedInterface = 'TBD';
    let selectedNode = 'TBD';

    if (endpoint !== undefined && endpoint !== null) {
      entity_id = endpoint.entity_id;
      index = endpoint.index;
      selectedInterface = endpoint.interface || 'TBD';
      selectedNode = endpoint.node || 'TBD';
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
          selectedInterface = child.name;
          selectedNode = child.node;
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
    if (endpoint !== undefined && endpoint !== null && 'tag' in endpoint) {
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
    entity.cloud_interconnect_type = null;

    for (let i = 0; i < entity.interfaces.length; i++) {
      if (typeof entity.interfaces[i].cloud_interconnect_id === 'undefined') {
        continue;
      }
      entity.cloud_interconnect_type = entity.interfaces[i].cloud_interconnect_type;
    }

    let cloudAccountFormGroup = this.parent.querySelector('.entity-cloud-account');
    let cloudAccountLabel = this.parent.querySelector('.entity-cloud-account-label');
    let cloudAccountInput = this.parent.querySelector('.entity-cloud-account-id');

    cloudAccountFormGroup.style.display = 'none';
    cloudAccountInput.value = null;

    if (entity.cloud_interconnect_type !== null) {
      cloudAccountFormGroup.style.display = 'block';

      if (entity.cloud_interconnect_type === 'gcp-partner-interconnect') {
        cloudAccountLabel.innerText = 'GCP Pairing Key';
        cloudAccountInput.setAttribute('placeholder', '00000000-0000-0000-0000-000000000000/us-east1/1');
      } else if (entity.cloud_interconnect_type === 'azure-express-route') {
        cloudAccountLabel.innerText = 'ExpressRoute Service Key';
        cloudAccountInput.setAttribute('placeholder', '00000000-0000-0000-0000-000000000000');
      } else {
        cloudAccountLabel.innerText = 'AWS Account Owner';
        cloudAccountInput.setAttribute('placeholder', '012301230123');
      }
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

    // Jumbo Frames
    let jumboCheckbox = this.parent.querySelector('.entity-jumbo-frames');

    if (entity.cloud_interconnect_type === 'aws-hosted-connection') {
      jumboCheckbox.checked = true;
      jumboCheckbox.removeAttribute('disabled');
    } else if (entity.cloud_interconnect_type === 'aws-hosted-vinterface') {
      jumboCheckbox.checked = true;
      jumboCheckbox.removeAttribute('disabled');
    } else if (entity.cloud_interconnect_type === 'gcp-partner-interconnect') {
      jumboCheckbox.checked = false;
      jumboCheckbox.setAttribute('disabled', '');
    } else if (entity.cloud_interconnect_type === 'azure-express-route') {
      jumboCheckbox.checked = false;
      jumboCheckbox.setAttribute('disabled', '');
    } else {
      jumboCheckbox.checked = true;
      jumboCheckbox.removeAttribute('disabled');
    }

    if (endpoint !== undefined && endpoint !== null && 'jumbo' in endpoint) {
      if (endpoint.jumbo == 1 || endpoint.jumbo == true) {
        jumboCheckbox.checked = true;
      } else {
        jumboCheckbox.checked = false;
      }
    }

    let addButton = this.parent.querySelector('.add-entity-submit');
    addButton.onclick = function(e) {
      console.log('endpoint:', endpoint);
      console.log('entity:', entity);

      endpoint.bandwidth = bandwidthSelector.options[bandwidthSelector.selectedIndex].value;
      endpoint.tag = vlanSelector.options[vlanSelector.selectedIndex].value;
      endpoint.cloud_account_id = cloudAccountInput.value;
      endpoint.entity = entity.name;
      endpoint.name = selectedInterface;
      endpoint.node = selectedNode;
      endpoint.interface = selectedInterface;
      endpoint.jumbo = jumboCheckbox.checked;
      endpoint.cloud_interconnect_type = entity.cloud_interconnect_type;

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
