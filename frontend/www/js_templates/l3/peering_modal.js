class PeeringModal {
  constructor(query) {
    let template = document.querySelector('#template-l3-peering-modal');
    this.element = document.importNode(template.content, true);

    // this.index = endpoint.index;
    // TODO - Remove
    this.index = 0;

    this.element.querySelector('.add-peering-modal-button').addEventListener('click', function(e) {
      let ipVersion = this.parent.querySelector(`.ip-version`);
      if (!ipVersion.validity.valid) {
        ipVersion.reportValidity();
        return;
      }
      let asn = this.parent.querySelectorAll(`.bgp-asn`)[this.index];
      if (!asn.validity.valid) {
        asn.reportValidity();
        return;
      }
      let yourPeerIP = this.parent.querySelectorAll(`.your-peer-ip`)[this.index];
      if (!yourPeerIP.validity.valid) {
        yourPeerIP.reportValidity();
        return;
      }
      let key = this.parent.querySelectorAll(`.bgp-key`)[this.index];
      if (!key.validity.valid) {
        key.reportValidity();
        return;
      }
      let oessPeerIP = this.parent.querySelectorAll(`.oess-peer-ip`)[this.index];
      if (!oessPeerIP.validity.valid) {
        oessPeerIP.reportValidity();
        return;
      }

      let ipVersionNo = ipVersion.checked ? 6 : 4;

      let peering = {
        ipVersion: ipVersionNo,
        asn: asn.value,
        key: key.value,
        oessPeerIP: oessPeerIP.value,
        yourPeerIP: yourPeerIP.value
      };

      // endpoint.peerings.push(peering);
      // state.updateEndpoint(endpoint);
      console.log(peering);

      update();
    }.bind(this));

    this.element.querySelector('.cancel-peering-modal-button').addEventListener('click', function(e) {
      this.hide();
    }.bind(this));

    this.parent = document.querySelector(query);
    this.parent.appendChild(this.element);
  }

  display(peering) {
    $('#add-endpoint-peering-modal').modal('show');
  }

  hide() {
    $('#add-endpoint-peering-modal').modal('hide');
  }
}
