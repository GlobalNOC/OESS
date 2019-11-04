class Schedule {
  constructor(query) {
    let template = document.querySelector('#template-schedule-picker');
    this.element = document.importNode(template.content, true);

    let mkOptions = this.element.querySelectorAll('.create-picker-radio');
    for (let i = 0; i < mkOptions.length; i++) {
      mkOptions[i].addEventListener('change', this.setCreatePickerDisplay.bind(this));
    }

    let rmOptions = this.element.querySelectorAll('.remove-picker-radio');
    for (let i = 0; i < rmOptions.length; i++) {
      rmOptions[i].addEventListener('change', this.setRemovePickerDisplay.bind(this));
    }

    this.parent = document.querySelector(query);
    this.parent.appendChild(this.element);
  }

  /**
   * setCreatePickerDisplay displays the create picker if the 'Create
   * later' radio is selected. Otherwise the picker is hidden.
   */
  setCreatePickerDisplay(event) {
    if (this.parent.querySelector('.create-picker-now').checked) {
      this.parent.querySelector('.create-picker-datetime').style.display = 'none';
    } else {
      this.parent.querySelector('.create-picker-datetime').style.display = 'block';
    }
  }

  /**
   * setRemovePickerDisplay displays the remove picker if the 'Remove
   * later' radio is selected. Otherwise the picker is hidden.
   */
  setRemovePickerDisplay(event) {
    if (this.parent.querySelector('.remove-picker-never').checked) {
      this.parent.querySelector('.remove-picker-datetime').style.display = 'none';
    } else {
      this.parent.querySelector('.remove-picker-datetime').style.display = 'block';
    }
  }

  /**
   * createTime returns the unix time when create should be executed
   * or -1 if the 'Create now' radio is selected.
   */
  createTime() {
    let date = -1;
    if (!this.parent.querySelector('.create-picker-now').checked) {
      date = new Date(this.parent.querySelector('.create-picker-datetime').value).getTime() / 1000;
    }
    return date;
  }

  /**
   * removeTime returns the unix time when remove should be executed
   * or -1 if the 'Never remove' radio is selected.
   */
  removeTime() {
    let date = -1;
    if (!this.parent.querySelector('.remove-picker-never').checked) {
      date = new Date(this.parent.querySelector('.remove-picker-datetime').value).getTime() / 1000;
    }
    return date;
  }
}
