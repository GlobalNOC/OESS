<script>
  
function set_summary(circuit_type) {
    let restore = YAHOO.util.Dom.get('restore_to_primary_summary');
    let staticm = YAHOO.util.Dom.get('static_mac_routing_summary');
    let qnq     = YAHOO.util.Dom.get('q_n_q_summary');

    YAHOO.util.Dom.setStyle(restore, 'display', 'none');
    YAHOO.util.Dom.setStyle(staticm, 'display', 'none');
    YAHOO.util.Dom.setStyle(qnq, 'display', 'none');

    if (circuit_type == 'openflow') {
        session.data.restore_to_primary = session.data.restore_to_primary || 0;
        if (session.data.restore_to_primary == 0) {
            YAHOO.util.Dom.get('restore_to_primary').innerHTML = 'Off';
        } else {
            YAHOO.util.Dom.get('restore_to_primary').innerHTML = session.data.restore_to_primary + " minutes";
        }
        YAHOO.util.Dom.setStyle(restore, 'display', 'block');

        session.data.static_mac_routing = session.data.static_mac_routing || 0;
        if (session.data.static_mac_routing == 0) {
            YAHOO.util.Dom.get('static_mac_routing').innerHTML = 'Off';
        } else {
            YAHOO.util.Dom.get('static_mac_routing').innerHTML = 'On';
        }
        YAHOO.util.Dom.setStyle(staticm, 'display', 'block');
        
    } else if (circuit_type == 'mpls') {
        session.data.q_n_q = session.data.q_n_q || 0;
        if (session.data.q_n_q == 1) {
            YAHOO.util.Dom.get('q_n_q').innerHTML = 'Enabled';
        } else {
            YAHOO.util.Dom.get('q_n_q').innerHTML = 'Disabled';
        }
        YAHOO.util.Dom.setStyle(qnq, 'display', 'block');

    } else {
        // No circuit summary info should be displayed
    }

    if (session.data.circuit_type == undefined) {
        YAHOO.util.Dom.get('control_type').innerHTML = 'undefined';
    } else {
        YAHOO.util.Dom.get('control_type').innerHTML = session.data.circuit_type;
    }
}

