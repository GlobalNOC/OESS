<script>

function init(){  

    setPageSummary("Provisioning","Verify that all the information is correct, then click the Submit Circuit Request button.");
    
    var next_button = setSubmitButton("Submit Circuit Request", function(){

	    try{

	    if (session.data.interdomain == 1){
		saveRemoteCircuit.call(this);
	    }
	    else {
		saveLocalCircuit.call(this);
	    }

	    }catch(e){alert(e);}

	});
  
    // defined in circuit_details_box.js
    var endpoint_table = summary_init();
   
    var nddi_map = new NDDIMap("map", session.data.interdomain == 1);

    var layout = makePageLayout(nddi_map, {map_width: 950,
					   max_resize: 950});
    

    legend_init(nddi_map);
    
    //nddi_map.showDefault();
    
    nddi_map.on("loaded", function(){
	    this.updateMapFromSession(session);

	    if (session.data.interdomain == 1){
		this.connectSessionEndpoints(session);
	    }
	});  
    
    
}

function saveRemoteCircuit(){
    this.set("label", "Provisioning remote circuit, please wait...");
    this.set("disabled", true);

    var ds = new YAHOO.util.DataSource("services/remote.cgi");
    ds.connMethodPost = true;
    ds.connTimeout    = 30 * 1000; // 30 seconds
    ds.responseType   = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "gri"}],
	metaFields: {
	    error: "error"
	}
    };

    var provision_time = session.data.provision_time;
    var remove_time    = session.data.remove_time;
    var circuit_state = "active";
    // get the times from milli into seconds
    if (provision_time != -1){
	provision_time = parseInt(provision_time / 1000);
        circuit_state = 'scheduled';
    }

    if (remove_time != -1){
	remove_time = parseInt(remove_time / 1000);
    }

    var circuit_id     = session.data.circuit_id || -1;

    var action;
    if (circuit_id == -1){
	action = "create_reservation";
    }
    else {
	action = "modify_reservation";
    }

    var postVars = "action=" + action + "&bandwidth=" + parseInt(session.data.bandwidth / (1000 * 1000));
    postVars += "&circuit_id=" + circuit_id;
    postVars += "&start_time=" + provision_time;
    postVars += "&end_time=" + remove_time;
    postVars += "&description=" + encodeURIComponent(session.data.description);

    var endpoints = session.data.endpoints;

    var src_urn = endpoints[0].urn;
    var dst_urn = endpoints[1].urn;

    var src_tag = endpoints[0].tag;
    var dst_tag = endpoints[1].tag;

    postVars += "&src_urn=" + encodeURIComponent(src_urn);
    postVars += "&dst_urn=" + encodeURIComponent(dst_urn);

    postVars += "&src_vlan=" + encodeURIComponent(src_tag);
    postVars += "&dst_vlan=" + encodeURIComponent(dst_tag);
    postVars += "&state=" + encodeURIComponent(circuit_state);

    ds.sendRequest(postVars, 
		   {
		       success: function(req, resp){

			   var results = resp.results;

			   var gri = results[0].gri;

			   if (gri == null){
			       alert("Unable to acquire Global Reservation ID for remote circuit. If this problem continues to exist, please notify your system administrator.");
			   }
			   else{

			       var status_panel = new YAHOO.widget.Panel("status",
									 { width: "300px",
									   close: false,
									   draggable: false,
									   zindex:999,
									   visible: false,
									   modal: true,
									   fixedcenter: true
									 });


			       status_panel.render(document.body);

			       status_panel.setHeader("OSCARS: Provisioning...");
			       status_panel.setBody("<center>" +
						    "<label class='soft_title'>Status:</label>"+
						    "<div id='provisioning_status' class='status_text'></div>" +
						    "</center>");

			       status_panel.show();
			       
			       pollForStatus(gri, status_panel);
			   }

		       },
		       failure: function(req, resp){

			   this.set("label", "Submit Circuit Request");
			   this.set("disabled", false);

			   alert("There was an error talking to the remote service. If this problem continues to exist, please notify your system administrator.");
		       },
		       scope: this
		   });


}

var total_failures = 0;

function pollForStatus(gri, status_panel){

    var ds = new YAHOO.util.DataSource("services/remote.cgi?action=query_reservation&gri="+encodeURIComponent(gri));
    ds.responseType   = YAHOO.util.DataSource.TYPE_JSON;
    ds.connTimeout    = 10 * 1000; // 10 seconds
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "status"},
                 {key: "message"}
		 ]
    };
    
    ds.sendRequest("",
		   {
		       success: function(req, resp){

			   var results = resp.results[0];

			   total_failures = 0;

			   var status = results.status;

			   YAHOO.util.Dom.get("provisioning_status").innerHTML = status;

			   // all set! Now we can figure out the circuit
			   if (status == "SUCCESS" || status == "ACTIVE"){
			       status_panel.hide();
			       getCircuitIdFromGRI(gri);
			   }
			   // uh oh, something went bad
			   else if (status == "FAILED" || status == "UNKNOWN"){
			       status_panel.hide();
			       alert("Remote provisioning reports an error.<br><br> " + results.message);
			   }
			   // otherwise we don't really know, keep polling
			   else {
			       pollForStatus(gri, status_panel);
			   }

		       },
		       failure: function(reqp, resp){

			       total_failures += 1;

			       // 3 fails in a row, the remote server is busted so give up
			       if (total_failures > 3){
				   status_panel.hide();
				   alert("Error while communicating with server. If this problem continues to exist, please notify your system administrator.");
			       }
			       else {
				   pollForStatus(gri, status_panel);
			       }
			       
		       }
		   });
}

