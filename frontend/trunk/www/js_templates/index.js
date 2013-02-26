<script>
  
  
  function index_init(){
    
    // set up the new circuit button
    //    var new_circuit = new YAHOO.widget.Button("new_circuit",
    //					      {label: "New Circuit"}
    //					     );

    var new_circuit = document.getElementById('create_new_circuit');
    //    new_circuit.on("click", function(){
    //	    session.clear();
    //	    window.location = "index.cgi?action=edit_details";
    //	});
    
    
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
    
    
    // setup help stuff

    makeHelpPanel(["circuit_search", "circuit_search_label"], "Use this to filter the circuits table below. The table will filter as you type.");
}

YAHOO.util.Event.onDOMReady(index_init);


</script>