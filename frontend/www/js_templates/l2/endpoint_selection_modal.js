class EndpointSelectionModal2 {
  constructor(query) {
    let template = document.querySelector('#endpoint-selection-modal2');
    this.element = document.importNode(template.content, true);

    this.endpoint = null;
    this.searchTimeout = null;

    this.parent = document.querySelector(query);
    this.parent.appendChild(this.element);
  }

  display(endpoint) {
    this.endpoint = endpoint;

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
    let selectedBandwidth = null;

    if (endpoint !== undefined && endpoint !== null) {
      interface_id = endpoint.interface_id;
      index = endpoint.index;
      selectedBandwidth = endpoint.bandwidth || null;
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

        if ( (selectedBandwidth === null && i == 0) || b[0] == selectedBandwidth) {
          o.setAttribute('selected', true);
        }

        bandwidthSelector.appendChild(o);
      });

      if (vlan === -1 || bandwidthOptions.length === 1) {
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

      if (this.endpoint === null) {
        this.endpoint = { index: index };
      }
      this.endpoint.bandwidth = this.parent.querySelector('.endpoint-bandwidth').value;
      this.endpoint.name = interfaceSelector.options[interfaceSelector.selectedIndex].dataset.name;
      this.endpoint.interface = interfaceSelector.options[interfaceSelector.selectedIndex].dataset.name;
      this.endpoint.interface_id = interfaceSelector.options[interfaceSelector.selectedIndex].value;
      this.endpoint.description = interfaceSelector.options[interfaceSelector.selectedIndex].dataset.description;
      this.endpoint.node = interfaceSelector.options[interfaceSelector.selectedIndex].dataset.node;
      this.endpoint.entity = null;
      this.endpoint.entity_id = null;
      this.endpoint.peerings = [];
      this.endpoint.cloud_account_id = '';
      this.endpoint.tag = vlanSelector.options[vlanSelector.selectedIndex].value;
      this.endpoint.jumbo = this.parent.querySelector('.endpoint-jumbo-frames').checked;
      this.endpoint.cloud_interconnect_type = interconnectType;

      state.updateEndpoint(this.endpoint);
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
    let selectedCloudAccountId = null;
    let selectedBandwidth = null;

    if (endpoint !== undefined && endpoint !== null) {
      entity_id = endpoint.entity_id;
      index = endpoint.index;
      selectedInterface = endpoint.interface || 'TBD';
      selectedNode = endpoint.node || 'TBD';
      selectedCloudAccountId = endpoint.cloud_account_id || null;
      selectedBandwidth = endpoint.bandwidth || null;
    }

    this.parent.querySelector('.entity-search').oninput = function(search) {
      let list = this.parent.querySelector('.entity-search-list');
      if (search.target.value.length < 2) {
        list.innerHTML = '';
        list.style.display = 'none';
        return null;
      }

      // If entity search hasn't yet executed restart the countdown; The
      // search query was updated.
      clearTimeout(this.searchTimeout);

      this.searchTimeout = setTimeout(function() {
        getEntitiesAll(session.data.workgroup_id, search.target.value).then(function(entities) {
          list.innerHTML = '';
          list.style.display = 'block';

          for (let i = 0; i < entities.length; i++) {
            let l = document.createElement('a');
            l.setAttribute('href', '#');
            l.setAttribute('class', 'list-group-item');
            l.innerText = entities[i].name;
            l.onclick = (e) => {
              search.target.value = '';
              list.innerHTML = '';
              list.style.display = 'none';

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
      let elem = document.createElement('a');
      elem.setAttribute('href', '#');
      elem.setAttribute('class', 'list-group-item active');
      elem.innerHTML = `<span class="glyphicon glyphicon-menu-left"></span>&nbsp;&nbsp; ${entity.name}`;
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

        let elem = document.createElement('a');
        elem.setAttribute('href', '#');
        elem.setAttribute('class', 'list-group-item');
        elem.innerHTML = `${spacer}${child.name} <span class="glyphicon glyphicon-menu-right" style="float: right;"></span>`;
        elem.addEventListener('click', function(e) {
          child.index = index;
          this.populateEntityForm(child);
        }.bind(this));

        list.appendChild(elem);
      }
    }

    // Display all interfaces of the selected Entity. If the Entity
    // describes a cloud interconnect, disable the Interfaces as they
    // will be auto-selected according to the prescribed procedure.
    for (let i = 0; i < entity.interfaces.length; i++) {
      let child = entity.interfaces[i];

      let autoSelectedInterface = (entity.interfaces[i].cloud_interconnect_type == "azure-express-route" || entity.interfaces[i].cloud_interconnect_type == "gcp-cloud-interconnect");

      let checked = 'checked';
      let disabled = '';
      let notAllow = '';


      if (autoSelectedInterface) {
        checked = '';
        disabled = 'disabled';
        notAllow = 'cursor: not-allowed;';
      }
      let elem = document.createElement('li');
      elem.setAttribute('class', `list-group-item ${disabled}`);
      if (child.cloud_interconnect_type != null){
      elem.innerHTML = `
            <div class="radio" style="margin: 0; padding: 0;">
              <label style="width: 100%; ${notAllow}">
                <input type="radio"
                       name="optionsRadios"
                       id="${child.node} ${child.name}"
                       value="${child.node} ${child.name}"
                       ${checked}
                       ${disabled}
                />
                <b> ${child.node}</b> ${child.name} <br/><span>${child.utilized_bandwidth}Mb reserved / ${child.bandwidth}Mb total</span>    
                </label>
            </div>`;
      }
      else{
      elem.innerHTML = `
           <div class="radio" style="margin: 0; padding: 0;">
              <label style="width: 100%; ${notAllow}">
                <input type="radio"
                       name="optionsRadios"
                       id="${child.node} ${child.name}"
                       value="${child.node} ${child.name}"
                       ${checked}
                       ${disabled}
                />
                <b> ${child.node}</b> ${child.name}</br>    
                </label>
            </div>`; 
      }
      elem.addEventListener('click', function(e) {
        selectedInterface = child.name;
        selectedNode = child.node;

        populateVLANs('.entity-vlans');
      });

      if (!autoSelectedInterface) {
        selectedInterface = child.name;
        selectedNode = child.node;
      }
      list.appendChild(elem);
    }

    // VLAN Select - Populates a select element with the VLANs
    // available for the currently selected (node, interface).
    const populateVLANs = (selector) => {
      let vlanSelector = this.parent.querySelector(selector);
      vlanSelector.innerHTML = '';

      let vlans = [];
      let vlanH = {};
      for (let i = 0; i < entity.interfaces.length; i++) {
        console.log('selectedInterface:', selectedInterface);
        console.log('selectedNode:', selectedNode);
        console.log('entity interfaces:', entity.interfaces[i]);

        let autoSelectedInterface = (entity.interfaces[i].cloud_interconnect_type == "azure-express-route" || entity.interfaces[i].cloud_interconnect_type == "gcp-cloud-interconnect");
        let userSelectedInterface = (entity.interfaces[i].node == selectedNode && entity.interfaces[i].name == selectedInterface);

        if (autoSelectedInterface || userSelectedInterface) {
          for (let j = 0; j < entity.interfaces[i].available_vlans.length; j++) {
            vlanH[entity.interfaces[i].available_vlans[j]] = 1;
          }
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

      return vlans;
    };

    let vlans = populateVLANs('.entity-vlans');
    let vlan = -1;
    if (vlans.length > 0) {
      vlan = vlans[0];
    }
    let vlanSelector = this.parent.querySelector('.entity-vlans');

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
    let cloudGatewayFormGroup = this.parent.querySelector('.form-group.entity-cloud-gateway-type');
    let cloudGatewayTypeSelector = this.parent.querySelector('.form-control.entity-cloud-gateway-type');
    let vlanHelp = this.parent.querySelector('.entity-vlans-help');

    cloudAccountFormGroup.style.display = 'none';
    cloudGatewayFormGroup.style.display = 'none';
    cloudAccountInput.value = selectedCloudAccountId;

    if (entity.cloud_interconnect_type !== null) {
      cloudAccountFormGroup.style.display = 'block';

      if (entity.cloud_interconnect_type === 'gcp-partner-interconnect') {
        cloudAccountLabel.innerText = 'GCP Pairing Key';
        cloudAccountInput.setAttribute('placeholder', '00000000-0000-0000-0000-000000000000/us-east1/1');
      } else if (entity.cloud_interconnect_type === 'azure-express-route') {
        cloudAccountLabel.innerText = 'ExpressRoute Service Key';
        cloudAccountInput.setAttribute('placeholder', '00000000-0000-0000-0000-000000000000');
        vlanHelp.dataset.content = '<b>Layer 2</b>: sTag of the QinQ Tagged Interface connecting to Microsoft Azure; This value will be overridden by Microsoft after provisioning.<br/><b>Layer 3</b>: cTag of the QinQ Tagged Interface connecting to Microsoft Azure. The sTag is selected by Microsoft and cannot be specified.';
      } else if (entity.cloud_interconnect_type === 'aws-hosted-connection') {
        cloudAccountLabel.innerText = 'AWS Account Owner';
        cloudAccountInput.setAttribute('placeholder', '012301230123');
        cloudGatewayFormGroup.style.display = 'block';
      } else {
        cloudAccountLabel.innerText = 'AWS Account Owner';
        cloudAccountInput.setAttribute('placeholder', '012301230123');
      }
    } else {
      vlanHelp.dataset.content = `VLAN Identifier of the tagged interface connecting to <b>${entity.name}.</b>`;
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
        [1000, '1 Gb/s'],
        [2000, '2 Gb/s'],
        [5000, '5 Gb/s']
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

      if ( (selectedBandwidth === null && i == 0) || b[0] == selectedBandwidth) {
        o.setAttribute('selected', true);
      }

      bandwidthSelector.appendChild(o);
    });

    if (vlan === -1 || bandwidthOptions.length === 1) {
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
        if (endpoint.mtu > 8500) {
          cloudGatewayTypeSelector.value = 'private';
        } else {
          cloudGatewayTypeSelector.value = 'transit';
        }
      } else {
        jumboCheckbox.checked = false;
      }
    }

    let addButton = this.parent.querySelector('.add-entity-submit');
    addButton.onclick = function(e) {
      console.log('endpoint:', endpoint);
      console.log('entity:', entity);

      let cloudGatewayType = null;
      if (entity.cloud_interconnect_type === 'aws-hosted-connection') {
        cloudGatewayType = cloudGatewayTypeSelector.options[cloudGatewayTypeSelector.selectedIndex].value;
        if (jumboCheckbox.checked) {
          endpoint.mtu = (cloudGatewayType === 'transit') ? 8500 : 9001;
        } else {
          endpoint.mtu = 1500;
        }
      }

      endpoint.bandwidth = bandwidthSelector.options[bandwidthSelector.selectedIndex].value;
      endpoint.tag = vlanSelector.options[vlanSelector.selectedIndex].value;
      endpoint.cloud_account_id = (cloudAccountInput.value) ? cloudAccountInput.value.trim() : '';
      endpoint.entity = entity.name;
      endpoint.name = selectedInterface;
      endpoint.node = selectedNode;
      endpoint.interface = selectedInterface;
      endpoint.jumbo = jumboCheckbox.checked;
      endpoint.cloud_interconnect_type = entity.cloud_interconnect_type;
      endpoint.cloud_gateway_type = cloudGatewayType;

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
