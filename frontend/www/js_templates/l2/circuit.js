class CircuitRaw extends Component {
  constructor(state) {
    super();
    this.state = state;
  }

  async render(props) {
    return `
      <pre>${props.raw}</pre>
`;
  }
}

class CircuitEvents extends Component {
  constructor(state) {
    super();
    this.state = state;
  }

  async render(props) {
    let eventRows = '';
    for (let i = 0; i < props.events.length; i++) {
      let e = props.events[i];
      eventRows += `<tr><td>${e.fullname}</td><td>${e.reason}</td><td>${e.activated}</td></tr>`;
    }

    return `
      <table align="left" class="table table-condensed">
        <thead style="font-weight: bold">
          <tr><th>User</th><th>Event</th><th>Start Date / Time</th><th>End Date / Time</th></tr>
        </thead>
        <tbody>${eventRows}</tbody>
      </table>
`;
  }
}


class CircuitHistory extends Component {
  constructor(state) {
    super();
    this.state = state;
  }

  async render(props) {
    let historyRows = '';
    let history = (props.history == null) ? [] : props.history;

    for (let i = 0; i < history.length; i++) {
      let h = history[i];
      historyRows += `<tr><td>${h.fullname}</td><td>${h.reason}</td><td>${h.activated}</td></tr>`;
    }

    return `
      <table align="left" class="table table-condensed">
        <thead style="font-weight: bold">
          <tr><th>User</th><th>Event</th><th>Date / Time</th></tr>
        </thead>
        <tbody>${historyRows}</tbody>
      </table>
`;
  }
}

class ResourceHistoryTable extends Component {
  constructor(state) {
    super();
    this.state = state;
  }

  async render(props) {
    
    let historyRows = '';
    let href = {
      l3connection: function(data) { return `index.cgi?action=modify_cloud&vrf_id=${data.vrf_id}`; }
    };
    let history = (props.history == null) ? [] : props.history;

    for (let i = 0; i < history.length; i++) {
      let h = history[i];
      h.object = JSON.parse(JSON.stringify(h.object));

      let date = new Date(h.date * 1000).toLocaleDateString("en-US", { year: 'numeric', month: 'long', day: 'numeric' });
      let time = new Date(h.date * 1000).toLocaleTimeString("en-US", {hour: 'numeric', minute: 'numeric', timeZoneName: 'short'});

      historyRows += `
        <tr class="table-hover">
          <td>${h.full_name}</td>
          <td><a href="${href[h.type](JSON.parse(h.object))}"><code>${h.resource_id}</code></a></td>
          <td>${h.event}</td>
          <td>l3connection</td>
          <td>${date} ${time}</td>
        </tr>
      `;
    }

    return `
      <table class="table table-hover" style="margin-top: 2em">
        <thead style="font-weight: bold">
          <tr><th>User</th><th>Resource ID</th><th>Event</th><th>Type</th><th>Date / Time</th></tr>
        </thead>
        <tbody>
          ${historyRows}
        </tbody>
      </table>
    `;
  }
}

class CircuitDetails extends Component {
  constructor(state) {
    super();
    this.state = state;
  }

  async render(props) {
    return `
      <div class="form-horizontal">
        <div class="form-group">
          <label class="col-sm-3 control-label">Status</label>
          <div class="col-sm-9"><p class="form-control-static">${props.state}</p></div>
        </div>
        <div class="form-group">
          <label class="col-sm-3 control-label">Created on</label>
          <div class="col-sm-9"><p class="form-control-static">${props.created_on}</p></div>
        </div>
        <div class="form-group">
          <label class="col-sm-3 control-label">Created by</label>
          <div class="col-sm-9"><p class="form-control-static">${props.created_by.email}</p></div>
        </div>
        <div class="form-group">
          <label class="col-sm-3 control-label">Modified on</label>
          <div class="col-sm-9"><p class="form-control-static">${props.last_modified_on}</p></div>
        </div>
        <div class="form-group">
          <label class="col-sm-3 control-label">Modified by</label>
          <div class="col-sm-9"><p class="form-control-static">${props.last_modified_by.email}</p></div>
        </div>
      </div>
`;
  }
}


class CircuitHeader extends Component {
  constructor(state) {
    super();
  }

  async render(props) {
    let displayEdits = (props.editable) ? 'inline-block' : 'none';

    return `
      <div class="col-sm-8">
        <h2 style="display: inline-block;">
          <div style="display: inline-block;" id='header-description'>${props.description}</div>  
          <label for='connectionId' class='sr-only'>connection Id</label>
          <small id='connectionId'>${props.connectionId}</small>
        </h2>

        <button id="change-description-button" class="btn-sm btn-link change-description-button" type="button" hidden>
          <span class="glyphicon "></span> Change
        </button>
        <button id="edit-description-button" class="btn-sm btn-link edit-description-button" type="button">
          <span class="glyphicon "></span> Edit Name
        </button>
      </div>

      <div class="col-sm-4" style="text-align: right; padding-top: 23px; display: ${displayEdits};">
        <button class="btn-sm btn-success" type="button" onclick="state.saveCircuit();">
          <span class="glyphicon glyphicon-floppy-disk"></span> Save
        </button>
        <button class="btn-sm btn-danger" type="button" onclick="state.deleteCircuit();">
          <span class="glyphicon glyphicon-trash"></span> Delete
        </button>
      </div>
    `;
  }
}
