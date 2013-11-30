<script>
  
function makeInterfacesTable(node){

    var node_name_holder = document.getElementById('node_name_holder');
    node_name_holder.innerHTML = "<center><h2><b>" + node + "</b></h2></center>";
  
  var ds = new YAHOO.util.DataSource("services/data.cgi?action=get_node_interfaces&node="+encodeURIComponent(node)+"&workgroup_id="+session.data.workgroup_id + "&show_down=1");
  ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
  ds.responseSchema = {
    resultsList: "results",
    fields: [
        {key: "name"},
        {key: "description"},
        {key: "status"},
        {key: "vlan_tag_range"}
    ],
    metaFields: {
      error: "error"
    }
  };
  
  var cols = [
    {key: "name", label: "Interface"},
	{key: "description", label: "Description", width: 120},
    {key: "status", label: "Status"},
    {key: "vlan_tag_range", label: "VLAN Tag Range", formatter: function(elLiner, oRec, oCol, oData){
        var string = oData.replace(/^-1/, "untagged");
        elLiner.innerHTML = string;
    }}
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

  var layout = makePageLayout(nddi_map, {map_width: 540,
					 max_resize: 700});

  
  legend_init(nddi_map, true);
    
  //nddi_map.showDefault();
  
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
            var tag_range = rec.getData('vlan_tag_range');
            var interface = rec.getData('name');
            var description = rec.getData('description');

            var state = rec.getData('status');
            if(state == 'down'){
              alert('Creating a circuit on a link down interface may prevent your circuit from functioning');
            }

            var region = YAHOO.util.Dom.getRegion(args.target);

            var components = makeTagSelectPanel([region.left, region.bottom], {
                include_static_mac_table: true,
                panel_width: 393,
                save_action: function(options){
                    var mac_addresses = options.get_mac_addresses();
                    var tag           = options.tag;
                    endpoint_table.addRow({
                        interface: interface,
                        interface_description: description,
                        node: node,
                        tag: tag,
                        vlan_tag_range: rec.getData("vlan_tag_range"),
                        mac_addrs: mac_addresses //components.get_mac_addresses()
                    });

                    save_session();

                    nddi_map.table.unselectAllRows();
                    nddi_map.table.vlan_panel.destroy();
                    nddi_map.table.vlan_panel = undefined; 
                },
                interface: interface,
                interface_description: description,
                node: node,
                workgroup_id: session.data.workgroup_id,
                tag_range: tag_range
            });

            var vlan_input = YAHOO.util.Dom.get('new_vlan_tag');


            this.vlan_panel      = components.panel;
            var tagged           = components.tagged_input;
            var static_mac_table = components.static_mac_table;

            //var add_tag_button = components.add_button;
            //var save_button = components.save_button;
            //var tag_range_holder = YAHOO.util.Dom.get('new_vlan_tag_range');
            //tag_range_holder.innerHTML = tag_range;

            this.vlan_panel.show();

            /*
            function verify_and_add_endpoint(){
                //--- determine if tag is untagged and validate input
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
                }else {
                    new_tag = -1;
                }
               
                //--- save function 
                var tag_verified = false;
                var mac_limit_verified = false;
                function save(){
                    // only save if both input has been validated
                    if( tag_verified && mac_limit_verified ){
                        save_button.set("label", "Save");
                        save_button.set("disabled", false);

                        endpoint_table.addRow({
                            interface: interface,
                            interface_description: description,
                            node: node,
                            tag: new_tag,
                            mac_addrs: components.get_mac_addresses()
                        });

                        save_session();

                        nddi_map.table.unselectAllRows();
                        nddi_map.table.vlan_panel.destroy();
                        nddi_map.table.vlan_panel = undefined;
                    }
                }

                //--- validate the tag input
                var tag_ds = new YAHOO.util.DataSource(
                    "services/data.cgi?action=is_vlan_tag_available"+
                    "&vlan="+new_tag+
                    "&interface="+encodeURIComponent(interface)+
                    "&node="+encodeURIComponent(node)+
                    "&workgroup_id="+session.data.workgroup_id
                );
                tag_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                tag_ds.responseSchema = {
                    resultsList: "results",
                    fields: [{key: "available", parser: "number"}],
                    metaFields: {
                      "error": "error"
                    }
                };
                
                save_button.set("label", "Validating...");
                save_button.set("disabled", true);
                tag_ds.sendRequest("", {
                success: function(req, resp){
                    if (resp.meta.error){
                        alert("Error - " + resp.meta.error);
                        return;
                    }
                    else if (resp.results[0].available == 1){
                        tag_verified = true;
                        save();
                    }
                    else{
                        if (new_tag == -1){
                            alert("Untagged traffic is currently in use by another circuit on interface " + interface + " on endpoint " + node + ".");
                        }
                        else {
                            alert("Tag " + new_tag + " is not currently available on interface " + interface + " on endpoint " + node + ".");
                        }
                        save_button.set("label", "Save");
                        save_button.set("disabled", false);
                    }

                },
                failure: function(reqp, resp){
                    save_button.set("label", "Save");
                    save_button.set("disabled", false);

                    alert("Error validating endpoint.");
                }});

                //--- verfiy mac addrs don't go over limits
                // build mac address string
                var mac_address_string = "";
                var mac_addresses = components.get_mac_addresses();
                for(var i=0; i< mac_addresses.length; i++){
                    var mac_address = mac_addresses[i].mac_address;
                    mac_address_string += "&mac_address="+mac_address;
                }

                var mac_ds = new YAHOO.util.DataSource(
                    "services/data.cgi?action=is_within_mac_limit"+
                    mac_address_string+
                    "&interface="+encodeURIComponent(interface)+
                    "&node="+encodeURIComponent(node)+
                    "&workgroup_id="+session.data.workgroup_id
                );
                mac_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                mac_ds.responseSchema = {
                    resultsList: "results",
                    fields: [
                        {key: "verified", parser: "number"},
                        {key: "explanation"}
                    ],
                    metaFields: {
                      "error": "error"
                    }
                };

                save_button.set("label", "Validating...");
                save_button.set("disabled", true);
                mac_ds.sendRequest("", {
                success: function(req, resp){
                    if (resp.meta.error){
                        alert("Error - " + resp.meta.error);
                        save_button.set("label", "Save");
                        save_button.set("disabled", false);
                        return;
                    }
                    else if (resp.results[0].verified == 1){
                        mac_limit_verified = true;
                        save();
                    }
                    else{
                        alert( "Problem adding mac addresses: "+resp.results[0].explanation );
                        save_button.set("label", "Save");
                        save_button.set("disabled", false);
                    }
                },
                failure: function(reqp, resp){
                    save_button.set("label", "Save");
                    save_button.set("disabled", false);

                    alert("Error validating endpoint.");
                }});
                                
            } //--- end verify_and_add_endpoint
            */
			
			//save_button.on("click", verify_and_add_endpoint);
  
			new YAHOO.util.KeyListener(vlan_input,
                    {keys: 13},
                    {fn: verify_and_add_endpoint}
            ).enable();

        });
		
		
  });
  
  function save_session(){
    
    var records = endpoint_table.getRecordSet().getRecords();
    
    session.data.endpoints = [];
    
    for (var i = 0; i < records.length; i++){
      
        var node           = records[i].getData('node');
        var interface      = records[i].getData('interface');
        var description    = records[i].getData('interface_description');
        var tag            = records[i].getData('tag');
        var mac_addrs      = records[i].getData('mac_addrs');
        var vlan_tag_range = records[i].getData('vlan_tag_range');

        session.data.endpoints.push({
            interface: interface,
            node: node,
            interface_description: description,
            tag: tag,
            mac_addrs: mac_addrs,
            vlan_tag_range: vlan_tag_range
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
