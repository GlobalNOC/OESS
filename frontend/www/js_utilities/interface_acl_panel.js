var get_interface_acl_panel = function(container_id, interface_id, options){
    var options = options || {};
    var is_edit = options.is_edit || false;
    var fixedcenter = options.fixedcenter || false;
    var modal = options.modal || false;
    
    $('body').append('<div id="'+container_id+'"></div>');
    $('#'+container_id).css('textAlign', 'left');

    function _validate_data(data){
        var error_message = '<div style="text-align: left;">';
        var error = 0;
        // validate permission
        var permission = data.permission;
        if( (permission == undefined) || (permission == "") ) {
            error_message += ' - Permission must be defined<br>';
            error = 1;
        } 

        // validate vlan start and vlan end
        var vlan_start = data.vlan_start;
        var vlan_end   = data.vlan_end;
        //if( !isNaN(vlan_start) ){
        if( vlan_start.match(/^-?\d+$/) == null ){
            error_message += ' - The start of the vlan range must be a number<br>';
            error = 1;
        }
        //if( !(vlan_end === undefined || vlan_end == "") && !isNaN(vlan_end) ){
        if( !(vlan_end === undefined || vlan_end == "") && (vlan_end.match(/^-?\d+$/) == null) ){
            error_message += ' - The end of the vlan range must be a number or undefined<br>';
            error = 1;
        }
        if( ((vlan_end.match(/^-?\d+$/) != null) && (vlan_start.match(/^-?\d+$/) != null)) && 
            (parseInt(vlan_start) > parseInt(vlan_end)) ){
            error_message += ' - The start of the vlan range must be smaller the the end of the range<br>';
            error = 1;
        } 

        error_message += '</div>';
        if( error ) {
            alert(error_message);
            return 1;
        }

        return 0;
    }

    var panel = new YAHOO.widget.Panel(container_id,{
        width: 360,
        modal: modal,
        fixedcenter: fixedcenter,
        zIndex: 10,
        draggable: false,
        close: false
    });
   
    if(is_edit){
        header = "Edit Interface ACL";
    }else {
        header = "Add Interface ACL";
    }

    panel.setHeader(header);
    panel.setBody(
        "<label for='"+container_id+"_acl_panel_workgroup' id='"+container_id+"_acl_panel_workgroup_label' style='margin-right: 12px' class='soft_title'>Workgroup:</label>" +
        "<select data-placeholder='Loading Workgroups...' style='width:250px;' class='chzn-select' id='"+container_id+"_acl_panel_workgroup'></select>" +
        "<br><br><label for='"+container_id+"_acl_panel_entity' id='"+container_id+"_acl_panel_entity_label' style='margin-right: 12px' class='soft_title'>Entity:</label>" +
        "<select data-placeholder='Loading Entitys...' style='width:250px;' class='chzn-select' id='"+container_id+"_acl_panel_entity'></select>" +
        "<br><br><label for='"+container_id+"_acl_panel_permission' id='"+container_id+"_acl_panel_permission_label' style='margin-right: 10px' class='soft_title'>Permission:</label>" +
        "<select data-placeholder='Select Permission' style='width:250px;' class='chzn-select' id='"+container_id+"_acl_panel_permission'>" +
        "<option value></option>" +
        "<option value='allow'>Allow</option>" +
        "<option value='deny'>Deny</option>" +
        "</select>" +
        "<br><br><label for='"+container_id+"_acl_panel_vlan_start' class='soft_title'>VLAN Range:</label>" +
        "<input id='"+container_id+"_acl_panel_vlan_start' type='text' size='10' style='margin-left: 5px;margin-right: 5px;'>" + "-" +
        "<input id='"+container_id+"_acl_panel_vlan_end' type='text' size='10' style='margin-left: 5px'>" +
        "<br><br><label for='"+container_id+"_acl_panel_notes' class='soft_title'>Notes:</label>" +
        "<textarea id='"+container_id+"_acl_panel_notes' rows='4' cols='35' style='margin-left: 12px'>"
	  );
    panel.setFooter("<div id='"+container_id+"_save_acl_panel'></div><div id='"+container_id+"_remove_acl_panel'></div><div id='"+container_id+"_cancel_acl_panel'></div>");
    if(options.render_location) {
        panel.render(options.render_location);
    }else {
        panel.render();
    }

    //set the values of all the inputs
    if(is_edit){
        var rec = options.record;
        $('#'+container_id+'_acl_panel_permission').val( rec.getData("allow_deny") )
        $('#'+container_id+'_acl_panel_vlan_start').val( rec.getData("start") );
        $('#'+container_id+'_acl_panel_vlan_end').val( rec.getData("end") );
        $('#'+container_id+'_acl_panel_entity').val( rec.getData("entity_id") );
        $('#'+container_id+'_acl_panel_notes').val( rec.getData("notes") );
    }
   
    $('.chzn-select').chosen({search_contains: true});
    //disable the workgroup selector until the workgroups are fetched
    $("#"+container_id+"_acl_panel_workgroup").attr('disabled', true).trigger("liszt:updated");
    $("#"+container_id+"_acl_panel_entity").attr('disabled', true).trigger("liszt:updated");

    //set up save button
    var save_acl_button = new YAHOO.widget.Button(container_id+'_save_acl_panel');
    save_acl_button.set('label','Save');
    //disable the button until the workgroups have come back when editing
    if(is_edit){
        save_acl_button.set('disabled', true);
    }

    save_acl_button.on('click',function(){
        var workgroup_id = $("#"+container_id+"_acl_panel_workgroup").chosen().val();
        var entity_id    = $("#"+container_id+"_acl_panel_entity").chosen().val();
        var allow_deny   = $("#"+container_id+"_acl_panel_permission").chosen().val();
        var vlan_start   = $("#"+container_id+"_acl_panel_vlan_start").val();
        var vlan_end     = $("#"+container_id+"_acl_panel_vlan_end").val();
        var notes        = encodeURIComponent($("#"+container_id+"_acl_panel_notes").val());
        //validate data then hide our panel        
        if(_validate_data({ 
            permission: allow_deny, 
            vlan_start: vlan_start, 
            vlan_end: vlan_end
			})){
            //data's bad 
            return 1;
        }
        panel.hide();

        var url = "services/workgroup_manage.cgi?method=";
        if(options.url_prefix){
            url = options.url_prefix + url;
        }
        //var record_id = owned_interface_table.getSelectedRows()[0];
        //var interface_id = owned_interface_table.getRecord(record_id).getData("interface_id");
        //determine which action and special params to send
        if(is_edit){
            var rec = options.record;
            url += "update_acl";
            url += "&interface_acl_id="+rec.getData("interface_acl_id");
            url += "&eval_position="+rec.getData("eval_position");
        }else {
            url += "add_acl";
        }
        //required
        url += "&allow_deny="+allow_deny;
        url += "&vlan_start="+vlan_start;
        url += "&interface_id="+interface_id;

        //optional
        if(workgroup_id) {url += "&workgroup_id="+workgroup_id;}
        if(entity_id)    {url += "&entity_id="+entity_id;}
        if(notes)        {url += "&notes="+notes;}
        if(vlan_end)     {url += "&vlan_end="+vlan_end;}

        var ds = new YAHOO.util.DataSource(url);
        ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
        ds.responseSchema = {
            resultsList: "results",
            fields: [
                "success",
                "error"
            ],
            metaFields: {
                error: "error"
            }
        };

        ds.sendRequest("",{
            success: function(req, resp){
                if(!resp.results.length || !resp.results[0].success){
                    alert("Error saving acl data: "+resp.meta.error);
                }else {
                    options.on_add_edit_success({ interface_id: interface_id });
                }
            },
            failure: function(req, resp){
                throw "Error saving acl data";
            },
            scope: this
		    },ds);
        });    
    //set up cancel button
    var cancel_acl_panel_button = new YAHOO.widget.Button(container_id+'_cancel_acl_panel');
    cancel_acl_panel_button.set('label','Cancel');
    cancel_acl_panel_button.on('click',function(){
        panel.hide();
    });

    //setup remove button if it is an edit
    if(is_edit){
        var remove_acl_button = new YAHOO.widget.Button(container_id+'_remove_acl_panel');
        remove_acl_button.set('label','Remove');
        remove_acl_button.on('click',function(){
            showConfirm("You are about to remove an acl. This CANNOT be undone. Are you sure you want to proceed?",
                function(){
                    var url = "services/workgroup_manage.cgi?method=remove_acl";
                    if(options.url_prefix){
                        url = options.url_prefix + url;
                    }
                    url += "&interface_acl_id="+rec.getData("interface_acl_id");

                    var ds = new YAHOO.util.DataSource(url);
                    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                    ds.responseSchema = {
                        resultsList: "results",
                        fields: ["success"]
                    };

                    ds.sendRequest("",{
                        success: function(req, resp){
                        if(resp.results.length <= 0){
                            alert("Error removing acl data");
                        }else {
                            panel.hide();
                            options.on_remove_success();
                        }
                    },
                    failure: function(req, resp){
                        alert("Error removing acl data");
                    },
                        scope: this
                    },ds);
                
                },
                function(){
                            return;
                }
            );    
        });
    }else {
        $('#'+container_id+'_remove_acl_panel').css('display', 'none');
    }

    //fetch workgroups
    var url = `services/entity.cgi?method=get_entities&workgroup_id=${session.data.workgroup_id}`;
    if(options.url_prefix){
        url = options.url_prefix + url;
    }

    var entity_ds = new YAHOO.util.DataSource(url);
    entity_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    entity_ds.responseSchema = {
        resultsList: "results",
        fields: [
            {key: "entity_id", parser:"number"},
            {key: "name"}
        ],
        metaFields: {
            error: "error",
            error_text: "error_text"
        }
    };
    entity_ds.sendRequest("",{
        success: function(req, resp){
            $('#'+container_id+'_acl_panel_entity').append("<option value>All</option>");
            for( var i = 0; i < resp.results.length; i++ ){
                var entity_id = resp.results[i].entity_id;
                var name = resp.results[i].name;
                var option = "<option value='"+entity_id+"'>"+name+"</option>";
                $('#'+container_id+'_acl_panel_entity').append(option);
            }
            //select proper value and enabled save button if its an edit
            if(is_edit){
                save_acl_button.set('disabled', false);
                $('#'+container_id+'_acl_panel_entity').val( rec.getData("entity_id") )
            }
            //enable and update
            $("#"+container_id+"_acl_panel_entity").attr('data-placeholder', 'Select Entity');
            $("#"+container_id+"_acl_panel_entity").attr('disabled', false).trigger("liszt:updated");
        },
        failure: function(req, resp){
            throw("Error: fetching selections");
        },
        scope: this
    });

    url = "services/workgroup_manage.cgi?method=get_all_workgroups";
    if(options.url_prefix){
        url = options.url_prefix + url;
    }

    var workgroup_ds = new YAHOO.util.DataSource(url);
    workgroup_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    workgroup_ds.responseSchema = {
        resultsList: "results",
        fields: [
            {key: "workgroup_id", parser:"number"},
            {key: "name" }
        ],
        metaFields: {
            error: "error"
        }
    };
    workgroup_ds.sendRequest("",{
        success: function(req, resp){
            $('#'+container_id+'_acl_panel_workgroup').append("<option value>All</option>");
            for( var i = 0; i < resp.results.length; i++ ){
                var id   = resp.results[i].workgroup_id;
                var name = resp.results[i].name;
                var option = "<option value='"+id+"'>"+name+"</option>";
                $('#'+container_id+'_acl_panel_workgroup').append(option);
            }
            //select proper value and enabled save button if its an edit
            if(is_edit){
                save_acl_button.set('disabled', false);
                $('#'+container_id+'_acl_panel_workgroup').val( rec.getData("workgroup_id") )
            }
            //enable and update
            $("#"+container_id+"_acl_panel_workgroup").attr('data-placeholder', 'Select Workgroup');
            $("#"+container_id+"_acl_panel_workgroup").attr('disabled', false).trigger("liszt:updated");
        },
        failure: function(req, resp){
            throw("Error: fetching selections");
        },
        scope: this
    });

    return panel;

};
