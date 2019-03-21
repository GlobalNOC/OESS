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

  setCreatePickerDisplay(event) {
    if (this.parent.querySelector('.create-picker-now').checked) {
      this.parent.querySelector('.create-picker-datetime').style.display = 'none';
    } else {
      this.parent.querySelector('.create-picker-datetime').style.display = 'block';
    }
  }

  setRemovePickerDisplay(event) {
    if (this.parent.querySelector('.remove-picker-never').checked) {
      this.parent.querySelector('.remove-picker-datetime').style.display = 'none';
    } else {
      this.parent.querySelector('.remove-picker-datetime').style.display = 'block';
    }
  }

  createTime() {
    let date = -1;
    if (!this.parent.querySelector('.create-picker-now').checked) {
      date = new Date(this.parent.querySelector('.create-picker-datetime').value).getTime() / 1000;
    }
    return date;
  }

  removeTime() {
    let date = -1;
    if (!this.parent.querySelector('.remove-picker-never').checked) {
      date = new Date(this.parent.querySelector('.remove-picker-datetime').value).getTime() / 1000;
    }
    return date;
  }
}
