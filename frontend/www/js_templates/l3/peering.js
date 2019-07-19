class Peering2 {
  constructor(parent, peering) {
    let template = document.querySelector('#template-l3-peering2');
    this.element = document.importNode(template.content, true);

    this.index = peering.index;
    this.endpointIndex = peering.endpointIndex;

    let stateDisplay = '';
    if (peering.operational_state === 'up') {
      stateDisplay = '<span class="glyphicon glyphicon-circle-arrow-up" aria-hidden="true" style="color: #5CB85C"></span>';
    } else if (peering.operational_state === 'down') {
      stateDisplay = '<span class="glyphicon glyphicon-circle-arrow-down" aria-hidden="true" style="color: #D9534E"></span>';
    } else {
      stateDisplay = '<span class="glyphicon glyphicon-question-sign" aria-hidden="true" style="color: #aaa"></span>';
    }

    this.element.querySelector('.operational-state').innerHTML = stateDisplay;
    this.element.querySelector('.ip-version').innerHTML = `IPv${peering.ip_version}`;
    this.element.querySelector('.peer-asn').innerHTML = peering.peer_asn;
    this.element.querySelector('.peer-ip').innerHTML = peering.peer_ip;
    this.element.querySelector('.key').innerHTML = peering.md5_key;
    this.element.querySelector('.oess-ip').innerHTML = peering.local_ip;

    this.element.querySelector('.delete-peering-button').style.display = (peering.editable) ? 'block' : 'none';

    this.onDelete = this.onDelete.bind(this);

    this.parent = parent;
    this.parent.appendChild(this.element);
  }

  onDelete(f) {
    this.parent.querySelectorAll('.delete-peering-button')[this.index].addEventListener('click', f);
  }
}
