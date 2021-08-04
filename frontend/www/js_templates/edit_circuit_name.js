function doneEditingName(name){
    let description = document.querySelector('#header-description');
    let button = document.getElementById("edit-description-button")
    description.innerHTML = "<div id='header-description' style='display: inline;'>" + name +  "</div> "
    document.getElementById("change-description-button").hidden = true
    button.textContent = "Edit Name"
}
function addEditNameEvents(default_name){
    document.querySelector('.change-description-button').addEventListener('click', function(e) {
        const newName = document.getElementById("description-input").value == "" ?  default_name : document.getElementById("description-input").value
        doneEditingName(newName)
    })

    document.querySelector('.edit-description-button').addEventListener('click', function(e) {
        let name = document.querySelector('#header-description');
        let button = document.getElementById("edit-description-button")
        
        if(button.textContent.trim() == "Edit Name"){
            name.innerHTML = `
                <label for='description-input' class='sr-only'>new name input: </label> 
                <input class="form-control"  id='description-input' style='display: inline-block;' placeholder='`+ name.textContent +`'></input>
            `;
            name.addEventListener("keyup", function(event) {
            // Number 13 is the "Enter" key on the keyboard
            if (event.keyCode === 13) {
                event.preventDefault();
                const newName = document.getElementById("description-input").value == "" ?  default_name: document.getElementById("description-input").value
                doneEditingName(newName)
            }
            });
            button.textContent = "Revert" 
            document.getElementById("change-description-button").hidden = false
        }else{
            doneEditingName(default_name)
        }
    });
}