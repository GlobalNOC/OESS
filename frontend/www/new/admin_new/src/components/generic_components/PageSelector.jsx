import React from 'react';

class PageSelector extends React.Component {
  constructor(props) {
    super(props);

    // this.addUser = this.addUser.bind(this);
    // this.deleteWorkgroup = this.deleteWorkgroup.bind(this);
    // this.editWorkgroup = this.editWorkgroup.bind(this);
    // this.manageInterfaces = this.manageInterfaces.bind(this);
    // this.manageUsers = this.manageUsers.bind(this);
  }

  render() {
    // this.props.pageSize;
    // this.props.itemCount;
    // this.props.pageNumber;

    let pages = [];
    for (let i = 0; i < Math.ceil(this.props.itemCount / this.props.pageSize); i++) {
      let isActive = (this.props.pageNumber == i) ? 'active' : '';
      // position: static - Ensure page number appears under modals' backdrop
      pages.push( <li className={isActive} key={i}><a style={{position: 'static'}} href="#" onClick={() => this.props.onChange(i)}>{i+1}</a></li> );
    }

    return (
      <nav aria-label="Page navigation">
        <ul className="pagination">
          {pages}
        </ul>
      </nav>
    );
  }
}

export { PageSelector };
