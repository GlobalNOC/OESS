<script>

function makePathTable(){
  
  var ds = new YAHOO.util.DataSource([]);
  ds.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
  
  var cols = [{key: "link", label: "Backup Path", width: 200}
	     ];
  
  var configs = {
    height: "337px"
  };
  
  var table = new YAHOO.widget.ScrollingDataTable("path_table", cols, ds, configs);
  
  var links = session.data.backup_links || [];
  
  for (var i = 0; i < links.length; i++){
    table.addRow({link: links[i]});
  }
  
  return table;
}  
  
function init(){  

  setPageSummary("Backup Path","Choose a backup path from the map below by clicking on links between nodes. This path should be as physically redundant as possible.");
  
  setNextButton("Proceed to Step 5: Scheduling", "?action=scheduling", verify_inputs);
  
  // defined in circuit_details_box.js
  var endpoint_table = summary_init();
  
  var path_table = makePathTable();
  
  var nddi_map = new NDDIMap("map");

  var layout = makePageLayout(nddi_map, {map_width: session.data.map_width,
					 max_resize: 700});  
 
  legend_init(nddi_map);
  
  var shortest_path_button = new YAHOO.widget.Button("shortest_path_button", {label: "Suggest Shortest Backup Path"});
  
  //nddi_map.showDefault();
  
  
  shortest_path_button.on("click", function(){

	                    this.set('disabled', true);
			    this.set('label', 'Calculating shortest backup path...');			    

			    var url = "services/data.cgi?action=get_shortest_path";
			    
			    for (var i = 0; i < session.data.endpoints.length; i++){
			      var node = session.data.endpoints[i].node;
			      url += "&node=" + encodeURIComponent(node);
			    }
			    
			    for (var j = 0; j < session.data.links.length; j++){
			      var link = session.data.links[j];
			      url += "&link=" + encodeURIComponent(link);
			    }
			    
			    url += "&bandwidth=" + session.data.bandwidth;
			    
			    var ds = new YAHOO.util.DataSource(url);
			    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
			    ds.responseSchema = {
			      resultsList: "results",
			      fields: [
			        {key: "link"}
			      ],
			      metaFields: {
				error: "error",
				warning: "warning"
			      }
			    }
			    
			    ds.sendRequest("", {success: function(req, resp){
					          this.set('disabled', false);
						  this.set('label', 'Suggest Shortest Backup Path');

						  if (resp.meta.error){
						    alert("Error - " + resp.meta.error);
						    return;
						  }
						  
						  path_table.deleteRows(0, path_table.getRecordSet().getRecords().length);
						  
						  for (var i = 0; i < resp.results.length; i++){
						    path_table.addRow({link: resp.results[i].link});
						  }
						  
						  save_session();
						  
						},
						failure: function(req, resp){
					           alert('Server error while determining shortest path.');
				                },
					        scope: this
					       });
			    
			  });
  
  nddi_map.on("loaded", function(){
		this.updateMapFromSession(session);
	      });  
  

  nddi_map.on("clickLink", function(e, args){

		var link    = args[0].name;
		
		var feature = args[0].feature;

		var was_previously_selected = -1;
		
		var records = path_table.getRecordSet().getRecords();
		
		for (var i = 0; i < records.length; i++){
		  if (records[i].getData('link') == link){
		    was_previously_selected = i;
		    break;
		  }
		}
		
		// if it was previous selected, deselect and remove from table
		if (was_previously_selected >= 0){
		  path_table.deleteRow(was_previously_selected);
		}
		else{
		  path_table.addRow({link: link});		  
		}		

		save_session();

	      });
  
  
  function save_session(){
    
    var records = path_table.getRecordSet().getRecords();
    
    session.data.backup_links = [];
    
    for (var i = 0; i < records.length; i++){
      
      var link      = records[i].getData('link');
      
      session.data.backup_links.push(link);

    }
    
    session.save();
    
    nddi_map.updateMapFromSession(session);

  }

  
  function verify_inputs(){

    var records = path_table.getRecordSet().getRecords();
    
    if (records.length == 0){

	showConfirm("Warning: You have selected no backup path. In the event of a failure along the primary path, your traffic will be interrupted. Are you sure you wish to continue?", 
		    function(){ 
			save_session(); 
			window.location = "?action=scheduling";
		    },
		    function(){}
		    );
	
	return false;
    
    }    
    
    save_session();
    
    return true;
  }
  
}

YAHOO.util.Event.onDOMReady(init);
  
</script>