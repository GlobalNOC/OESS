[% INCLUDE js_templates/graph.js %]

<script>

function init(){

    var ds = make_circuit_details_datasource();

    ds.sendRequest("", {success: function(req, resp){

		             var details = resp.results[0];

			     save_session_from_datasource(details);

		             page_init();
	                },
		        failure: function(req, resp){
		             alert("Error loading circuit details.");
	                },
		   });

}

function make_circuit_details_datasource(){
    var ds = new YAHOO.util.DataSource("services/data.cgi?action=get_circuit_details&circuit_id="+session.data.circuit_id);
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [
           {key: "circuit_id", parser: "number"},
           {key: "description"},     
           {key: "bandwidth", parser: "number"},
           {key: "links"},
           {key: "backup_links"},
           {key: "endpoints"},
           {key: "state"},
           {key: "active_path"}
	]	
    };

    return ds;
}

function save_session_from_datasource(details){
    session.clear();
    
    session.data.circuit_id   = details.circuit_id;
    session.data.description  = details.description;
    session.data.bandwidth    = details.bandwidth * 1000000;
    session.data.state        = details.state;
    session.data.active_path  = details.active_path;
    session.data.interdomain  = 0;
    session.data.endpoints    = [];
    session.data.links        = [];
    session.data.backup_links = [];
    session.data.passthrough  = [];
    
    for (var i = 0; i < details.endpoints.length; i++){
	var endpoint = details.endpoints[i];

	var endpoint_data = {node: endpoint.node,
			     interface: endpoint.interface,
			     tag: endpoint.tag,
			     role: endpoint.role,
			     urn: endpoint.urn,
			     local: endpoint.local
	                     };

	if (endpoint.local == 0){
	    session.data.interdomain = 1;
	}

	if (endpoint.role == "trunk"){
	    session.data.passthrough.push(endpoint_data);			                    	 
	}
	else{
	    session.data.endpoints.push(endpoint_data);
	}

    }

    for (var i = 0; i < details.links.length; i++){
	var path_component = details.links[i];
	session.data.links.push(path_component.name);
    }
    
    for (var i = 0; i < details.backup_links.length; i++){
	var path_component = details.backup_links[i];
	session.data.backup_links.push(path_component.name);
    }
    
    session.save();
}

function page_init(){
  // defined in circuit_details_box.js
  var endpoint_table = summary_init();
   
  var nddi_map = new NDDIMap("map", session.data.interdomain == 1);
  
  legend_init(nddi_map, false, true);
    
  nddi_map.showDefault();
  
  nddi_map.on("loaded", function(){
	  this.updateMapFromSession(session, session.data.interdomain == 1);

	  if (session.data.interdomain == 1){			  
	      getInterDomainPath(this);
	  }

      });
  
  var edit_button = new YAHOO.widget.Button("edit_button", {label: "Edit Circuit"});

  edit_button.on("click", function(){

	  session.data.interdomain = 0;

	  var endpoints = [];

	  for (var i = 0; i < session.data.endpoints.length; i++){
	      if (session.data.endpoints[i].local == 1){
		  endpoints.push(session.data.endpoints[i]);
	      }
	  }

	  if (endpoints.length < 2){
	      for (var i = 0; i < session.data.passthrough.length; i++){
		  if (session.data.passthrough[i].local == 1){
		      endpoints.push(session.data.passthrough[i]);
		  }
	      }
	  }

	  session.data.endpoints = endpoints;

	  session.save();

	  window.location = "?action=edit_details";
      });

  var remove_button = new YAHOO.widget.Button("remove_button", {label: "Remove Circuit"});

  remove_button.on("click", function(){

	  window.location = "?action=remove_scheduling";
      });


  // show the edit interdomain stuff if we're an interdomain circuit
  if (session.data.interdomain == 1){

      var edit_interdomain = new YAHOO.widget.Button("edit_interdomain_button", {label: "Edit Interdomain"});

      edit_interdomain.on("click", function(){
	      window.location = "?action=edit_details";
	  });
      
  }
  else {
      YAHOO.util.Dom.get("edit_interdomain_button").parentNode.style.display = "none";
  }


  var tabs = new YAHOO.widget.TabView("details_tabs");

  setupMeasurementGraph();

  setupScheduledEvents();

  setupNetworkEvents();

  // we can poll the map to show intradomain status updates unless we're interdomain
  if (session.data.interdomain == 0){
      setInterval(function(){
	      
	      var ds = make_circuit_details_datasource();

	      ds.sendRequest("", {success: function(req, resp){
			  var details = resp.results[0];
			  
			  save_session_from_datasource(details);
			  
			  for (var i = 0; i < session.data.endpoints.length; i++){
			      nddi_map.removeNode(session.data.endpoints[i].node);
			  }
			  
			  nddi_map.updateMapFromSession(session, true);			  
		      },
			  failure: function(req, resp){
			  
		      }
		  });
	  

	  }, 10000);
  }

}

