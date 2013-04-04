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
    

    //build the switch status table
    var switch_status_ds = new YAHOO.util.DataSource("services/data.cgi?action=get_all_node_status");
    switch_status_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    switch_status_ds.responseSchema = {
	resultsList: "results",
	fields: ["name","node_id","operational_state"]
    };

    var switch_status_columns = [
				 {key: "name", label: "Switch", width: 200},
				 {key: "operational_state", label: "Status", width: 40, formatter: function(elLiner, oRec, oCol, oData){
					 if(oRec.getData('operational_state') == 'up'){
					     elLiner.innerHTML = "<font color='green'>up</font>";
					 }else{
					     elLiner.innerHTML = "<font color='red'>" + oRec.getData('operational_state') + "</font>";
					 }
				     }}
				 ];

    var switch_table = new YAHOO.widget.ScrollingDataTable("switch_status_table",switch_status_columns, switch_status_ds,{height: '210px'});

      var circuit_status_ds = new YAHOO.util.DataSource("services/data.cgi?action=get_existing_circuits&workgroup_id="+session.data.workgroup_id);
    circuit_status_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    circuit_status_ds.responseSchema = {
	resultsList: "results",
	fields: ["description","name","operational_state","active_path"]
    };

    var circuit_status_cols = [
			       {key: "description", label: "name", width: 200},
			       {key: "status", label: "Status", width: 100, formatter: function(elLiner, oRec, oColumn, oData){
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
    
    var nddi_map = new NDDIMap("network_status_map", session.data.interdomain == 0);

    nddi_map.showDefault();

    nddi_map.on("loaded", function(){
	    this.updateMapFromSession(session);
	});

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

    resource_map.showDefault();

    resource_map.on("loaded", function(){
            this.updateMapFromSession(session);
        });    

    var avail_resource_ds = new YAHOO.util.DataSource("services/data.cgi?action=get_all_resources_for_workgroup&workgroup_id=" + session.data.workgroup_id);
    avail_resource_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    avail_resource_ds.responseSchema = {
	resultsList: "results",
	fields: ["node_name","interface_name","operational_state","description"]
    };
    
    var avail_resource_cols = [
			       {key: "node_name", label: "Node", width: 200 },
			       {key: "interface_name", label: "Interface", width: 50},
			       {key: "description", label: "Description", width: 100},
			       {key: "operational_state", label: "Status", formatter: function(elLiner, oRec, oCol, oData){
				       if(oRec.getData('operational_state') == 'up'){
					   elLiner.innerHTML = "<font color='green'>up</font>";
				       }else{
					   elLiner.innerHTML = "<font color='red'>" + oRec.getData('operational_state') + "</font>";
				       }
				   }}
			       ];

    var avail_resource_table = new YAHOO.widget.ScrollingDataTable("available_resource_table",avail_resource_cols, avail_resource_ds, {height: '473px', width: '475px'});

    // setup help stuff
    makeHelpPanel(["circuit_search", "circuit_search_label"], "Use this to filter the circuits table below. The table will filter as you type.");
}

YAHOO.util.Event.onDOMReady(index_init);


</script>