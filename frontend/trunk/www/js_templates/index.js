<script type='text/javascript' src='js_utilities/datatable_utils.js'></script>
<script>
  
  
  function index_init(){
    session.clear();
    // set up the new circuit link
    var new_circuit = new YAHOO.util.Element('create_new_vlan');
    new_circuit.on('click', function(){
	    session.clear();
	    window.location = "index.cgi?action=edit_details";
	});
    
    var add_user = new YAHOO.util.Element('request_user_add');
    add_user.on('click', function(){
	    
	    var panel = new YAHOO.widget.Panel("request_user_add_p",
					       {width: 360,
						modal: true,
                                                fixedcenter: true,
                                                zIndex: 10,
                                                draggable: false
					       });

            panel.setHeader("Request a User to be added to this Workgroup");
            panel.setBody("<label for='username' class='soft_title'>Username:</label>" +
                          "<input id='username' type='text' size='20' style='margin-left: 30px'>" +
                          "<br><label for='given_name' class='soft_title'>Given Name:</label>" +
                          "<input id='given_name' type='text' size='20' style='margin-left: 18px'>" + 
			  "<br><label for='family_name' class='soft_title'>Family Name:</label>" + 
			  "<input id='family_name' type='text' size='20' style='margin-left: 12px'>" + 
			  "<br><label for='email_address' class='soft_title'>Email Address:</label>" +
			  "<input id='email_address' type='text' size='20'>"
                          );
            panel.setFooter("<div id='send_user_add'></div><div id='cancel_user_add'></div>");

            panel.render();

	    var send_user_add_button = new YAHOO.widget.Button('send_user_add');
            send_user_add_button.set('label','Send Request');
            send_user_add_button.on('click',function(){
                    panel.hide();
		    //                    panel.destroy();
		    var username = document.getElementById('username').value;
		    var given_name = document.getElementById('given_name').value;
		    var family_name = document.getElementById('family_name').value;
		    var email_address = document.getElementById('email_address').value;
		    
		    var subject = "Please Add User to workgroup " + session.data.workgroup_name  + " (ID=" + session.data.workgroup_id + ")";
		    var body = "Details: <br><table><tr><td>Username:</td><td>" + username + "</td></tr><tr><td>Given Name:</td><td>" + given_name + "</td></tr><tr><td>Family Name:</td><td>" + family_name + "</td></tr><tr><td>Email Address:</td><td>" + email_address + "</td></tr></table>";
		    subject = encodeURI(subject);
		    body = encodeURI(body);
		    var ds = new YAHOO.util.DataSource("services/data.cgi?action=send_email&subject=" + subject + "&body=" + body );
		    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
		    ds.responseSchema = {
			resultsList: "results",
			fields: ["success","error"]
		    };

		    ds.sendRequest("",{success: function(Req,Res){
				
			    },
				failure: function(Req,Res){

			    },
				argument: ds},ds);
                });

            var cancel_user_add_button = new YAHOO.widget.Button('cancel_user_add');
	    cancel_user_add_button.set('label','Cancel');
            cancel_user_add_button.on('click',function(){
                    panel.hide();
                    panel.destroy();
                });

	});

    var send_feedback = new YAHOO.util.Element('send_feedback');
    send_feedback.on('click', function(){
	    
	    var panel = new YAHOO.widget.Panel("send_feedback_p",
					       {width: 660,
						modal: true,
						fixedcenter: true,
						zIndex: 10,
						draggable: false
					       });

            panel.setHeader("Send Feedback To Administrators");
            panel.setBody("<label for='subject' class='soft_title'>Subject:</label>" +
                          "<input id='subject' type='text' size='75' style='margin-left: 15px'>" +
                          "<br><label for='feedback' class='soft_title' style='vertical-align: top'>Feedback:</label>" +
                          "<textarea id='feedback' rows='20' cols='80'></textarea>"
                          );
            panel.setFooter("<div id='do_send_feedback'></div><div id='cancel_feedback'></div>");

            panel.render();

	    var send_feedback_button = new YAHOO.widget.Button('do_send_feedback');
	    send_feedback_button.set('label','Send');
	    send_feedback_button.on('click',function(){
		    panel.hide();
		    panel.destroy();
		});

	    var cancel_feedback_button = new YAHOO.widget.Button('cancel_feedback');
	    cancel_feedback_button.set('label','Cancel');
	    cancel_feedback_button.on('click',function(){
		    panel.hide();
		    panel.destroy();
		});
	});

    
    
    // set up the search bar
    var tabs = new YAHOO.widget.TabView("workgroup_tabs");
    var searchTimeout;
    
    var search = new YAHOO.util.Element(YAHOO.util.Dom.get('circuit_search'));
    
    search.on('keyup', function(e){
		
	    var search_value = this.get('element').value;
		
	    if (e.keyCode == YAHOO.util.KeyListener.KEY.ENTER){
		clearTimeout(searchTimeout);
			table_filter.call(ckt_table,search_value);
	    }
	    else{
		if (searchTimeout) clearTimeout(searchTimeout);
		
		searchTimeout = setTimeout(function(){
			table_filter.call(ckt_table,search_value);
		    }, 400);
		
	    } 
	    
	}
	);
	  $('.chzn-select').chosen({search_contains: true});
    
    var node_ds = new YAHOO.util.DataSource("services/data.cgi?action=get_nodes");
	  node_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
	  node_ds.responseSchema = {

		  resultsList: "results",
		  fields: [
			  {key: "node_id", parser:"number"},
			  {key: "name" }
		  ],
		  metaFields: {
			  error: "error"
		  }

	  };
	  //get nodes for both option selectors

	  node_ds.sendRequest("",
					 {
					     success: function(req, resp){
						     var optionsfragment = document.createDocumentFragment();
							 for (var i = 0; i < resp.results.length; i++){
								 var option= document.createElement('option');
								 option.setAttribute("value", resp.results[i].node_id);
								 option.innerHTML= resp.results[i].name;
								 optionsfragment.appendChild(option);
							 }
							 
							 var endpoint= YAHOO.util.Dom.get("endpoint_node_selector");
							 var path= YAHOO.util.Dom.get("path_node_selector");
							 endpoint.appendChild(optionsfragment.cloneNode(true) );
							 path.appendChild(optionsfragment.cloneNode(true) );
							 $("#endpoint_node_selector").trigger("liszt:updated");
							 $("#path_node_selector").trigger("liszt:updated");
                             
                             //set up subscriptions for events;
						     
                             var endpoint_el = new YAHOO.util.Element(endpoint);
                             var path_el = new YAHOO.util.Element(path);
                             
                             
                             $("#endpoint_node_selector,#path_node_selector").chosen().change( function(){ 
                                 
                                 ckt_table = build_circuitTable.apply(ckt_table,[]); } );
                             
                         
                         },
						 failure: function(req, resp){
							 throw("Error: fetching selections");
						 },
						 scope: this
					 },
					 node_ds);
  
 


function build_circuitTable(){

    if ( typeof(this.destroy) == "function" ){
        this.destroy();
    };
    

    var dsString="services/data.cgi?action=get_existing_circuits&workgroup_id="+session.data.workgroup_id;
    
    var endpointSelector= YAHOO.util.Dom.get("endpoint_node_selector");
	var pathSelector= YAHOO.util.Dom.get("path_node_selector");

    for(x=0;x<endpointSelector.length; x++){
        if(endpointSelector[x].selected){
            dsString +="&endpoint_node_id="+endpointSelector[x].value;
        }
    }
    for(x=0;x<pathSelector.length; x++){
        if(pathSelector[x].selected){
            dsString +="&path_node_id="+pathSelector[x].value;
        }
    }
    console.log(dsString);


var ds = new YAHOO.util.DataSource(dsString);
      ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
      ds.responseSchema = {
		  resultsList: "results",
		  fields: [
			  {key: "circuit_id", parser: "number"},
			  {key: "description"},
			  {key: "bandwidth", parser: "number"},
			  {key: "name"},
			  {key: "endpoints"},
			  {key: "state"}
		  ],
		  metaFields: {
			  error: "error"
		  }
	  };
	 
	     
    var columns = [
		   
		   {key: "description", label: "Description", width: 450},
		   {key: "endpoints", label: "Endpoints", width: 300, formatter: function(el, rec, col, data){

			   var endpoints  = rec.getData('endpoints');
			   
			   var string = "";
			   
			   if (endpoints.length <= 2){
			       
			       for (var i = 0; i < endpoints.length; i++){
				   
				   if (i > 0){
				       string += "<br>";
				   }
				   
				   string += endpoints[i].node + " - " + endpoints[i].interface;
			       }
			       
			   }
			   else{
			       
			       string += endpoints[0].node + " - " + endpoints[0].interface;
			       string += "<br>and " + (endpoints.length - 1) + " more";
			       
			   }
			   
			   el.innerHTML = string;
		       }
		   },
		   {key: "state", label: "Status", width: 70, formatter: function(el, rec, col, data){
			   el.innerHTML = "<center>"+data+"</center>";
		       }
		   }
		   ];
    
    var config = {
	      paginator: new YAHOO.widget.Paginator({rowsPerPage: 10,
					     containers: ["circuit_table_nav"]
					    })
    };
    
    var circuit_table = new YAHOO.widget.DataTable("circuit_table", columns, ds, config);

    circuit_table.on("initEvent", function(){
        var search = new YAHOO.util.Element(YAHOO.util.Dom.get('circuit_search'));
        var search_value = search.get('element').value;
	    table_filter.call(ckt_table,search_value);
    }

                    );

    circuit_table.subscribe("rowMouseoverEvent", circuit_table.onEventHighlightRow);
    circuit_table.subscribe("rowMouseoutEvent", circuit_table.onEventUnhighlightRow);
    circuit_table.subscribe("rowClickEvent", function(oArgs){

	    var record = circuit_table.getRecord(oArgs.target);

	    session.clear();

	    session.data.circuit_id  = record.getData('circuit_id');

	    session.save();

	    window.location = "?action=view_details";
	});


    // cache the response so we can do some client side filtering 
    // and show aggregate stats
    circuit_table.on("dataReturnEvent", function(oArgs){		       		     
	    this.cache = oArgs.response;

	    var results = oArgs.response.results;

	    var total_circuits  = 0;
	    var total_bandwidth = 0;

	    for (var i = 0; i < results.length; i++){
		    var data = results[i];
		    total_circuits++;
		    total_bandwidth += data.bandwidth;
	    }

	    if (total_bandwidth >= 1000){
		    total_bandwidth = (total_bandwidth / 1000) + " Gbps";
	    }
	    else{
		    total_bandwidth = total_bandwidth + " Mbps";
	    }
        
	    YAHOO.util.Dom.get("total_workgroup_bandwidth").innerHTML = total_bandwidth;
	    YAHOO.util.Dom.get("total_workgroup_circuits").innerHTML = total_circuits;
        
       

        return oArgs;
    }
                    );
    
    

    

    return circuit_table;
        


}

   
      var ckt_table = build_circuitTable();
      

    var link_status_ds = new YAHOO.util.DataSource("services/data.cgi?action=get_all_link_status");
    link_status_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    link_status_ds.responseSchema = {
	resultsList: "results",
	fields: ["name","link_id","status","operational_state"]
    };

    var link_status_columns = [
			       {key: "name", label: "Link", width: 200},
			       {key: "status", label: "Status", width: 40, formatter: function(elLiner, oRec, oCol, oData){
				       if(oRec.getData('status') == 'up'){
					   elLiner.innerHTML = "<font color='green'>up</font>";
				       }else{
					   elLiner.innerHTML = "<font color='red'>" + oRec.getData('status') + "</font>";
				       }
				   }}
			       ];
    var link_table = new YAHOO.widget.ScrollingDataTable("link_status_table",link_status_columns, link_status_ds,{height: '210px'});
    link_status_ds.setInterval(30000);

    //build the switch status table
    var switch_status_ds = new YAHOO.util.DataSource("services/data.cgi?action=get_all_node_status");
    switch_status_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    switch_status_ds.responseSchema = {
	resultsList: "results",
	fields: ["name","node_id","operational_state"]
    };

    var switch_status_columns = [
				 {key: "name", label: "Switch",sortable: true, width: 200},
				 {key: "operational_state", sortable: true, label: "Status", width: 40, formatter: function(elLiner, oRec, oCol, oData){
					 if(oRec.getData('operational_state') == 'up'){
					     elLiner.innerHTML = "<font color='green'>up</font>";
					 }else{
					     elLiner.innerHTML = "<font color='red'>" + oRec.getData('operational_state') + "</font>";
					 }
				     }}
				 ];

    var switch_table = new YAHOO.widget.ScrollingDataTable("switch_status_table",switch_status_columns, switch_status_ds,{height: '210px'});
    switch_status_ds.setInterval(30000);
      var circuit_status_ds = new YAHOO.util.DataSource("services/data.cgi?action=get_existing_circuits&workgroup_id="+session.data.workgroup_id);
    circuit_status_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    circuit_status_ds.responseSchema = {
	resultsList: "results",
	fields: ["description","name","operational_state","active_path"]
    };

    var circuit_status_cols = [
			       {key: "description", label: "name",sortable:true, width: 200},
			       {key: "status", label: "Status",sortable:true, width: 100,sortable: true, formatter: function(elLiner, oRec, oColumn, oData){
				       if(oRec.getData('operational_state') == 'down'){
					   elLiner.innerHTML = "<font color='red'>down</font>";
				       }else{
					   if(oRec.getData('active_path') == 'primary'){
					       elLiner.innerHTML = "<font color='green'>primary</font>";
					   }else{
					       elLiner.innerHTML = "<font color='orange'>backup</font>";
					   }
				       }
				   }}
			       ];

    var circuit_status_table = new YAHOO.widget.ScrollingDataTable("circuit_status_table",circuit_status_cols, circuit_status_ds,{height: '480px'});
    circuit_status_ds.setInterval(30000);
    var nddi_map = new NDDIMap("network_status_map", session.data.interdomain == 0);

    //nddi_map.showDefault();

    nddi_map.on("loaded", function(){
	    this.updateMapFromSession(session);
	});

    setInterval(function(){
	    nddi_map.reinitialize();
	}, 30000);

    // build the users table
    var user_ds = new YAHOO.util.DataSource("services/data.cgi?action=get_workgroup_members&workgroup_id="+session.data.workgroup_id);
    user_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    user_ds.responseSchema = {
	resultsList: "results",
	fields: [
    {key: "auth_name"},
    {key: "first_name"},
    {key: "family_name"},
    {key: "email_address"}
		 ],
	metaFields: {
	    error: "error"
	}
    };

    var user_columns = [

                   {key: "auth_name", label: "Username(s)", width: 150},
                   {key: "first_name", label: "Given Name", width: 150},
                   {key: "family_name", label: "Last Name", width: 150},
		   {key: "email_address", label: "Email Address", width: 150}
                   ];

    var user_config = {
	paginator: new YAHOO.widget.Paginator({rowsPerPage: 10,
					       containers: ["user_table_nav"]
	    })
    };

    var user_table = new YAHOO.widget.DataTable("user_table", user_columns, user_ds, user_config);

    var resource_map = new NDDIMap("available_resource_map", session.data.interdomain == 0);

    //resource_map.showDefault();

    resource_map.on("loaded", function(){
            this.updateMapFromSession(session);
        });    

    tabs.on('activeTabChange', function(){
	    resource_map.render("available_resource_map");
	    nddi_map.render("network_status_map");
	});

    var avail_resource_ds = new YAHOO.util.DataSource("services/data.cgi?action=get_all_resources_for_workgroup&workgroup_id=" + session.data.workgroup_id);
    avail_resource_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    avail_resource_ds.responseSchema = {
	resultsList: "results",
	fields: ["node_name","interface_name","operational_state","description","vlan_tag_range"]
    };
    
    var avail_resource_cols = [
			       {key: "node_name",sortable: true, label: "Node"},
			       {key: "interface_name", sortable: true, label: "Interface"},
			       {key: "description", sortable: true,  label: "Description"},
			       {key: "operational_state", sortable:true, label: "Status", formatter: function(elLiner, oRec, oCol, oData){
				       if(oRec.getData('operational_state') == 'up'){
					   elLiner.innerHTML = "<font color='green'>up</font>";
				       }else{
					   elLiner.innerHTML = "<font color='red'>" + oRec.getData('operational_state') + "</font>";
				       }
				   }},
			       {key: "vlan_tag_range", sortable: true,  label: "VLAN Range", formatter: function(elLiner, oRec, oCol, oData){ 
                        var string = oData.replace("-1", "untagged");
			            elLiner.innerHTML = string;
                   }}
			       ];

    var avail_resource_table = new YAHOO.widget.ScrollingDataTable("available_resource_table",avail_resource_cols, avail_resource_ds, {height: '473px', width: '475px'});

    // setup help stuff
    makeHelpPanel(["circuit_search", "circuit_search_label"], "Use this to filter the circuits table below. The table will filter as you type.");


    //---
    //--- Set up Acl stuff
    //---
    function build_interface_acl_table(interface_id, options){
        if(interface_acl_table) {
            interface_acl_table.destroy();
        }
        var options = options || {};
        //if ( typeof(this.destroy) == "function" ){
        //    this.destroy();
        //};

        var dsString="services/workgroup_manage.cgi?action=get_acls&interface_id="+interface_id;

        var ds = new YAHOO.util.DataSource(dsString);
        ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
        ds.responseSchema = {
        resultsList: "results",
        fields: [
            {key: "interface_acl_id", parser: "number"},
            {key: "workgroup_id", parser: "number"},
            {key: "workgroup_name"},
            {key: "interface_id", parser: "number"},
            {key: "allow_deny"},
            {key: "eval_position"},
            {key: "vlan_start"},
            {key: "vlan_end"},
            {key: "notes"}
        ]};

        var columns = [
            {key: "workgroup_name", label: "Workgroup", width: 180 ,sortable:false, formatter: function(el, rec, col, data){
                if(data === null) {
			        el.innerHTML = "All";
                } else {
			        el.innerHTML = data;
                }
            }},
            {key: "allow_deny", label: "Permission",sortable:false},
            {label: "VLAN Range", formatter: function(el, rec, col, data){
                var vlan_start  = rec.getData('vlan_start');
                var vlan_end    = rec.getData('vlan_end');
                if(vlan_start == -1){
                    vlan_start = 'untagged';
                }
                var string = vlan_start;
                if(vlan_end !== null){
                    if(vlan_start == "untagged") {
                        string += ", 1";
                    }
                    string += "-"+vlan_end;
                }
			    el.innerHTML = string;
            }},
            {key: "notes", label: "Notes",sortable:false}
        ];

        //var config = {
        //    sortedBy: {key:'eval_position', dir:'asc'}
        //};
        var config = {};

        $("#interface_acl_container").css('display', 'block');

        var interface_acl_table = new YAHOO.widget.DataTable("interface_acl_table", columns, ds, config);



        //make drag drop
        _makeTableDragDrop(interface_acl_table, {
            url: "services/workgroup_manage.cgi?action=update_acl",
            position_param: "eval_position",
            ws_params: [
                "interface_acl_id",
                "allow_deny",
                "vlan_start",
                "vlan_end",
                "interface_id",
                "workgroup_id",
                "notes" 
            ],
            fields: ["success"],
            onSuccess: function(req, resp, index){
                if(resp.results.length <= 0){
                    alert("Save Unsuccessful");
                }
                var record_id = owned_interface_table.getSelectedRows()[0];
                var interface_id = owned_interface_table.getRecord(record_id).getData("interface_id");
                build_interface_acl_table(interface_id, {
                    enableDragDrop: interface_acl_table._dragDrop
                });
            },
            onFailure: function(req, resp, index) {
                alert("Save Unsuccessful");
                var record_id = owned_interface_table.getSelectedRows()[0];
                var interface_id = owned_interface_table.getRecord(record_id).getData("interface_id");
                build_interface_acl_table(interface_id, {
                    enableDragDrop: interface_acl_table._dragDrop
                });
            }
        });

        if(options.enableDragDrop){
            interface_acl_table.enableDragDrop();
        }
       
        //add editing functionality  
        interface_acl_table.subscribe("rowClickEvent", function(oArgs){
            if(this._dragDrop){
                return;
            }
            var record = this.getRecord(oArgs.target);
            show_interface_acl_panel({ is_edit: true, record: record });
        });
        interface_acl_table.subscribe("rowMouseoverEvent", interface_acl_table.onEventHighlightRow);
        interface_acl_table.subscribe("rowMouseoutEvent", interface_acl_table.onEventUnhighlightRow);

        //return owned_interface_table;
        return interface_acl_table;
    }

    function build_owned_interface_table(){
        if ( typeof(this.destroy) == "function" ){
            this.destroy();
        };

        var dsString="services/data.cgi?action=get_workgroup_interfaces&workgroup_id="+session.data.workgroup_id;

        var ds = new YAHOO.util.DataSource(dsString);
        ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
        ds.responseSchema = {
        resultsList: "results",
        fields: [
            {key: "node_id", parser: "number"},
            {key: "interface_id", parser: "number"},
            {key: "node_name"},
            {key: "interface_name"}
        ]};
    
        var columns = [
            {key: "node_name", label: "Node", width: 180 ,sortable:true},
            {key: "interface_name", label: "Interface", width: 60 ,sortable:true}
        ];
    
        var config = {
            sortedBy: {key:'node_name', dir:'asc'},
            paginator:  new YAHOO.widget.Paginator({
                rowsPerPage: 10,
                containers: ["owned_interfaces_table_nav"]
            }),
            selectionMode:"single"
        };
    
        var owned_interface_table = new YAHOO.widget.DataTable("owned_interface_table", columns, ds, config);

        owned_interface_table.subscribe("rowClickEvent", function(oArgs){
            owned_interface_table.onEventSelectRow(oArgs);
            var record = owned_interface_table.getRecord(oArgs.target);
            var interface_id = record.getData('interface_id'); 

            //session.clear();
            //session.data.circuit_id  = record.getData('circuit_id');
            //session.save();
            var interface_acl_table = build_interface_acl_table(interface_id);
        });
        owned_interface_table.subscribe("rowMouseoverEvent", owned_interface_table.onEventHighlightRow);
        owned_interface_table.subscribe("rowMouseoutEvent", owned_interface_table.onEventUnhighlightRow);
    
        return owned_interface_table;
    }

    var show_interface_acl_panel = function(options){
        var options = options || {};
        var is_edit = options.is_edit || false;

        var panel = new YAHOO.widget.Panel("interface_acl_panel",{
            width: 360,
            modal: true,
            fixedcenter: true,
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
            "<label for='acl_panel_workgroup' id='acl_panel_workgroup_label' style='margin-right: 12px' class='soft_title'>Workgroup:</label>" +
            "<select data-placeholder='Loading Workgroups...' style='width:250px;' class='chzn-select' id='acl_panel_workgroup'></select>" +
            "<br><br><label for='acl_panel_permission' id='acl_panel_permission_label' style='margin-right: 10px' class='soft_title'>Permission:</label>" +
            "<select data-placeholder='Select Permission' style='width:250px;' class='chzn-select' id='acl_panel_permission'>" + 
            "<option value></option>" +
            "<option value='allow'>Allow</option>" + 
            "<option value='deny'>Deny</option>" + 
            "</select>" +
            "<br><br><label for='acl_panel_vlan_start' class='soft_title'>VLAN Range:</label>" +
            "<input id='acl_panel_vlan_start' type='text' size='10' style='margin-left: 5px'>" +
            "<input id='acl_panel_vlan_end' type='text' size='10' style='margin-left: 5px'>" +
            "<br><br><label for='acl_panel_notes' class='soft_title'>Notes:</label>" +
            "<textarea id='acl_panel_notes' rows='4' cols='35' style='margin-left: 12px'>"
        );
        panel.setFooter("<div id='save_acl_panel'></div><div id='remove_acl_panel'></div><div id='cancel_acl_panel'></div>");
        panel.render();

        //set the values of all the inputs
        if(is_edit){
            var rec = options.record;
            $('#acl_panel_permission').val( rec.getData("allow_deny") )
            $('#acl_panel_vlan_start').val( rec.getData("vlan_start") );
            $('#acl_panel_vlan_end').val( rec.getData("vlan_end") );
            $('#acl_panel_notes').val( rec.getData("notes") );
        }

	    $('.chzn-select').chosen({search_contains: true});
        //disable the workgroup selector until the workgroups are fetched
        $("#acl_panel_workgroup").attr('disabled', true).trigger("liszt:updated");
       
        //set up save button 
        var save_acl_button = new YAHOO.widget.Button('save_acl_panel');
        save_acl_button.set('label','Save');
        //disable the button until the workgroups have come back when editing
        if(is_edit){
            save_acl_button.set('disabled', true);
        }
        save_acl_button.on('click',function(){
            panel.hide();

            //get values 
            var workgroup_id = $("#acl_panel_workgroup").chosen().val()
            var allow_deny   = $("#acl_panel_permission").chosen().val()
            var vlan_start   = $("#acl_panel_vlan_start").val();
            var vlan_end     = $("#acl_panel_vlan_end").val();
            var notes        = $("#acl_panel_notes").val();

            var url = "services/workgroup_manage.cgi?action=";
            var record_id = owned_interface_table.getSelectedRows()[0];
            var interface_id = owned_interface_table.getRecord(record_id).getData("interface_id");
            //determine which action and special params to send
            if(is_edit){
                var rec = options.record;
                url += "update_acl";
                url += "&interface_acl_id="+rec.getData("interface_acl_id");
                url += "&eval_position="+rec.getData("eval_position");
                //TODO add interface_acl_id
            }else {
                url += "add_acl";
            }

            //required
            url += "&allow_deny="+allow_deny;
            url += "&vlan_start="+vlan_start;
            url += "&interface_id="+interface_id;
           
            //optional 
            if(workgroup_id) {url += "&workgroup_id="+workgroup_id;}
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
                        build_interface_acl_table(interface_id);
                    }
                },
                failure: function(req, resp){
                    throw "Error saving acl data";
                },
                scope: this
            },ds);
        });

        //set up cancel button
        var cancel_acl_panel_button = new YAHOO.widget.Button('cancel_acl_panel');
        cancel_acl_panel_button.set('label','Cancel');
        cancel_acl_panel_button.on('click',function(){
            panel.hide();
        }); 

        //setup remove button if it is an edit
        if(is_edit){
            var remove_acl_button = new YAHOO.widget.Button('remove_acl_panel');
            remove_acl_button.set('label','Remove');
            remove_acl_button.on('click',function(){

                var url = "services/workgroup_manage.cgi?action=remove_acl";
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
                            var record_id = owned_interface_table.getSelectedRows()[0];
                            var interface_id = owned_interface_table.getRecord(record_id).getData("interface_id");
                            build_interface_acl_table(interface_id);
                        }
                    },
                    failure: function(req, resp){
                        alert("Error removing acl data");
                    },
                    scope: this
                },ds);
            }); 
        }else {
            $('#remove_acl_panel').css('display', 'none');
        }

        //fetch workgroups
        var workgroup_ds = new YAHOO.util.DataSource("services/workgroup_manage.cgi?action=get_all_workgroups");
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
                $('#acl_panel_workgroup').append("<option value>All</option>");
                for( var i = 0; i < resp.results.length; i++ ){
                    var id   = resp.results[i].workgroup_id;
                    var name = resp.results[i].name;
                    var option = "<option value='"+id+"'>"+name+"</option>";
                    $('#acl_panel_workgroup').append(option);
                }
                //select proper value and enabled save button if its an edit
                if(is_edit){
                    save_acl_button.set('disabled', false);
                    $('#acl_panel_workgroup').val( rec.getData("workgroup_id") )
                }
                //enable and update
                $("#acl_panel_workgroup").attr('data-placeholder', 'Select Workgroup');
                $("#acl_panel_workgroup").attr('disabled', false).trigger("liszt:updated");

            },
            failure: function(req, resp){
                throw("Error: fetching selections");
            },
            scope: this
        });

    };

    var owned_interface_table = build_owned_interface_table();

    var add_interface_acl = new YAHOO.util.Element('add_interface_acl');
    add_interface_acl.on('click', function(){
        show_interface_acl_panel({is_edit: false});
    });

}

YAHOO.util.Event.onDOMReady(index_init);


</script>