function setupMeasurementGraph(){

    var date = new Date();

    var now  = date.valueOf() / 1000;

    var then = now - 600;
    
    var graph = new MeasurementGraph("traffic_graph",
				     "traffic_legend",
				     {
					 title:      session.data.description,
					 circuit_id: session.data.circuit_id,
					 start:      then,
					 end:        now
				     }
				     );

    var time_select = new YAHOO.util.Element(YAHOO.util.Dom.get("traffic_time"));
    time_select.on("change", function(){
	    var new_start = this.get('element').options[this.get('element').selectedIndex].value;

	    var date = new Date();

	    graph.options.end   = date.valueOf() / 1000;

	    graph.options.start = graph.options.end - new_start;

	    graph.render();
	});

    return graph;
}

function getInterDomainPath(map){

    YAHOO.util.Dom.get("interdomain_path_status").innerHTML = "Querying interdomain path....";

    var ds = new YAHOO.util.DataSource("services/remote.cgi?action=query_reservation&circuit_id="+session.data.circuit_id);
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "status"},
                 {key: "message"},
                 {key: "path"}
		 ]	
    }

    ds.sendRequest("", 
		   {
		       success: function(req, resp){

			   var endpoints = resp.results[0].path;

			   for (var i = 0; i < endpoints.length; i++){

			       var from_node = endpoints[i].from_node;
			       var from_lat  = parseFloat(endpoints[i].from_lat);
			       var from_lon  = parseFloat(endpoints[i].from_lon);

			       var to_node   = endpoints[i].to_node;
			       var to_lat    = parseFloat(endpoints[i].to_lat);			       
			       var to_lon    = parseFloat(endpoints[i].to_lon);			       

			       if (from_node == to_node){
				   continue;
			       }

			       map.showNode(from_node, null, {"node_lat": from_lat, "node_long": from_lon});
			       map.showNode(to_node, null, {"node_lat": to_lat, "node_long": to_lon});

			       map.connectEndpoints([from_node, to_node]);
			   }

			   YAHOO.util.Dom.get("interdomain_path_status").innerHTML = "Total Interdomain Path";

		       },
		       failure: function(req, resp){
			   YAHOO.util.Dom.get("interdomain_path_status").innerHTML = "Unable to query interdomain path.";
		       }
		   }
		   );

}

function setupScheduledEvents(){


    YAHOO.util.Dom.get("scheduled_events_table").innerHTML = "Coming soon...";
    return;

    var ds = new YAHOO.util.DataSource("services/data.cgi?action=get_circuit_scheduled_events&circuit_id="+session.data.circuit_id);
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "user"},
                 {key: "registration_time"},
                 {key: "activation_time"},
                 {key: "circuit_layout"},
                 {key: "completed"}
		 ]
    };

    var cols = [{key: "user", label: "By", width: 101},
		{key: "registration_time", label: "Scheduled", width: 122},
		{key: "activation_time", label: "Activated", width: 121},
		{label: "Completed", formatter: function(el, rec, col, data){
			if (rec.getData('completed')){
			    el.innerHTML = "Yes";
			}
			else {
			    el.innerHTML = "No";
			}
		    }
		}
		];

    var config = {
	height: "255px"
    };
    
    var table = new YAHOO.widget.ScrollingDataTable("scheduled_events_table", cols, ds, config);

    table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
    table.subscribe("rowMouseoutEvent", table.onEventUnhighlightRow);

    table.subscribe("rowClickEvent", function(oArgs){

	    var record = this.getRecord(oArgs.target);

	    if (! record) return;

	    var region = YAHOO.util.Dom.getRegion(oArgs.target);
	    
	    showActionPanel(record, [region.left, region.top]);	    

	});

    return table;
}

function setupNetworkEvents(){

    YAHOO.util.Dom.get("historical_events_table").innerHTML = "Coming soon...";
    return;


    var ds = new YAHOO.util.DataSource("services/data.cgi?action=get_circuit_network_events&circuit_id="+session.data.circuit_id);
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "fullname"},
                 {key: "scheduled"},
                 {key: "activated"},
                 {key: "layout"},
                 {key: "completed"}
		 ]
    };

    var cols = [{key: "fullname", label: "By", width: 121},
		{key: "activated", label: "Scheduled On", width: 142},
		{key: "completed", label: "Done On", width: 141}
		];

    var config = {
	height: "255px"
    };
    
    var table = new YAHOO.widget.ScrollingDataTable("historical_events_table", cols, ds, config);

    table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
    table.subscribe("rowMouseoutEvent", table.onEventUnhighlightRow);

    table.subscribe("rowClickEvent", function(oArgs){

	    var record = this.getRecord(oArgs.target);

	    if (! record) return;

	    var region = YAHOO.util.Dom.getRegion(oArgs.target);
	    
	    showActionPanel(record, [region.left, region.top]);
	});

    return table;

}


YAHOO.util.Event.onDOMReady(init);
  
</script>