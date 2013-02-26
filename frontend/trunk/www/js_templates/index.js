<script>
  
  
  function index_init(){
    
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
                    panel.destroy();
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
			table_filter.call(circuit_table,search_value);
	    }
	    else{
		if (searchTimeout) clearTimeout(searchTimeout);
		
		searchTimeout = setTimeout(function(){
			table_filter.call(circuit_table,search_value);
		    }, 400);
		
	    } 
	    
	}
	);
    

    // build the circuits table

    var ds = new YAHOO.util.DataSource("services/data.cgi?action=get_existing_circuits&workgroup_id="+session.data.workgroup_id);
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
		   
		   {key: "description", label: "Description", width: 230},
		   {key: "endpoints", label: "Endpoints", width: 230, formatter: function(el, rec, col, data){

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
    });
    
    

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

    // setup help stuff
    makeHelpPanel(["circuit_search", "circuit_search_label"], "Use this to filter the circuits table below. The table will filter as you type.");
}

YAHOO.util.Event.onDOMReady(index_init);


</script>