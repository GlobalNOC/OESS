import React from 'react';

class WorkgroupModal extends React.Component {
  constructor(props) {
    super(props);
  }

  submit(workgroup) {
    console.log('submit', workgroup);
  }

  cancel(workgroup) {
    console.log('cancel', workgroup);
  }

  render() {
    return (
      <form>
        <div className="form-group">
          <label>Name</label>
          <input className="form-control" type="text" name="name" value={this.props.name} />
        </div>
        <div className="form-group">
          <label>External ID</label>
          <input className="form-control" type="text" name="external_id" value={this.props.external_id} />
        </div>

        <input type="hidden" name="workgroup_id" value={this.props.workgroup_id} />

        <button type="button" className="btn btn-primary" style={{margin: '0 2px'}}>Submit</button>
        <button type="button" className="btn btn-default" style={{margin: '0 2px'}} data-dismiss="modal">Cancel</button>
      </form>
    );
  }
}

export { WorkgroupModal };
