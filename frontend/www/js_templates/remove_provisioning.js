<script>

function init(){  

    setPageSummary("Remove Provisioning","Verify that all the information is correct, then click the Submit Circuit Removal button.");
    
    var next_button = setSubmitButton("Submit Circuit Removal", function(){

	    if (session.data.interdomain == 1){
		removeRemoteCircuit.call(this);
	    }
	    else {
		removeLocalCircuit.call(this);
	    }

	});
  
    // defined in circuit_details_box.js
    var endpoint_table = summary_init({ remove_only: true });
   
    var nddi_map = new NDDIMap("map", session.data.interdomain == 1);

    var layout = makePageLayout(nddi_map, {map_width: 950,
					   max_resize: 950});
    
    legend_init(nddi_map);
    
    //nddi_map.showDefault();
    
    nddi_map.on("loaded", function(){
	    this.updateMapFromSession(session);
	    
	    if (session.data.interdomain == 1){
                this.getInterDomainPath(session.data.circuit_id);
	    }

	});      
}

function removeRemoteCircuit(){
    this.set("label", "Provisioning remote circuit, please wait...");
    this.set("disabled", true);

    var ds = new YAHOO.util.DataSource("services/remote.cgi");
    ds.connMethodPost = true;
    ds.connTimeout    = (30 * 1000) * 10; // 300 seconds
    ds.responseType   = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "status"},
                 {key: "message"},
                 {key: "gri"}
		 ],
	metaFields: {
	    error: "error"
	}
    };

    var remove_time    = session.data.remove_time;

    // get the times from milli into seconds
    if (remove_time != -1){
	remove_time = parseInt(remove_time / 1000);
    }

    var circuit_id     = session.data.circuit_id;

    var postVars = "action=cancel_reservation&bandwidth=" + parseInt(session.data.bandwidth / (1000 * 1000));
    postVars += "&circuit_id=" + circuit_id;
    postVars += "&end_time=" + remove_time;

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

			       status_panel.setHeader("OSCARS: Canceling...");
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
			   if (status == "SUCCESS" || status == "CANCELLED"){
			       status_panel.hide();

			       alert("Circuit has been successfully removed.",
				     function(){
					 window.location = "?action=index";
				     });
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

function removeLocalCircuit(){

    this.set("label", "Removing, please wait...");
    this.set("disabled", true);

    var remove_time    = session.data.remove_time;

    if (remove_time != -1){
	remove_time = parseInt(remove_time / 1000);
    }
    
    var circuit_id     = session.data.circuit_id;
    
    var ds = new YAHOO.util.DataSource("services/provisioning.cgi");
    ds.connMethodPost = true;
    ds.connTimeout    = (30 * 1000) * 10; // 300 seconds
    ds.responseType   = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "success", parser: "number"},
                 {key: "circuit_id", parser: "number"}    
		 ],
	metaFields: {
	    error: "error",
            error_text: "error_text"
	}
    };

    var postVars = "method=remove_circuit&circuit_id="+encodeURIComponent(circuit_id)+"&remove_time="+encodeURIComponent(remove_time) + "&workgroup_id=" + encodeURIComponent(session.data.workgroup_id) + "&type=" + encodeURIComponent(session.data.circuit_type);

    ds.sendRequest(postVars, {success: handleSuccess, failure: handleFailure, scope: this});
}

function handleSuccess(request, response){

    this.set("label", "Submit Circuit Removal");
    this.set("disabled", false);

    if (response.meta.error){
	alert(response.meta.error_text);
	return;
    }

    var results = response.results;

    if (results && results[0].success == 1){

	var remove_time = session.data.remove_time;
	var circuit_id  = session.data.circuit_id;

	if (remove_time == -1){

	    session.clear();
	    session.save();

	    alert("Circuit has been successfully removed.",
		  function(){
		      window.location = "?action=index";
		  });
	}
	else{
	    alert("Circuit removal has been successfully scheduled.",
		  function(){
		      window.location = "?action=view_details";
		  });
	}
    }
    else{
	alert("Unknown return value in provisioning.");
    }
}

function handleFailure(request, response){
    this.set("label", "Submit Circuit Removal");
    this.set("disabled", false);
    alert("Error while communicating with server. If this problem continues to exist, please notify your system administrator.");
}

YAHOO.util.Event.onDOMReady(init);

  
</script>
