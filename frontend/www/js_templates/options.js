<script type='text/javascript' src='js_utilities/multilink_panel.js'></script>
<script type='text/javascript' src='js_utilities/path_utils.js'></script>
<script>

function makePathTable(){
  
  var ds = new YAHOO.util.DataSource([]);
  ds.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
  
  var cols = [{key: "link", label: "Primary Path", width: 200}
	     ];
  
  var configs = {
    height: "337px"
  };
  
  var table = new YAHOO.widget.ScrollingDataTable("path_table", cols, ds, configs);
  
  var links = session.data.links || [];
  
  for (var i = 0; i < links.length; i++){
    table.addRow({link: links[i]});
  }
  
  return table;
}  
  
function init(){  
    setPageSummary("Path","Choose a primary path from the map below by clicking on links between nodes.");
    setNextButton("Proceed to Step 4: Primary Path", "?action=primary_path", verify_inputs);


    // Load default session variables if they're not already set
    session.data.static_mac_routing = session.data.static_mac_routing || 0;
    session.data.q_n_q = session.data.q_n_q || 0;


    // Circuit Endpoint Table: circuit_details_box.js
    // By default the static mac column is hidden.
    var endpoint_table = summary_init();
    endpoint_table.hideColumn('mac_addrs');


    // OpenFlow Circuit Options
    const restore_to_primary = new YAHOO.widget.Button('restore_to_primary_button', {
        type:  'button',
        label: 'Disabled'
    });
    restore_to_primary.on('click', function() {
        if (this.get('label') == 'Enabled') {
            document.getElementById('restore_to_primary_holder').style.display = 'none';
            document.getElementById('restore_to_primary').value = 0;
            this.set('label', 'Disabled');
        } else{
            document.getElementById('restore_to_primary_holder').style.display = 'inline';
            this.set('label', 'Enabled');
        }
    });
    
    const static_mac = new YAHOO.widget.Button('static_mac_routing_button', { 
        type:  'button',
        label: 'Disabled'
    });
    static_mac.on('click', function() {
        if (this.get('label') == 'Enabled') {
            this.set('label', 'Disabled');
            session.data.static_mac_routing = 0;
            endpoint_table.hideColumn('mac_addrs');
        } else {
            this.set('label', 'Enabled');
            session.data.static_mac_routing = 1;
            endpoint_table.showColumn('mac_addrs');
        }
    });

    YAHOO.util.Dom.get('restore_to_primary').value = session.data.restore_to_primary || 0;
    if(YAHOO.util.Dom.get('restore_to_primary').value > 0){
        restore_to_primary.set('label', 'Enabled');
        document.getElementById("restore_to_primary_holder").style.display = "inline";
    }
    
    YAHOO.util.Dom.get('static_mac_routing_button').value = session.data.static_mac_routing || 0;
    if(YAHOO.util.Dom.get('static_mac_routing_button').value > 0){
        static_mac.set('label', 'Enabled');
        endpoint_table.showColumn('mac_addrs');
    }


    // MPLS Circuit Options
    const q_n_q = new YAHOO.widget.Button('q_n_q_button', { 
        type:  'button',
        label: (session.data.q_n_q > 0) ? 'Enabled' : 'Disabled'
    });
    q_n_q.on('click', function() {
        if (session.data.q_n_q > 0) {
            session.data.q_n_q = 0;
            this.set('label', 'Disabled');
        } else {
            session.data.q_n_q = 1;
            this.set('label', 'Enabled');
        }
    });

    // Display OpenFlow or MPLS Options based on selected circuit type
    if (session.data.circuit_type == 'openflow') {
        document.getElementById('openflow_circuit_options').style.display = 'table-row';
        document.getElementById('mpls_circuit_options').style.display = 'none';
    } else if (session.data.circuit_type == 'mpls') {
        document.getElementById('openflow_circuit_options').style.display = 'none';
        document.getElementById('mpls_circuit_options').style.display = 'table-row';
    } else {
        console.log('Unexpected circuit type was set.');
    }


    var nddi_map = new NDDIMap("map");
    var layout = makePageLayout(nddi_map, {map_width: 700,
                                           max_resize: 700});  
    legend_init(nddi_map);

    nddi_map.on("loaded", function() {
        this.updateMapFromSession(session);
    });

    function save_session() {
        session.save();
        console.log("Session updated");
    }

    function verify_inputs() {
        // OpenFlow Options
        let restore_to_primary_value = document.getElementById('restore_to_primary_text').value;
        if (restore_to_primary_value == '') {
            restore_to_primary_value = 0;
        } else {
            restore_to_primary_value = parseInt(restore_to_primary_value);
        }
        session.data.restore_to_primary = restore_to_primary_value;

        var records = endpoint_table.getRecordSet().getRecords();
        session.data.endpoints = [];

        for (var i = 0; i < records.length; i++) {
            var mac_addrs = null;
            if (static_mac.get('label') == 'Enabled'){
                mac_addrs = records[i].getData('mac_addrs');
                session.data.static_mac_routing = 1;
            } else {
                mac_addrs = [];
                session.data.static_mac_routing = 0;
            }

            session.data.endpoints.push({
                interface: records[i].getData('interface'),
                node: records[i].getData('node'),
                interface_description: records[i].getData('interface_description'),
                tag: records[i].getData('tag'),
                mac_addrs: mac_addrs,
                vlan_tag_range: records[i].getData('vlan_tag_range')
            });
        }

        save_session();
        return true;
    }
}

YAHOO.util.Event.onDOMReady(init);
  
</script>
