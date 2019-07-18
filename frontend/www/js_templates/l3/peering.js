class Peering {
  constructor(props) {
    this.props = props;
  }

  render() {
    return `
    <tr>
      <td>${this.props.ipVersion === 4 ? 'ipv4' : 'ipv6'}</td>
      <td>${this.props.asn}</td>
      <td>${this.props.yourPeerIP}</td>
      <td>${this.props.cloudAccountType ? '*****' : this.props.key}</td>
      <td>${this.props.oessPeerIP}</td>
      <td>
        <button class="btn btn-danger btn-sm"
                type="button"
                onclick="deletePeering(${this.props.endpointIndex}, ${this.props.index})">
          &nbsp;<span class="glyphicon glyphicon-trash"></span>&nbsp;
        </button>
      </td>
    </tr>
    `;
  }
}

class Peering2 {
  constructor(parent, peering) {
    let template = document.querySelector('#template-l3-peering2');
    this.element = document.importNode(template.content, true);

    this.index = peering.index;
    this.endpointIndex = peering.endpointIndex;

    this.element.querySelector('.ip-version').innerHTML = `IPv${peering.ipVersion}`;
    this.element.querySelector('.peer-asn').innerHTML = peering.asn;
    this.element.querySelector('.peer-ip').innerHTML = peering.yourPeerIP;
    this.element.querySelector('.key').innerHTML = peering.key;
    this.element.querySelector('.oess-ip').innerHTML = peering.oessPeerIP;

    this.onDelete = this.onDelete.bind(this);

    this.parent = parent;
    this.parent.appendChild(this.element);
  }

  onDelete(f) {
    this.parent.querySelectorAll('.delete-peering-button')[this.index].addEventListener('click', f);
  }
}
