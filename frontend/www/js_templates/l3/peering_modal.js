class PeeringModal {
  constructor(query) {
    let template = document.querySelector('#template-l3-peering-modal');
    this.element = document.importNode(template.content, true);

    this.handleIpVersionChange = this.handleIpVersionChange.bind(this);
    this.display = this.display.bind(this);
    this.hide = this.hide.bind(this);
    this.onSubmit = this.onSubmit.bind(this);
    this.onCancel = this.onCancel.bind(this);

    this.element.querySelector('.cancel-peering-modal-button').addEventListener('click', function(e) {
      this.hide();
    }.bind(this));

    this.parent = document.querySelector(query);
    this.parent.innerHTML = '';
    this.parent.appendChild(this.element);
  }

  onSubmit(f) {
    this.parent.querySelector('.add-peering-modal-button').addEventListener('click', function(e) {
      let ipVersion = this.parent.querySelector(`.ip-version`).checked ? 6 : 4;
      let asn = this.parent.querySelector(`.bgp-asn`);
      if (!asn.validity.valid) {
        asn.reportValidity();
        return;
      }
      let yourPeerIP = this.parent.querySelector(`.your-peer-ip`);
      if (!yourPeerIP.validity.valid) {
        yourPeerIP.reportValidity();
        return;
      }
      let key = this.parent.querySelector(`.bgp-key`);
      if (!key.validity.valid) {
        key.reportValidity();
        return;
      }
      let oessPeerIP = this.parent.querySelector(`.oess-peer-ip`);
      if (!oessPeerIP.validity.valid) {
        oessPeerIP.reportValidity();
        return;
      }

      let peering = {
        ip_version: ipVersion,
        peer_asn: asn.value,
        md5_key: key.value,
        local_ip: oessPeerIP.value,
        peer_ip: yourPeerIP.value,
        operational_state: 'unknown'
      };

      f(peering);
      this.hide();
    }.bind(this));
  }

  onCancel(f) {
    this.parent.querySelector('.cancel-peering-modal-button').addEventListener('click', function(e) {
      f(e);
    }.bind(this));
  }

  handleIpVersionChange(e) {
    let ipv6 = this.parent.querySelector(`.ip-version`).checked;

    if (ipv6) {
      console.log('setting validators to ipv6');
      asIPv6CIDR(this.parent.querySelector(`.oess-peer-ip`));
      asIPv6CIDR(this.parent.querySelector(`.your-peer-ip`));
    } else {
      console.log('setting validators to ipv4');

      asIPv4CIDR(this.parent.querySelector(`.oess-peer-ip`));
      asIPv4CIDR(this.parent.querySelector(`.your-peer-ip`));
    }
  }

  display(peering) {
    if (peering === null) {
      this.parent.querySelector(`.ip-version`).checked = false;
      this.parent.querySelector(`.ip-version`).onchange = this.handleIpVersionChange;

      this.parent.querySelector(`.bgp-asn`).value = null;
      this.parent.querySelector(`.bgp-asn`).placeholder = 0;

      this.parent.querySelector(`.bgp-key`).value = null;
      this.parent.querySelector(`.bgp-key`).placeholder = '000000000000';

      this.parent.querySelector(`.your-peer-ip`).value = null;
      this.parent.querySelector(`.your-peer-ip`).placeholder = '192.168.1.2/31';

      this.parent.querySelector(`.oess-peer-ip`).value = null;
      this.parent.querySelector(`.oess-peer-ip`).placeholder = '192.168.1.3/31';
    }
    this.handleIpVersionChange();

    $('#add-endpoint-peering-modal').modal('show');
  }

  hide() {
    $('#add-endpoint-peering-modal').modal('hide');
  }
}
