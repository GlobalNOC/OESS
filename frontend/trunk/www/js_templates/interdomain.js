
<script>
  
function make_network_tree(){

    var tree = new YAHOO.widget.TreeView("networks_tree");

    var ds = new YAHOO.util.DataSource("services/remote.cgi?action=get_networks&workgroup_id="+session.data.workgroup_id);
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [
                  {key: "urn"},
                  {key: "name"},
                  {key: "links"}
		 ],
	
    };

    ds.sendRequest("", 
		   {
		       success: function(req, resp){

			   var networks = resp.results;

			   if (! networks){
			       return null;
			   }

			   var root = tree.getRoot();			   

			   for (var i = 0; i < networks.length; i++){

			       var network_urn  = decodeURIComponent(networks[i].urn);
			       var network_name = decodeURIComponent(networks[i].name); 

			       var node = new YAHOO.widget.TextNode(network_name, root);

			       var links = networks[i].links;

			       for (var j = 0; j < links.length; j++){

				   var info      = links[j];
				   var node_name = decodeURIComponent(info.node);
				   var port_name = decodeURIComponent(info.port);
				   var link_name = decodeURIComponent(info.link);
				   var node_urn  = decodeURIComponent(info.urn);

				   if (node_name == "*" || port_name == "*"){
				       continue;
				   }

				   var child = new YAHOO.widget.TextNode({label: node_name + " - " + port_name + " - " + link_name,
									  urn: node_urn,
				                                          node: node_name,
				                                          port: port_name,
									  domain: network_name
				                                          },
				                                          node);
			       }
			   }

			   tree.render();
	   
		       },
		       failure: function(req, resp){
		       }
		   }
		   );

    return tree;

}
  
function init(){  
    
    setPageSummary("Interdomain Endpoints","Pick at least two endpoints from the map below.");

    setNextButton("Proceed to Step 5: Scheduling", "?action=scheduling", verify_inputs);    

  
    var map = new NDDIMap("map", true);
    
    var layout = makePageLayout(map, {map_width: Math.min(session.data.map_width || 600, 600),
				      max_resize: 600});

    var endpoint_table = summary_init(false, true);

    endpoint_table.subscribe("rowDeleteEvent", function(oArgs){
	    var node = oArgs.oldData.node;

	    map.removeNode(node);
	    
	    save_session();
    });
    

    legend_init(map, true);
    
    map.showDefault();

    map.on("loaded", function(){
	    this.updateMapFromSession(session);
	    
	    this.connectSessionEndpoints(session);
	});

    var tree = make_network_tree();

    var panel;

    tree.subscribe("clickEvent", function(oArgs){
	    var tree_element = oArgs.node;

	    if (panel){
		panel.destroy();
		panel = null;
	    }

	    // this is a network level element we clicked on, skip
	    if (! tree_element.data.urn){
		return;
	    }

	    var urn   = tree_element.data.urn;
	    var node  = tree_element.data.node; 
	    var port  = tree_element.data.port;
	    var domain = tree_element.data.domain;

	    var region = YAHOO.util.Dom.getRegion(tree_element.contentElId);

	    var components = makeTagSelectPanel([region.left - 10, region.bottom], port);

	    panel          = components.panel;
	    var tagged     = components.tagged_input;
	    var add_button = components.add_button; 

	    panel.show();

	    var vlan_input = YAHOO.util.Dom.get('new_vlan_tag');

	    vlan_input.focus();

	    add_button.on("click", function(oArgs){

		    var new_tag;

		    if (tagged.get('element').checked){
			new_tag = vlan_input.value;

			if (! new_tag){
			    alert("You must specify an outgoing VLAN tag.");
			    return;
			}
			
			if (! new_tag.match(/^\d+$/) || new_tag >= 4096 || new_tag < 1){
			    alert("You must specify a VLAN tag between 1 and 4095.");
			    return;
			}
		    }
		    
		    else {
			new_tag = -1;
		    }	

		    if (endpoint_table.getRecordSet().getRecords().length == 2){
			alert("You can only have exactly two endpoints.");
			return;
		    }

                    //do some validation on the endpoint
                    

		    endpoint_table.addRow({interface: port,
				           node: node,
				           tag: new_tag,
				           urn: urn});

		    if (panel){
			panel.destroy();
			panel = null;
		    }

		    map.showNode(node);		    

		    save_session();

		});
	    
	    return false;

	});

  function save_session(){
    
    var records = endpoint_table.getRecordSet().getRecords();

    session.data.endpoints = [];

    for (var i = 0; i < records.length; i++){
      
      var node      = records[i].getData('node');
      var interface = records[i].getData('interface');
      var tag       = records[i].getData('tag');
      var urn       = records[i].getData('urn');
      
      session.data.endpoints.push({interface: interface,
		                   node: node,
		                   tag: tag,
		                   urn: urn
		                   });
    }
    
    session.save();
    

    map.updateMapFromSession(session);
    map.connectSessionEndpoints(session);

  }

  function verify_inputs(){

    var records = endpoint_table.getRecordSet().getRecords();
    
    if (records.length != 2){
      alert("You must have exactly two endpoints.");
      return false;
    }       
    
    save_session();

    return true;
  }
    
}

YAHOO.util.Event.onDOMReady(function(){
			      try{
				init();
			      }catch(e){
				alert(e);
			      }
			    });
  
</script>