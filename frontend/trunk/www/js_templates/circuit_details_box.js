<script>
  
function summary_init(remove_only){
  
  var bandwidth = session.data.bandwidth || 0;
  
  if (bandwidth < 1000000000){
    bandwidth = (bandwidth / 1000000) + " Mbps";
  }
  else{
    bandwidth = (bandwidth / 1000000000) + " Gbps";
  }
  
  YAHOO.util.Dom.get('summary_bandwidth').innerHTML         = bandwidth;
  YAHOO.util.Dom.get('summary_description').innerHTML       = session.data.description;
  YAHOO.util.Dom.get('summary_status').innerHTML            = session.data.state || "Planning";
  YAHOO.util.Dom.get('summary_type').innerHTML              = session.data.interdomain == 1 ? "Interdomain" : "Local";

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

  [% total_width = 550 %]

  

  [% IF delete %]

    [% interface_width = 195 %]

  [% END %]

  var cols = [
      {key: "interface", label: "Interface", formatter: function(el, rec, col, data){
          el.innerHTML = rec.getData('node') + ' - ' + rec.getData('interface');
      }
     
      },
      {key:"description", label: "Interface Description" , formatter: function(el,rec,col,data){
          el.innerHTML = rec.getData('interface_description');
          //console.log(data);
          console.log(rec);
      }
  },
    {key: "tag", label: "VLAN", formatter: function(el, rec, col, data){
	    if (data == -1){
		    el.innerHTML = "<span style='font-size: 74%;'>Untagged</span>";
	    }
	    else {
		    el.innerHTML = data;
	    }
	}
    }    

    [% IF delete %]

    , {
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
    }

    [% END %]

  ];
  
  var configs = {
      height: '130px',
      width: '[% total_width %]px'
  };
  
  var endpoint_table = new YAHOO.widget.ScrollingDataTable("circuit_endpoints_table", cols, ds, configs);
 
  var endpoints = session.data.endpoints || [];
    console.log(endpoints);
  for (var i = 0; i < endpoints.length; i++){
      endpoint_table.addRow({interface: endpoints[i].interface, interface_description: endpoints[i].interface_description, node: endpoints[i].node, tag: endpoints[i].tag, urn: endpoints[i].urn});    
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

  makeHelpPanel(["summary_bandwidth", "summary_bandwidth_label"], "This is the amount of bandwidth this circuit has reserved across the network.");

  makeHelpPanel(["summary_type", "summary_type_label"], "This indicates whether the circuit is simply intradomain (Local), or interdomain.");

  makeHelpPanel(["summary_status", "summary_status_label"], "This indicates the present status of the circuit.");

  return endpoint_table;
}
  
</script>