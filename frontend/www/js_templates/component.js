document.components = {};
document.nextId = 0;

class Component {
  constructor() {
    this._id = ++document.nextId;
    document.components[this._id] = this;
  }
}
