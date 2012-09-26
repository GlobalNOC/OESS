<script>
  
  
  function index_init(){
    
    // set up the new circuit button
    var new_circuit = new YAHOO.widget.Button("new_circuit",
					      {label: "New Circuit"}
					     );
    
    new_circuit.on("click", function(){
	    session.clear();
	    window.location = "index.cgi?action=edit_details";
	});
    
    
    // set up the search bar

    var searchTimeout;
    
    var search = new YAHOO.util.Element(YAHOO.util.Dom.get('circuit_search'));
    
    search.on('keyup', function(e){
		
	    var search_value = this.get('element').value;
		
	    if (e.keyCode == YAHOO.util.KeyListener.KEY.ENTER){
		clearTimeout(searchTimeout);
		table_filter(search_value);
	    }
	    else{
		if (searchTimeout) clearTimeout(searchTimeout);
		
		searchTimeout = setTimeout(function(){
			table_filter(search_value);
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
		   {key: "circuit_id", label: "Identifier", width: 60, formatter: function(el, rec, col, data){
			   el.innerHTML = "<center>"+data+"</center>";
		       }
		   },
		   {key: "description", label: "Description", width: 230},
		   {key: "bandwidth", label: "Bandwidth", width: 80, formatter: function(el, rec, col, data){
			   
			   // gets returned as Mbps
			   var bandwidth = data;
			   
			   if (bandwidth >= 1000){
			       el.innerHTML = "<center>" + (bandwidth / 1000) + " Gbps </center>" ;
			   }
			   else{
			       el.innerHTML = "<center>" + bandwidth + " Mbps </center>";
			   }
	      
		       }
		   },
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
    
    function table_filter(search_term){

      if (! circuit_table.cache){
	return;
      }
      
      var new_rows = [];
      
      // empty search term, show everything again
      if (! search_term){
	new_rows = circuit_table.cache.results;
      }
      else{

	var regex = new RegExp(search_term, "i");
	
	for (var i = 0; i < circuit_table.cache.results.length; i++){
	
	  var row = circuit_table.cache.results[i];
	
	  for (var j = 0; j < columns.length; j++){
	    var col_name = columns[j]['key'];
	    
	    var value = row[col_name];

	    if (regex.exec(value)){
	      new_rows.push(row);
	      break;
	    }
	    
	  }
	  
	} 	
	
      }
      
      circuit_table.deleteRows(0, circuit_table.getRecordSet().getRecords().length);
      
      circuit_table.addRows(new_rows);

    }

    // setup help stuff

    makeHelpPanel(["circuit_search", "circuit_search_label"], "Use this to filter the circuits table below. The table will filter as you type.");
}

YAHOO.util.Event.onDOMReady(index_init);


</script>