function getCircuitIdFromGRI(gri){

    var ds = new YAHOO.util.DataSource("services/data.cgi?action=get_circuit_details_by_external_identifier&external_identifier="+encodeURIComponent(gri));
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "circuit_id", parser: "number"}]
    };

    ds.sendRequest("",
		   {
		       success: function(req, resp){

			   var results = resp.results;

			   session.clear();
			   session.data.circuit_id = results[0].circuit_id;
			   session.save();
			   
			   update_circuit_owner(gri);
			   
			   alert("Circuit successfully provisioned.",
				 function(){
				     window.location = "?action=view_details";
				 }
				 );


		       },
		       failure: function(req, res){
			   alert("Remote service reported success but we are unable to find the circuit. Please contact a system administrator about this.");
		       }
		   });

}

function saveLocalCircuit(){

    this.set("label", "Provisioning, please wait...");
    this.set("disabled", true);

    var workgroup_id = session.data.workgroup_id;

    var description = session.data.description;
    var bandwidth   = parseInt(session.data.bandwidth / (1000 * 1000));

    var provision_time = session.data.provision_time;
    var remove_time    = session.data.remove_time;
    var restore_to_primary = session.data.restore_to_primary;
    var circuit_state = 'active';
    // get the times from milli into seconds
    if (provision_time != -1){
	provision_time = parseInt(provision_time / 1000);
        circuit_state = 'scheduled';
    }

    if (remove_time != -1){
	remove_time = parseInt(remove_time / 1000);
    }
    
    var endpoints          = session.data.endpoints;
    var links              = session.data.links;
    var backups            = session.data.backup_links;
    var static_mac = session.data.static_mac_routing;

    var circuit_id     = session.data.circuit_id || -1;
    
    var ds = new YAHOO.util.DataSource("services/provisioning.cgi");
    ds.connMethodPost = true;
    ds.connTimeout    = 30 * 1000; // 30 seconds
    ds.responseType   = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "success", parser: "number"},
                 {key: "circuit_id", parser: "number"}    
		 ],
	metaFields: {
	    error: "error",
	    warning: "warning"
	}
    };

    var postVars = "action=provision_circuit&circuit_id="+encodeURIComponent(circuit_id)
        +"&description="+encodeURIComponent(description)
        +"&bandwidth="+encodeURIComponent(bandwidth)
        +"&provision_time="+encodeURIComponent(provision_time)
        +"&remove_time="+encodeURIComponent(remove_time)
        +"&workgroup_id="+workgroup_id
        +"&restore_to_primary="+restore_to_primary
        +"&static_mac="+static_mac
        +"&state=" + circuit_state;
    
    for (var i = 0; i < endpoints.length; i++){
        postVars += "&node=" + encodeURIComponent(endpoints[i].node);
        postVars += "&interface=" + encodeURIComponent(endpoints[i].interface);
        postVars += "&tag=" + encodeURIComponent(endpoints[i].tag);
        postVars += "&endpoint_mac_address_num=" +  encodeURIComponent(endpoints[i].mac_addrs.length);

        var mac_addresses = endpoints[i].mac_addrs;
        for(var j = 0; j < mac_addresses.length; j++){
	        postVars += "&mac_address=" + encodeURIComponent(mac_addresses[j].mac_address);
        }
    }

    for (var i = 0; i < links.length; i++){
	postVars += "&link="+encodeURIComponent(links[i]);
    }

    for (var i = 0; i < backups.length; i++){
	postVars += "&backup_link="+encodeURIComponent(backups[i]);
    }


    //alert(postVars);
    ds.sendRequest(postVars, {success: handleLocalSuccess, failure: handleLocalFailure, scope: this});

}

function handleLocalSuccess(request, response){

    this.set("label", "Submit Circuit Request");
    this.set("disabled", false);

    if (response.meta.error){
	alert("Error - " + response.meta.error);
	return;
    }

    var results = response.results;
    
    var provision_time = session.data.provision_time;
    
    if (results && results[0].success == 1){

	if (provision_time == -1){
	    session.clear();
	    session.data.circuit_id = results[0].circuit_id;
	    session.save();

	    var warning = "";

	    if (response.meta && response.meta.warning){
		warning = "Warning: " + response.meta.warning;
	    }

	    alert("Circuit successfully provisioned.<br>" + warning,
		  function(){
		      window.location = "?action=view_details";
		  }
		  );
	}
	else{
	    alert("Circuit successfully scheduled.",
		  function(){
		      window.location = "?action=index";
		  }
		  );
	}
    }
    else {
	    alert("Unknown return value in provisioning.");
    }
}

function update_circuit_owner(gri){
    var ds = new YAHOO.util.DataSource("services/remote.cgi?action=update_circuit_owner&gri="+encodeURIComponent(gri) + "&workgroup_id=" + encodeURIComponent(session.data.workgroup_id));

    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;

    ds.responseSchema = {
        resultsList: "results",
	fields: [{key: "success"},
    {key: "error"},
    {key: "message"}]
    };

    ds.sendRequest("",
                   {
                       success: function(req, resp){
			   var data = resp.results;
			   if(!results.success){
			       alert('An error occured changing circuit ownership');
			   }
		       },failure: function(req,resp){
			   alert('Unable to change circuit ownership, the circuit probably exists, but is not visible to your workgroup');
		       }
		   });
}

function handleLocalFailure(request, response){
    this.set("label", "Submit Circuit Request");
    this.set("disabled", false);
    alert("Error while communicating with server. If this problem continues to exist, please notify your system administrator.");
}

YAHOO.util.Event.onDOMReady(init);

  
</script>
