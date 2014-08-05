<script type='text/javascript' src='js_utilities/interface_acl_panel.js'></script>
<script type='text/javascript' src='js_utilities/datatable_utils.js'></script>
<script type='text/javascript' src='js_utilities/interface_acl_table.js'></script>
<script>


  function index_init(){
    session.clear();
    // set up the new circuit link
    var new_circuit = new YAHOO.util.Element('create_new_vlan');
    var checking_circuit_limit = false;
    new_circuit.on('click', function(e){
	    //window.location = "index.cgi?action=edit_details";
	    if([% is_read_only %] == 1){
		alert('Your account is read-only and can not provision a circuit');
		return;
	    }
        e.preventDefault();
        if(checking_circuit_limit){
            return;
        }else {
            checking_circuit_limit = true;
        }

        new_circuit.set("innerHTML","Checking Circuit Limit...");
        var circuit_limit_ds = new YAHOO.util.DataSource("services/data.cgi?action=is_within_circuit_limit&workgroup_id=" + session.data.workgroup_id );


        circuit_limit_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
        circuit_limit_ds.responseSchema = {
            resultsList: "results",
            fields: [{key: "within_limit", parser: "number"}],
            metaFields: {
              "error": "error"
            }
        };

        circuit_limit_ds.sendRequest("",{
            success: function(req,resp){
                if(parseInt(resp.results[0].within_limit)){
	                session.clear();
	                window.location = "index.cgi?action=edit_details";
                }else {
                    alert("Workgroup is already at circuit limit");
                    new_circuit.set("innerHTML","Create a New VLAN");
                    checking_circuit_limit = false;
                }
            },
            failure: function(req,resp){
                alert("Problem fetching circuit limit for workgroup");
                new_circuit.set("innerHTML","Create a New VLAN");
                checking_circuit_limit = false;
            }//,
            //argument: circuit_limit_ds
        }, this);

	});

    var add_user = new YAHOO.util.Element('request_user_add');
    add_user.on('click', function(){

	    var panel = new YAHOO.widget.Panel("request_user_add_p",
					       {width: 350,
						modal: true,
                                                fixedcenter: true,
                                                zIndex: 10,
                                                draggable: false
					       });

            panel.setHeader("Request a User to be added to this Workgroup");
            panel.setBody("<div id='user_add_error' style='color:#F00; margin-left:6em;margin-bottom:1em;'> </div>"+
                           "<div style='margin-bottom:8px;'><label for='username' class='soft_title'>Username:</label>" +
                          "<input id='username' type='text' size='20' style='float:right;margin-right: 60px;'>" +
                          "</div><div style='margin-bottom:8px;'><label for='given_name' class='soft_title'>Given Name:</label>" +
                          "<input id='given_name' type='text' size='20' style='float:right;margin-right: 60px'>" +
			  "</div><div style='margin-bottom:8px;'><label for='family_name' class='soft_title'>Family Name:</label>" +
			  "<input id='family_name' type='text' size='20' style='float:right;margin-right: 60px'>" +
			  "</div><div style='margin-bottom:8px;'><label for='email_address' class='soft_title'>Email Address:</label>" +
			  "<input id='email_address' type='text' size='20' style='float:right;margin-right: 60px'>" +
              "</div><div style='margin-bottom:8px;'><label for='phone_number' class='soft_title'>Phone Number:</label>" +
              "<input id='phone_number' type='text' size='20' style='float:right;margin-right: 60px'> </div>"
                         );
            panel.setFooter("<div id='send_user_add'></div><div id='cancel_user_add'></div>");

            panel.render();


	    var send_user_add_button = new YAHOO.widget.Button('send_user_add');
            send_user_add_button.set('label','Send Request');
            send_user_add_button.on('click',function(){

		    //                    panel.destroy();
		    var username = document.getElementById('username').value;
		    var given_name = document.getElementById('given_name').value;
		    var family_name = document.getElementById('family_name').value;
		    var email_address = document.getElementById('email_address').value;
            var phone_number = document.getElementById('phone_number').value;

            if (!username || !given_name || !family_name || !email_address || !phone_number)
                {
                    var user_add_error =YAHOO.util.Dom.get('user_add_error');
                    user_add_error.innerHTML="All Fields Are Required";
                    return;
                }
            else {
                var user_add_error =YAHOO.util.Dom.get('user_add_error');
                user_add_error.innerHTML="";
                panel.hide();

            }

		    var subject = "Please Add User to workgroup " + session.data.workgroup_name  + " (ID=" + session.data.workgroup_id + ")";
		    var body = "Details: <br><table><tr><td>Username:</td><td>" + username + "</td></tr><tr><td>Given Name:</td><td>" + given_name + "</td></tr><tr><td>Family Name:</td><td>" + family_name + "</td></tr><tr><td>Email Address:</td><td>" + email_address + "</td><td>Phone Number:</td><td>"+ phone_number + "</td></tr></table>";
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

    var url = location.href.split('#');

      if (url.length > 1) {

          var tab_fragment = url[1];

          var tabset = tabs.get('tabs');
          for (var i = 0; i < tabset.length; i++) {
              console.log(tabset[i].get('href'));
              if (tabset[i].get('href') == '#' + tab_fragment) {
                  tabs.selectTab(tabs.getTabIndex(tabset[i]) );
                  break;
              }
          }
      }
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

    
    var ds = new YAHOO.util.DataSource(dsString);
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [
    {key: "circuit_id", parser: "number"},
    {key: "description"},
    {key: "external_identifier"},
    {key: "bandwidth", parser: "number"},
    {key: "name"},
    {key: "endpoints"},
    {key: "workgroup.name"}
		 ],
	metaFields: {
	    error: "error"
	}
    };
    

    var columns = [
		   
		   {key: "description", label: "Description", sortable: true, width: 400},
		   {key: "endpoints", label: "Endpoints", sortable: true, width: 280, formatter: function(el, rec, col, data){

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
		   {key: "workgroup.name", label: "Owned By", sortable: true, width: 90, formatter: function(el, rec, col, data){
			   el.innerHTML = "<center>"+data+"</center>";
		       }
		   },
		   {key: "external_identifier", label: "GRI", sortable: true, width: 90, formatter: function(el, rec,col,data){
			   if(data == null){
			       data = "N/A";
			   }
			   el.innerHTML = "<enter>"+data+"</center>";
		       }
		   }
		   ];

    var config = {
	    paginator: new YAHOO.widget.Paginator({rowsPerPage: 10,
					                           containers: ["circuit_table_nav"]

					                          }),
        formatRow: function (elTr, oRecord) {
            if (oRecord.getData('workgroup.name') != session.data.workgroup_name){
                Dom.addClass(elTr,'guest-workgroup');
            }
            return true;
        }
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
	fields: ["name","link_id","status","operational_state","fv_status"]
    };

    var link_status_columns = [
			       {key: "name", label: "Link", width: 200},
			       {key: "status", label: "Status", width: 40, formatter: function(elLiner, oRec, oCol, oData){
				       if(oRec.getData('fv_status') == 'down'){
					   if(oRec.getData('status') == 'up'){
					       elLiner.innerHTML = "<font color='red'>impaired</font>";
					   }else{
					       elLiner.innerHTML = "<font color='red'>" + oRec.getData('status') + "</font>";
					   }
				       }else{
					   if(oRec.getData('status') == 'up'){
                                               elLiner.innerHTML = "<font color='green'>up</font>";
                                           }else{
                                               elLiner.innerHTML = "<font color='red'>" + oRec.getData('status') + "</font>";
                                           }
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
	fields: ["node_name","interface_name","operational_state","description","vlan_tag_range","is_owner", "owning_workgroup.name"]
    };

    var avail_resource_cols = [
    {key: "node_name",sortable: true, label: "Node", width: 250},
    {key: "interface_name", sortable: true, label: "Interface", width: 90},
    {key: "description", sortable: true,  label: "Description", width: 250},
    {key: "vlan_tag_range", sortable: true,  label: "VLAN Range", width: 150, formatter: function(elLiner, oRec, oCol, oData){
	    var string = oData.replace(/^-1/, "untagged");
	    elLiner.innerHTML = string;
	}},
    {key: "owning_workgroup.name", sortable: true, label: "Owned By", width: 100}
    
			       ];

    var avail_resource_table_config = {
	height: '223px',
	formatRow: function (elTr, oRecord) {
            if (oRecord.getData('is_owner') != 1){
                Dom.addClass(elTr,'guest-workgroup');
            }
            return true;
        }
    }

    var avail_resource_table = new YAHOO.widget.ScrollingDataTable("available_resource_table",avail_resource_cols, avail_resource_ds, avail_resource_table_config);

    // setup help stuff
    makeHelpPanel(["circuit_search", "circuit_search_label"], "Use this to filter the circuits table below. The table will filter as you type.");


    //---
    //--- Set up Acl stuff
    //---A
    var interface_acl_table;
    var interface_acl_edit_panel;
    function build_interface_acl_table(interface_id){
        interface_acl_table = get_interface_acl_table("interface_acl_table", interface_id, {
            on_show_edit_panel: function(oArgs){
                var record = oArgs.record;
                var interface_id = oArgs.interface_id;
                //this.interface_acl_panel
                if(interface_acl_edit_panel){
                    interface_acl_edit_panel.destroy();
                }
                //if(interface_acl_table){
                //    interface_acl_table.destroy();
                //}
                interface_acl_edit_panel = get_interface_acl_panel("interface_acl_edit_panel", interface_id, {
                    modal: true,
                    fixedcenter: true,
                    is_edit: true,
                    record: record,
                    on_remove_success: function(){
                        build_interface_acl_table(interface_id);
                    },
                    on_add_edit_success: function(oArgs){
                        var interface_id = oArgs.interface_id;
                        build_interface_acl_table(interface_id);
                    }
                });
            }
        });
        return interface_acl_table;
    }
    var add_interface_acl_panel; 
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
            {key: "node_name", label: "Node",sortable:true},
            {key: "interface_name", label: "Interface",sortable:true}
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

    var owned_interface_table = build_owned_interface_table();

    var add_interface_acl = new YAHOO.util.Element('add_interface_acl');
    var oLinkButton1 = new YAHOO.widget.Button("add_interface_acl");
    var add_interface_acl_panel;
    add_interface_acl.on('click', function(){
        var record_id = owned_interface_table.getSelectedRows()[0];
        var interface_id = owned_interface_table.getRecord(record_id).getData("interface_id");
        if(add_interface_acl_panel){
            add_interface_acl_panel.destroy();
        }
        
        add_interface_acl_panel = get_interface_acl_panel("interface_acl_panel", interface_id, {
            is_edit: false,
            modal: true,
            fixedcenter: true,
            on_remove_success: function(){
                var record_id = owned_interface_table.getSelectedRows()[0];
                var interface_id = owned_interface_table.getRecord(record_id).getData("interface_id");
                var interface_acl_table = build_interface_acl_table(interface_id);
            },
            on_add_edit_success: function(oArgs){
                var interface_id = oArgs.interface_id;
                var interface_acl_table = build_interface_acl_table(interface_id);
            }
        });
    });

}

YAHOO.util.Event.onDOMReady(index_init);


</script>
