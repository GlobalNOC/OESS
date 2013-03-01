<script>
  
function makeInterfacesTable(node){
  
  var ds = new YAHOO.util.DataSource("services/data.cgi?action=get_node_interfaces&node="+encodeURIComponent(node)+"&workgroup_id="+session.data.workgroup_id + "&show_down=1");
  ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
  ds.responseSchema = {
    resultsList: "results",
    fields: [
  {key: "name"},
  {key: "description"},
  {key: "status"}
    ],
    metaFields: {
      error: "error"
    }
  };
  
  var cols = [{key: "name", label: "Interface"},
	      {key: "description", label: "Description"},
              {key: "status", label: "Status", width: 120}
	     ];
  
  var configs = {
    height: "337px"
  };
  
  var table = new YAHOO.widget.ScrollingDataTable("add_interface_table", cols, ds, configs);

  table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
  table.subscribe("rowMouseoutEvent", table.onEventUnhighlightRow);
  table.subscribe("rowClickEvent", table.onEventSelectRow);

  return table;
}  
  
function init(){  

  setPageSummary("Intradomain Endpoints","Pick at least two endpoints from the map below.");
  
  setNextButton("Proceed to Step 3: Primary Path", "?action=primary_path", verify_inputs);
  
  var endpoint_table = summary_init();

  var nddi_map = new NDDIMap("map");

  var layout = makePageLayout(nddi_map, {map_width: session.data.map_width,
					 max_resize: 700});

  
  legend_init(nddi_map, true);
    
  nddi_map.showDefault();
  
  nddi_map.on("loaded", function(){
		this.updateMapFromSession(session);
	      });

  endpoint_table.subscribe("rowDeleteEvent", function(){
	  save_session();
      });

  nddi_map.on("clickNode", function(e, args){	  

		var node   = args[0].name;
		
		var feature = args[0].feature;

		if (this.table){
		  this.table.destroy();
		  save_session();
		}

		this.changeNodeImage(feature, this.ACTIVE_IMAGE);
		
		this.table = makeInterfacesTable(node);		
		
		this.table.subscribe("rowClickEvent", function(args){
  
                                  if (this.vlan_panel){
				    this.vlan_panel.destroy();
				    this.vlan_panel = undefined;
				  }
  
				  var rec = this.getRecord(args.target);
					      
				  var interface = rec.getData('name');
	
				  var state = rec.getData('status');
				  if(state == 'down'){
				      alert('Creating a circuit on a link down interface may prevent your circuit from functioning');
				  }
				  var region = YAHOO.util.Dom.getRegion(args.target);

				  var components = makeTagSelectPanel([region.left, region.bottom], interface);

				  var vlan_input = YAHOO.util.Dom.get('new_vlan_tag');
  

				  this.vlan_panel = components.panel;

				  var tagged = components.tagged_input;

				  var add_tag_button = components.add_button;
				  

				  this.vlan_panel.show();

				  function verify_and_add_vlan_tag(){

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

				      var ds = new YAHOO.util.DataSource("services/data.cgi?action=is_vlan_tag_available&vlan="+new_tag+"&interface="+encodeURIComponent(interface)+"&node="+encodeURIComponent(node));
				      ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
				      ds.responseSchema = {
					  resultsList: "results",
					  fields: [{key: "available", parser: "number"}],
					  metaFields: {
					      "error": "error"
					  }
				      };
				      
				      add_tag_button.set("label", "Validating...");
				      add_tag_button.set("disabled", true);

				      ds.sendRequest("", {success: function(req, resp){
						           add_tag_button.set("label", "Add Tag");
							   add_tag_button.set("disabled", false);

						           if (resp.meta.error){
							       alert("Error - " + resp.meta.error);
							       return;
							   }
							   else if (resp.results[0].available == 1){
							       endpoint_table.addRow({interface: interface,
								                      node: node,
								                      tag: new_tag});
						
							       save_session();
							       
							       nddi_map.table.unselectAllRows();
							       nddi_map.table.vlan_panel.destroy();
							       nddi_map.table.vlan_panel = undefined;	       
							   }
							   else{
							       if (new_tag == -1){
								   alert("Untagged traffic is currently in use by another circuit on interface " + interface + " on endpoint " + node + ".");
							       }
							       else {
								   alert("Tag " + new_tag + " is not currently available on interface " + interface + " on endpoint " + node + ".");
							       }
							   }
						 
					               },
 						       failure: function(reqp, resp){
						           add_tag_button.set("label", "Add Tag");
							   add_tag_button.set("disabled", false);

						           alert("Error validating endpoint.");
					               }
					  });
				    				    
				  }
				  
				  add_tag_button.on("click", verify_and_add_vlan_tag);
  
				  new YAHOO.util.KeyListener(vlan_input,
							     {keys: 13},
							     {fn: verify_and_add_vlan_tag}).enable();
				  

				});
		
		
	      });
  
  function save_session(){
    
    var records = endpoint_table.getRecordSet().getRecords();
    
    session.data.endpoints = [];
    
    for (var i = 0; i < records.length; i++){
      
      var node      = records[i].getData('node');
      var interface = records[i].getData('interface');
        var description = records[i].getData('interface_description');
        var tag       = records[i].getData('tag');
      
      session.data.endpoints.push({interface: interface,
				   node: node,
                   interface_description: description,
				   tag: tag,
				  });
    }
    
    session.save();
    
    nddi_map.updateMapFromSession(session);

  }

  function verify_inputs(){

    var records = endpoint_table.getRecordSet().getRecords();
    
    if (records.length < 2){
      alert("You must have at least two endpoints.");
      return false;
    }       
    
    save_session();

    return true;
  }
  
}

YAHOO.util.Event.onDOMReady(init);
  
</script>