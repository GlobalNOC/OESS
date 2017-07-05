var get_multilink_panel = function(container_id, options){
    var options = options || {};
    if( options.already_used_check === undefined) options.already_used_check = true;
    if( options.fixedcenter === undefined) options.fixedcenter = true;
    $('body').append('<div id="'+container_id+'"></div>');
    $('#'+container_id).css('textAlign', 'left');

    var panel = new YAHOO.widget.Panel(container_id,{
        width: 360,
        modal: false,
        fixedcenter: options.already_used_check,
        zIndex: 1005,
        draggable: false,
        close: false
    });
   
    header = "Select Link";

    function is_already_used(link_name){
        var used_links = (session.data.links || []);
        used_links.concat( (session.data.backup_links || []) );
        for(var i=0; i < used_links.length; i++){
            if(used_links[i] == link_name) return true;
        }
        return false;
    }

    var link_options = "<option value=''>Select Link</option>";
    for( var i = 0; i < options.links.length; i++ ){
        var link = options.links[i];
        if( (options.already_used_check) && is_already_used(link.link_name)) continue;
        //if( (options.hide_down_links) && (link.state == "down") ) continue;
        //if(is_already_used(link.link_name)) {
        //    link_options += "class='disabled-result' "; 
        //}
        link_options += "<option value='"+link.link_name+"'>"+link.link_name+"</option>";
    }
    panel.setHeader(header);
    panel.setBody(
        "<label for='"+container_id+"_link_selector' id='"+container_id+"_link_selector_label' style='margin-right: 10px' class='soft_title'>Link:</label>" +
        "<select data-placeholder='Select Link' style='width:250px;' class='chzn-select' id='"+container_id+"_link_selector'>" +link_options+"</select>"
    );
    panel.setFooter("<div id='"+container_id+"_select'></div></div><div id='"+container_id+"_cancel'></div>");
    if(options.render_location) {
        panel.render(options.render_location);
    }else {
        panel.render();
    }

    $('.chzn-select').chosen({search_contains: true});

    //set up save button
    var select_button = new YAHOO.widget.Button(container_id+'_select');
    select_button.set('label','Select');
    select_button.on('click',function(){
        var link = $('#'+this.container_id+'_link_selector').val();
        if(link == "") link = null;
        options.on_change({ link: link });
        panel.destroy();
    }, false, { container_id: container_id });

    //set up cancel button
    var cancel_panel_button = new YAHOO.widget.Button(container_id+'_cancel');
    cancel_panel_button.set('label','Cancel');
    cancel_panel_button.on('click',function(){
        panel.destroy();
    });

    return panel;

};
