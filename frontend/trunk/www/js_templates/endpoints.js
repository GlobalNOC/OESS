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

                    var add_row = function(options){
                        var tag           = options.tag;
                        var mac_addresses = [];
                        if(session.data.static_mac_routing) {
                            mac_addresses = options.get_mac_addresses();
                        }
                        endpoint_table.addRow({
                            interface: interface,
                            interface_description: description,
                            node: node,
                            tag: tag,
                            vlan_tag_range: rec.getData("vlan_tag_range"),
                            mac_addrs: mac_addresses 
                        });

                        save_session();

                        nddi_map.table.unselectAllRows();
                        nddi_map.table.vlan_panel.destroy();
                        nddi_map.table.vlan_panel = undefined; 
                    };

                    var endpoint_limit_ds = new YAHOO.util.DataSource(
                        "services/data.cgi?action=is_within_circuit_endpoint_limit"+
                        "&workgroup_id=" + session.data.workgroup_id+
                        "&endpoint_num=" + ( endpoint_table.getRecordSet().getRecords().length + 1 ) 
                    );


                    endpoint_limit_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                    endpoint_limit_ds.responseSchema = {
                        resultsList: "results",
                        fields: [{key: "within_limit", parser: "number"}],
                        metaFields: {
                          "error": "error"
                        }
                    };

                    endpoint_limit_ds.sendRequest("",{
                        success: function(req,resp){
                            if(parseInt(resp.results[0].within_limit)){
                                add_row(options);
                            }else {
                                alert("You have exceeded this workgroups max endpoints per circuit limit");
                            }
                        },
                        failure: function(req,resp){
                            alert("Problem fetching workgroup max endpoints per circuit limit");
                        }
                    }, this);
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

            this.vlan_panel.show();

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