function summary_init(options){
  options = options || {};
  
  var remove_only = options.remove_only;

  var bandwidth = session.data.bandwidth || 0;
  
  if (bandwidth < 1000000000){
    bandwidth = (bandwidth / 1000000) + " Mbps";
  }
  else{
    bandwidth = (bandwidth / 1000000000) + " Gbps";
  }
  
  // YAHOO.util.Dom.get('summary_bandwidth').innerHTML         = bandwidth;
  YAHOO.util.Dom.get('summary_description').innerHTML       = session.data.description;
  YAHOO.util.Dom.get('summary_status').innerHTML            = session.data.state || "Planning";
  YAHOO.util.Dom.get('summary_type').innerHTML              = session.data.interdomain == 1 ? "Interdomain" : "Local";

  if(session.data.circuit_workgroup != undefined){
      YAHOO.util.Dom.get('workgroup_name').innerHTML        = session.data.circuit_workgroup.name;
  }else{
      YAHOO.util.Dom.get('workgroup_name').innerHTML        = session.data.workgroup_name;
  }

    // Display summary fields based on circuit type
    set_summary(session.data.circuit_type);


    // OpenFlow summary fields
  // if(session.data.restore_to_primary == 0 || session.data.restore_to_primary == undefined){
  //     YAHOO.util.Dom.get('restore_to_primary').innerHTML    = 'Off';
  // }else{
  //     YAHOO.util.Dom.get('restore_to_primary').innerHTML    = session.data.restore_to_primary + " minutes";
  // }
  // if(session.data.static_mac_routing == 0 || session.data.static_mac_routing == undefined){
  //     YAHOO.util.Dom.get('static_mac_routing').innerHTML    = 'Off';
  // }else{
  //     YAHOO.util.Dom.get('static_mac_routing').innerHTML    = 'On';
  // }

  [% IF show_times %]

      [% IF ! remove_only %]
      var start_time = session.data.provision_time;

      if (start_time == -1){
	  start_time = "Now";
      }
      else{
	  var d = new Date(start_time);
	  start_time = d.toUTCString();
      }
      
      YAHOO.util.Dom.get('summary_start_time').innerHTML = start_time;
      [% END %]

      var remove_time = session.data.remove_time;

      if (remove_time == -1){
	  [% IF remove_only %]
	  remove_time = "Now";
	  [% ELSE %]
	  remove_time = "Never";
	  [% END %]
      }
      else{
	  var d = new Date(remove_time);
	  remove_time = d.toUTCString();
      }

      YAHOO.util.Dom.get('summary_remove_time').innerHTML = remove_time;
    
  [% END %]
    
  var ds = new YAHOO.util.DataSource([]);
  ds.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;

  [% total_width = 495 %]

  

  [% IF delete %]

    [% interface_width = 195 %]
    [% total_width = 563 %]
  [% END %]
    var hide_static_mac = true;
    if(session.data.static_mac_routing){
        hide_static_mac = false;
    }

    //determine whether we should use a delete or edit action
    var edit_column = {
        label: "Edit", width: 48, formatter: function(el, rec, col, data){
            var button = new YAHOO.widget.Button({label: "Edit"});
            YAHOO.util.Dom.addClass(button, "endpoint_edit_button");
            var t = this;
            var fetching_input = false;
            
            button.on("click", function(){
                button.set('disabled',true);
                var create_panel = function(){
                    var region = YAHOO.util.Dom.getRegion(el);
                    var components = makeTagSelectPanel([region.right, region.bottom], {
                        include_static_mac_table: true,
                        align_right: true,
                        panel_width: 393,
                        save_action: function(options){

                            if(session.data.static_mac_routing){
                                t.updateCell( rec , "tag" , options.tag , true);
                                t.updateCell( rec , "mac_addrs" , (options.get_mac_addresses() || []) );
                            }else {
                                t.updateCell( rec , "tag" , options.tag );
                            }
                        },
                        remove_action: function(options){
                            var interface = rec.getData('interface');
                            showConfirm("Are you sure you wish to delete interface " + interface + "?",
                                    function(){
                                    t.deleteRow(t.getRecordSet().getRecordIndex(rec));
                                    },
                                    function(){}
                                    );

                        },
                        interface: rec.getData("interface"),
                        interface_description: rec.getData("interface_description"),
                        node: rec.getData("node"),
                        tag_range: rec.vlan_tag_range,
                        workgroup_id: session.data.workgroup_id,
                        is_edit: true,
                        current_values: {
                            mac_addresses: rec.getData("mac_addrs"),
                            tag: rec.getData("tag")
                        }
                    });
                    var vlan_panel = components.panel;
                    vlan_panel.show();
                    button.set('disabled',false);
                };

                if(!rec.vlan_tag_range){ 
                    var tag_ds = new YAHOO.util.DataSource(
                        "services/data.cgi?method=get_vlan_tag_range"+
                        "&interface="+encodeURIComponent(rec.getData('interface'))+
                        "&node="+encodeURIComponent(rec.getData('node'))+
                        "&workgroup_id="+session.data.workgroup_id
                    );
                    tag_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                    tag_ds.responseSchema = {
                        resultsList: "results",
                        fields: [{key: "vlan_tag_range"}],
                        metaFields: {
                          "error": "error"
                        }
                    };

                    tag_ds.sendRequest("", {
                    success: function(req, resp){
                        if (resp.results[0].vlan_tag_range){
                            fetching_input = false;
                            rec.vlan_tag_range = resp.results[0].vlan_tag_range;
                            create_panel();
                        }
                        else if(resp.results[0].vlan_tag_range === null){
                            rec.vlan_tag_range = "None Available"; 
                            create_panel();
                        } 
                        else{
                            alert("Problem fetching vlan tag range.");
                        }
                    },
                    failure: function(req, resp){
                        alert("Problem fetching vlan tag range.");
                    }});
                } else {
                    create_panel();
                }
            });//--end on click
            button.appendTo(el);
        }
    };
    var delete_column = {
        label: "Delete", width: 48, formatter: function(el, rec, col, data){
        var del_button = new YAHOO.widget.Button({label: "Delete"});
        YAHOO.util.Dom.addClass(del_button, "endpoint_delete_button");
        var t = this;
        del_button.on("click", function(){
            var interface = rec.getData('interface');

            showConfirm("Are you sure you wish to delete interface " + interface + "?",
                function(){
                t.deleteRow(t.getRecordSet().getRecordIndex(rec));
                },
                function(){}
            );

         });
        del_button.appendTo(el);
        }
    };
    var action_column = edit_column;
    if(options.interdomain){
        action_column = delete_column;
    }


    var cols = [
        {key: "interface", width: 250, label: "Interface", formatter: 
        function(el, rec, col, data){
           el.innerHTML = rec.getData('node') + ' - ' + rec.getData('interface');
        }

        },
        {key:"description", width: 150, label: "Interface Description" , formatter: 
        function(el,rec,col,data){
           el.innerHTML = rec.getData('interface_description');
           //console.log(data);
           //console.log(rec);
        }
        },
        {key: "tag", width: 30, label: "VLAN", formatter: function(el, rec, col, data){
          if (data == -1){
              el.innerHTML = "<span style='font-size: 74%;'>Untagged</span>";
          }
          else {
              el.innerHTML = data;
          }
        }},
        {key: "mac_addrs", label: "Static MAC Addresses", hidden: hide_static_mac, formatter: function(el, rec, col, data){
          if (!data){
              el.innerHTML = "None";
          }
          else {
              var text = "";
              for(var i=0; i<data.length;i++){
                text += data[i].mac_address+"<br>";
              }
              el.innerHTML = text;
          }
        }}
        [% IF delete %]
        ,action_column
        [% END %]
    ];
  
    var configs = {
      height: '130px',
      //width: '[% total_width %]px'
    };
  
 

  var endpoint_table = new YAHOO.widget.ScrollingDataTable("circuit_endpoints_table", cols, ds, configs);
  /* endpoint_table.on('initEvent', function(){
        console.log("checking size");
        
        var table_div = YAHOO.util.Element("circuit_endpoints_table");
        
                }
    });*/

    var endpoints = session.data.endpoints || [];
    //console.log(endpoints);
    for (var i = 0; i < endpoints.length; i++){
        endpoint_table.addRow({
            interface: endpoints[i].interface, 
            interface_description: endpoints[i].interface_description, 
            node: endpoints[i].node, 
            tag: endpoints[i].tag, 
            urn: endpoints[i].urn,
            mac_addrs: endpoints[i].mac_addrs,
            vlan_tag_range: endpoints[i].vlan_tag_range,
        });    
    }

  // set up all the help hover widgets
  makeHelpPanel(["summary_description", "summary_description_label"], "This is the human readable description for this circuit.");

  makeHelpPanel(["circuit_endpoints_table", "circuit_endpoints_table_label"], "These are the endpoints of the circuit in the Openflow network. In addition, this table shows what ports and what VLAN tags are used on the endpoint.");

  [% IF show_times %]
      [% IF ! remove_only %]
      makeHelpPanel(["summary_start_time", "summary_start_time_label"], "This is when the desired provisioning action will take place. A value of \"Now\" means that it will take place as soon as the submission is made.");
      [% END %]
      makeHelpPanel(["summary_remove_time", "summary_remove_time_label"], "This is when the current circuit will be removed. A value of \"Never\" simply means that there is no predefined time for automatic removal. It may still be removed manually at a later date.");
  [% END %]

  // makeHelpPanel(["summary_bandwidth", "summary_bandwidth_label"], "This is the amount of bandwidth this circuit has reserved across the network.");

  makeHelpPanel(["summary_type", "summary_type_label"], "This indicates whether the circuit is simply intradomain (Local), or interdomain.");

  makeHelpPanel(["summary_status", "summary_status_label"], "This indicates the present status of the circuit.");

  makeHelpPanel(["restore_to_primary", "restore_to_primary_label"], "This indicates if restore to primary is configured and the number of minutes until the primary is restored");
  
  makeHelpPanel(["static_mac_routing", "static_mac_routing_label"], "This indicates if the nodes will forward traffic based on the static MAC addresses configured on each endpoint.");

  return endpoint_table;
}
  
</script>
