class CircuitHeader extends Component {
  constructor(state) {
    super();
    this.state = state;
  }

  async render(props) {
    let [circuit] = await Promise.all([
      getCircuit(props.id),
    ]);

    return `
<h2>${circuit.description} <small>${circuit.circuit_id}</small></h2>
<hr/>
`;
  }
}

class Circuit extends Component {
  constructor(state) {
    super();
    this.state = state;
  }

  async render(props) {
    let [circuit,events,history,raw] = await Promise.all([
      getCircuit(props.id),
      getCircuitEvents(props.id),
      getCircuitHistory(props.id),
      getRawCircuit(props.id)
    ]);

    console.log(circuit);
    // console.log(events);
    // console.log(history);
    // console.log(raw);

    let historyRows = '';
    for (let i = 0; i < history.length; i++) {
      let h = history[i];
      historyRows += `<tr><td>${h.fullname}</td><td>${h.reason}</td><td>${h.activated}</td></tr>`;
    }

    let eventRows = '';
    for (let i = 0; i < events.length; i++) {
      let e = events[i];
      eventRows += `<tr><td>${e.fullname}</td><td>${e.reason}</td><td>${e.activated}</td></tr>`;
    }

    return `
<div>

  <ul class="nav nav-tabs" role="tablist">
    <li role="presentation" class="active">
      <a href="#home" aria-controls="home" role="tab" data-toggle="tab">Details</a>
    </li>
    <li role="presentation">
      <a href="#profile" aria-controls="profile" role="tab" data-toggle="tab">History</a>
    </li>
    <li role="presentation">
      <a href="#messages" aria-controls="messages" role="tab" data-toggle="tab">Events</a>
    </li>
    <li role="presentation">
      <a href="#settings" aria-controls="settings" role="tab" data-toggle="tab">Raw</a>
    </li>
  </ul>

  <!-- Tab panes -->
  <div class="tab-content">
    <br/>

    <div role="tabpanel" class="tab-pane active" id="home">

      <div class="form-horizontal">
        <div class="form-group">
          <label class="col-sm-3 control-label">Status</label>
          <div class="col-sm-9"><p class="form-control-static">${circuit.state}</p></div>
        </div>
        <div class="form-group">
          <label class="col-sm-3 control-label">Created on</label>
          <div class="col-sm-9"><p class="form-control-static">${circuit.created_on}</p></div>
        </div>
        <div class="form-group">
          <label class="col-sm-3 control-label">Created by</label>
          <div class="col-sm-9"><p class="form-control-static">${circuit.created_by.email}</p></div>
        </div>
        <div class="form-group">
          <label class="col-sm-3 control-label">Modified on</label>
          <div class="col-sm-9"><p class="form-control-static">${circuit.last_edited}</p></div>
        </div>
        <div class="form-group">
          <label class="col-sm-3 control-label">Modified by</label>
          <div class="col-sm-9"><p class="form-control-static">${circuit.last_modified_by.email}</p></div>
        </div>
      </div>

    </div>
    <div role="tabpanel" class="tab-pane" id="profile">

      <table align="left" class="table table-condensed">
        <thead style="font-weight: bold">
          <tr><th>User</th><th>Event</th><th>Date / Time</th></tr>
        </thead>
        <tbody>${historyRows}</tbody>
      </table>

    </div>
    <div role="tabpanel" class="tab-pane" id="messages">
      <table align="left" class="table table-condensed">
        <thead style="font-weight: bold">
          <tr><th>User</th><th>Event</th><th>Start Date / Time</th><th>End Date / Time</th></tr>
        </thead>
        <tbody>${eventRows}</tbody>
      </table>
    </div>
    <div role="tabpanel" class="tab-pane" id="settings">
      <pre>${raw}</pre>
    </div>
  </div>

</div>
`;
  }
}
