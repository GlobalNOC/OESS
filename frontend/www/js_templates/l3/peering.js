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
      <td>${this.props.cloudAccountType ? '' : this.props.key}</td>
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
