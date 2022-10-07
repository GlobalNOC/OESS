class Endpoint2 {
  constructor(query, endpoint) {
    let template = document.querySelector('#template-layer3-endpoint');
    this.element = document.importNode(template.content, true);

    this.index = endpoint.index;

    let entity = this.element.querySelector('.entity');

    if (endpoint.state == 'in-review') {
      this.element.querySelector('.panel').classList.remove('panel-default')
      this.element.querySelector('.panel').classList.add('panel-warning')
      this.element.querySelector('.panel-heading').innerHTML = 'Pending Approval';
    } else {
      this.element.querySelector('.panel-heading').style.display = 'none';
    }

    this.element.querySelector('.entity').innerHTML = endpoint.entity || 'NA';
    this.element.querySelector('.node').innerHTML = endpoint.node;
    this.element.querySelector('.interface').innerHTML = endpoint.interface;
    this.element.querySelector('.interface-description').innerHTML = endpoint.description;
    this.element.querySelector('.tag').innerHTML = endpoint.tag;
    this.element.querySelector('.inner-tag').innerHTML = endpoint.inner_tag || null;
    this.element.querySelector('.bandwidth').innerHTML = (endpoint.bandwidth == null || endpoint.bandwidth == 0) ? 'Unlimited' : `${endpoint.bandwidth} Mb/s`;

    if ('mtu' in endpoint) {
      this.element.querySelector('.mtu').innerHTML = endpoint.mtu;
    } else {
      this.element.querySelector('.mtu').innerHTML = (endpoint.jumbo) ? 'Jumbo' : 'Standard';
    }

    if (endpoint.inner_tag === undefined || endpoint.inner_tag === null || endpoint.inner_tag === '') {
      Array.from(this.element.querySelectorAll('.d1q')).map(e => e.style.display = 'block');
      Array.from(this.element.querySelectorAll('.qnq')).map(e => e.style.display = 'none');
    } else {
      Array.from(this.element.querySelectorAll('.d1q')).map(e => e.style.display = 'none');
      Array.from(this.element.querySelectorAll('.qnq')).map(e => e.style.display = 'block');
    }

    this.element.querySelector('.endpoint-buttons').style.display = (endpoint.editable) ? 'block' : 'none';
    this.element.querySelector('.add-peering-button').style.display = (endpoint.editable) ? 'block' : 'none';

    this.element.querySelector('.modify-endpoint-button').addEventListener('click', function(e) {
      modal.display(endpoint);
    });

    this.element.querySelector('.delete-endpoint-button').addEventListener('click', function(e) {
      state.deleteEndpoint(endpoint.index);
      update();
    });

    this.element.querySelector('.view-endpoint-configuration-button').addEventListener('click', function(e) {
      let modal = new ConfigurationModal(document.querySelector('#configuration-modal-container'));
      modal.display(endpoint);
    }.bind(this));

    this.element.querySelector('.add-peering-button').addEventListener('click', function(e) {
      let modal = new PeeringModal('#peering-modal', endpoint, endpoint.cloud_interconnect_type);
      modal.onSubmit((peering) => {
        if (!'peerings' in endpoint) {
          endpoint.peers = [];
        }

        endpoint.peers.push(peering);
        state.updateEndpoint(endpoint);

        update();
      });
      modal.display(null, endpoint.cloud_interconnect_type);


    }.bind(this));

    this.peerings = this.peerings.bind(this);

    this.parent = document.querySelector(query);
    this.parent.appendChild(this.element);
  }

  peerings() {
    return this.parent.querySelectorAll('.peerings')[this.index];
  }
}
