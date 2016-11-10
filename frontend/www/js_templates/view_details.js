[% INCLUDE js_templates/graph.js %]

<script>

function init(){

    var tabs = new YAHOO.widget.TabView("tabs");

    var ds = make_circuit_details_datasource();

    ds.sendRequest("", {
        success: function(req, resp){
            var details = resp.results[0];
            save_session_from_datasource(details);

            page_init();
        },
        failure: function(req, resp){
            alert("Error loading circuit details.");
        }

    });

}

function make_circuit_details_datasource(){
    var ds = new YAHOO.util.DataSource("services/data.cgi?method=get_circuit_details&circuit_id="+session.data.circuit_id);
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [
    {key: "circuit_id", parser: "number"},
    {key: "workgroup"},
    {key: "description"},
    {key: "bandwidth", parser: "number"},
    {key: "links"},
    {key: "backup_links"},
    {key: "endpoints"},
    {key: "state"},
    {key: "active_path"},
    {key: "restore_to_primary"},
    {key: "loop_node"},
    {key: "type"},
    {key: "static_mac"} //TODO change to perma-name
	]
    };

    return ds;
}

function save_session_from_datasource(details){
    session.clear();
    session.data.circuit_id   = details.circuit_id;
    session.data.description  = details.description;
    session.data.bandwidth    = details.bandwidth * 1000000;
    session.data.state        = details.state;
    session.data.circuit_type = details.type;
    session.data.active_path  = details.active_path;
    session.data.circuit_workgroup = details.workgroup;
    session.data.static_mac_routing = parseInt(details.static_mac);
    session.data.interdomain  = 0;
    session.data.endpoints    = [];
    session.data.links        = [];
    session.data.backup_links = [];
    session.data.restore_to_primary = details.restore_to_primary;
    session.data.loop_node = details.loop_node;

    for (var i = 0; i < details.endpoints.length; i++){
        var endpoint = details.endpoints[i];
        var endpoint_data = {
            node: endpoint.node,
            node_id: endpoint.node_id,
            interface: endpoint.interface,
            interface_description: endpoint.interface_description,
            tag: endpoint.tag,
            role: endpoint.role,
            urn: endpoint.urn,
            local: endpoint.local,
            mac_addrs: endpoint.mac_addrs,
            vlan_tag_range: endpoint.vlan_tag_range
        };

        if (endpoint.local == 0){
            session.data.interdomain = 1;
        }

        session.data.endpoints.push(endpoint_data);
    }


    for (var i = 0; i < details.links.length; i++){
        var path_component = details.links[i];
        session.data.links.push(path_component.name);
    }

    for (var i = 0; i < details.backup_links.length; i++){
        var path_component = details.backup_links[i];
        session.data.backup_links.push(path_component.name);
    }

    session.save();
}

function page_init(){ 
    // defined in circuit_details_box.js
  var endpoint_table = summary_init();
  var nddi_map = new NDDIMap("map", session.data.interdomain == 1);

  //legend_init(nddi_map, false, true);
  //nddi_map.showDefault();
  nddi_map.on("loaded", function(){
          this.updateMapFromSession(session, session.data.interdomain == 1);

          if (session.data.interdomain == 1){
              this.getInterDomainPath(session.data.circuit_id, YAHOO.util.Dom.get("interdomain_path_status"));
          }

      });

  if((session.data.circuit_workgroup.workgroup_id == session.data.workgroup_id || [% is_admin %] == 1) && [% is_read_only %] == 0){

      if(session.data.backup_links.length > 0){
	  var change_path_button = new YAHOO.widget.Button("change_path_button", {label: "Change Path"});
	  change_path_button.on("click", function(){
		  showConfirm("Doing this may cause a disruption in traffic.  Are you sure?",
			      function(){
				  change_path_button.set("disabled",true);
				  var ds = new YAHOO.util.DataSource("services/provisioning.cgi?method=fail_over_circuit&circuit_id=" + session.data.circuit_id + "&workgroup_id=" + session.data.workgroup_id);
				  ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
				  
				  ds.connTimeout    = 30 * 1000; // 30 seconds
				  
				  ds.responseSchema = {
				      resultsList: "results",
				      fields: [{key: "success", parser: "number"},
				  {key: "circuit_id", parser: "number"},
				  {key: "alt_path_down", parser:"number"}
					       ],
				      metaFields: {
				          error: "error",
				          warning: "warning"
				      }
				  };
				  ds.sendRequest("",{success: function(Request,Response){
					      var data = Response.results;
                                              if(typeof data == 'undefined'){
                                                  alert('An error occured changing the path.');
                                              }else if(typeof data[0] == 'undefined'){
                                                  alert('An error occured changing the path.');
                                              }else if(data[0].success == 0){
						  if(data[0].alt_path_down == 1){
						      alert('The alternate path is down, unable to change to it.');
						  }else{
						      alert('An error occured changing the path.');
						  }
                                              }else{
                        
						  /*
						   *
						   * reload the graph! VV
						   *
						   */
						  var node = session.data.endpoints[0].node;
						  var valid_node = false;
						  if (graph.updating){
						      clearTimeout(graph.updating);
						  }
						  graph.options.node      = node;
						  graph.options.interface = null;
						  graph.options.link      = null;
						  
						  graph.render(); 
					        	 
						  alert('Successfully changed the path.');
                                              }
					      change_path_button.set("disabled",false);					      
					  },
					      failure: function(Request, Response){
					      change_path_button.set("disabled",false);
					      alert('Unable to change to the backup path.');
					  }},ds);
				  
			      },
			      function(){
				  //do nothing
			      });
		  
	      });
      }
      
      
      
      var edit_button = new YAHOO.widget.Button("edit_button", {label: "Edit Circuit"});
      var start_button;
      edit_button.on("click", function(){
	      
	  session.data.interdomain = 0;
	  
	  var endpoints = [];
	  for (var i = 0; i < session.data.endpoints.length; i++){
	      if (session.data.endpoints[i].local == 1){
		  endpoints.push(session.data.endpoints[i]);
	      }
	  }
	  
	  session.data.endpoints = endpoints;
	  session.save();
	  
	  window.location = "?action=edit_details";
	  });
      
      var remove_button = new YAHOO.widget.Button("remove_button", {label: "Remove Circuit"});
      
      remove_button.on("click", function(){
	      
	      window.location = "?action=remove_scheduling";
	  });
      
      
      // show the edit interdomain stuff if we're an interdomain circuit
      if (session.data.interdomain == 1){
	  
	  var edit_interdomain = new YAHOO.widget.Button("edit_interdomain_button", {label: "Edit Interdomain"});
	  
	  edit_interdomain.on("click", function(){
		  window.location = "?action=edit_details";
	      });
	  
      }
      else {
	  YAHOO.util.Dom.get("edit_interdomain_button").parentNode.style.display = "none";
      }
      
      var reprovision_button = new YAHOO.widget.Button("reprovision_button", {label: "Force Reprovision" });
      
      reprovision_button.on("click", function(){
	      showConfirm("Doing this may cause a disruption in traffic.  Are you sure? ", 
			  function(){
			      reprovision_button.set('disabled',true);
			      
			      var circuit_id= session.data.circuit_id;
			      var workgroup_id = session.data.workgroup_id;
			      
			      var ds = new YAHOO.util.DataSource("services/provisioning.cgi?method=reprovision_circuit&circuit_id="+circuit_id+"&workgroup_id="+workgroup_id);
			      ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
			      ds.responseSchema = {
				  resultsList: "results",
				  fields: [
			      {key: "success", parser: "number"},
			      
					   ],
				  metaFields: {
				      error: "error",
				      warning: "warning"
				  }
			      };
			      
			      ds.sendRequest("", { 
				      success: function(req, resp){ 
					  reprovision_button.set('disabled',false);
					  alert("Successfully reprovisioned circuit.");
					  
					  
				      },
					  failure: function(req, resp){
					  reprovision_button.set('disabled',false);
					  alert("Failed to reprovision circuit, please try again later or contact your systems administrator if this continues.");
				      }
				  });
			      
			  },
			  function(){ 
			      //do nothing
			  }
			  );
	  });
      var traceroute_panel;
      var traceroute_button = new YAHOO.widget.Button("traceroute_button", {label: "Trace Circuit Path" });


      traceroute_button.on("click", function(){
          traceroute_button.set('disabled',true);
          var region = YAHOO.util.Dom.getRegion("main_page");
          var xy = [region.left + (region.width/2)-350,
                    region.top+ (region.height/2)-200];
          var p = new YAHOO.widget.Panel("trace_circuit",
                                         {
                                             width: 550,
                                             xy: xy,
                                             modal: true
                                         }
                                        );
          
          p.hideEvent.subscribe(function(){
              traceroute_button.set('disabled',false);
              this.destroy();
          });
          
          p.setHeader("Traceroute");
          p.setBody("<p class='title summary'>Select Starting Endpoint:</p>"+
                    "<div id='traceroute_endpoint_table'></div>"+
                    "<div id='start_traceroute_button'></div>" +
                    "<div style='display:none' id='traceroute_results'><p class='title summary'>Results:</p>"
                    +"<div id='traceroute_results_table'> </div><p class='title summary'>Traceroute Status : <div id='trace_status'></div></p></div>");
          
          traceroute_panel = p;
          traceroute_panel.render(document.body);

          start_button = new YAHOO.widget.Button("start_traceroute_button", {label: "Start Traceroute", disabled: true });
          

          var cols = [
              {key: "interface", width: 250, label: "Interface", formatter: 
               function(el, rec, col, data){
                   el.innerHTML = rec.getData('node') + ' - ' + rec.getData('interface');
               }
               
              },
              {key:"description", width: 150, label: "Interface Description" , formatter: 
               function(el,rec,col,data){
                   el.innerHTML = rec.getData('interface_description');

               }
              },
              {key: "tag", width: 30, label: "VLAN", formatter: function(el, rec, col, data){
                  if (data == -1){
                      el.innerHTML = "<span style='font-size: 74%;'>Untagged</span>";
                  }
                  else {
                      el.innerHTML = data;
                  }
              }
              }
              
          ];
          
          var configs = {
              //height: '130px'
              selectionMode:'single'
          };
          


          var ds = new YAHOO.util.DataSource([]);
          ds.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;

          var endpoints = session.data.endpoints || [];

          var traceroute_table = new YAHOO.widget.ScrollingDataTable("traceroute_endpoint_table",cols,ds,configs);

          traceroute_table.subscribe("rowMouseoverEvent", traceroute_table.onEventHighlightRow);
          traceroute_table.subscribe("rowMouseoutEvent", traceroute_table.onEventUnhighlightRow);
          traceroute_table.subscribe("rowClickEvent", function (e){

              var row = this.getTrEl(e.target);
              var rec = this.getRecord(row);
              if (row && rec){
                  
                  if (this.isSelected(rec)){
                      this.unselectRow(rec);
                      start_button.set("disabled",true);
                  }
                  else {
                      var rows= this.getSelectedRows();
                      for ( var i =0; i < rows.length; i++){
                          var rowrec= this.getRecord(rows[i]);
                          this.unselectRow(rowrec);
                      }
                      this.selectRow(rec);
                      start_button.set("disabled",false);
                  }
             
              }                                              
          }
                                                                  );


          for (var i = 0; i < endpoints.length; i++){
              
              traceroute_table.addRow({
                  interface: endpoints[i].interface, 
                  interface_description: endpoints[i].interface_description, 
                  node: endpoints[i].node, 
                  tag: endpoints[i].tag, 
                  urn: endpoints[i].urn,
                  mac_addrs: endpoints[i].mac_addrs,
                  vlan_tag_range: endpoints[i].vlan_tag_range,
              });    

          }

          start_button.on("click", function(){
              //first get circuit_id, node and interface name.
              start_button.set("disabled",true);
              var circuit_id = session.data.circuit_id;
              var rows = traceroute_table.getSelectedRows();
              var trace_status = YAHOO.util.Dom.get("trace_status");
              YAHOO.util.Dom.setStyle('traceroute_results', 'display', 'block');
              trace_status.innerHTML="";
              if (rows.length < 1){
                  
              }
              else {
                  //code should only allow one row to be selected
                  var rec = traceroute_table.getRecord(rows[0]);

                  var node = encodeURIComponent(rec.getData('node'));
                  var interface = encodeURIComponent(rec.getData('interface'));
                  //submit to traceroute.cgi
                   var ds = new YAHOO.util.DataSource("services/traceroute.cgi?method=init_circuit_traceroute&circuit_id=" + session.data.circuit_id 
                                                      + "&workgroup_id=" + session.data.workgroup_id
                                                      + "&node="+ node + "&interface="+interface
                                                     );
				  ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
				  
				  ds.connTimeout    = 30 * 1000; // 30 seconds
				  
				  ds.responseSchema = {
				      resultsList: "results",
				      fields: [{key: "success", parser: "number"},
	
					       ],
				      metaFields: {
				          error: "error",
				          warning: "warning"
				      }
				  };
				  ds.sendRequest("",{success: function(Request,Response){
                                      
                                      var cols = [{key: "node", label:"Nodes Traversed", 
                                                   width: 150                                                   
                                                   },
                                                  {key: "interface", label:"Interface", 
                                                   width: 100                                                   
                                                  } ];
                                      var configs = {
                                          height: "100px",
                                          MSG_EMPTY: "<img height='32px' width='32px' style='width:32px;height:32px;margin-left:60px;margin-right:auto'src='media/loading.gif'></img> ",
                                          MSG_LOADING: "<img height='32px' width='32px' style='width:32px;height:32px;margin-left:60px;margin-right:auto'src='media/loading.gif'></img> ",
                                          formatRow: function(elTr, oRecord) {  
                                                       if (oRecord.getData("isLast") == 1)
                                                       {
                                                           YAHOO.util.Dom.addClass(elTr, 'spinnerRow');
                                                       }
                                                       return true;
                                                   }
                                      };

                                      var tmp_ds = new YAHOO.util.DataSource([]);
                                      tmp_ds.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
                                      var traceroute= YAHOO.util.Dom.get("traceroute_results_table");

                                      var traceroute_results =  new YAHOO.widget.ScrollingDataTable('traceroute_results_table',cols,tmp_ds,configs);
                                      
                                      //successful request, lets start polling the status of the trace
                                      pollTracerouteStatus(traceroute_results,start_button);
                                  },
                                                     failure: function(req, resp){
                                                         alert("Error starting Traceroute, please try again or if this continues please contact the OESS System Administrator");
                                                     }

                                                    } );
      
              }
          });
      });

      var loop_circuit_button;

        if (session.data.state == "looped") {
            loop_circuit_button = new YAHOO.widget.Button("loop_circuit_button", {label: "Remove Loop" });
        }
        else {
            loop_circuit_button = new YAHOO.widget.Button("loop_circuit_button", {label: "Loop Circuit" });
        }

      loop_circuit_button.on("click", function(){

              if (session.data.state == "looped") {
                alert("Removing Loop from Circuit.");
                var description = session.data.description;
                var bandwidth   = parseInt(session.data.bandwidth / (1000 * 1000));
                var provision_time = session.data.provision_time;
                var remove_time    = session.data.remove_time;
                var restore_to_primary = session.data.restore_to_primary;
                // get the times from milli into seconds
                if (provision_time != -1){
                    provision_time = parseInt(provision_time / 1000);
                }   

                if (remove_time != -1){
                    remove_time = parseInt(remove_time / 1000);
                }   
            
                var endpoints          = session.data.endpoints;
                var links              = session.data.links;
                var backups            = session.data.backup_links;
                var static_mac = session.data.static_mac_routing;
                var workgroup_id = session.data.workgroup_id;
                var circuit_id = session.data.circuit_id;
                var node_id = null;
                var state = 'active';
                var postVars = "method=provision_circuit&circuit_id="+encodeURIComponent(circuit_id)
                       +"&description="+encodeURIComponent(description)
                       +"&bandwidth="+encodeURIComponent(bandwidth)
                       +"&provision_time="+encodeURIComponent(provision_time)
                       +"&remove_time="+encodeURIComponent(remove_time)
                       +"&workgroup_id="+workgroup_id
                       +"&restore_to_primary="+restore_to_primary
                       +"&static_mac="+static_mac
                       +"&loop_node="+node_id
                       +"&state=" +state; 

                for (var i = 0; i < endpoints.length; i++){
                    postVars += "&node=" + encodeURIComponent(endpoints[i].node);
                    postVars += "&interface=" + encodeURIComponent(endpoints[i].interface);
                    postVars += "&tag=" + encodeURIComponent(endpoints[i].tag);
                    postVars += "&endpoint_mac_address_num=" +  encodeURIComponent(endpoints[i].mac_addrs.length);

                    var mac_addresses = endpoints[i].mac_addrs;
                    for(var j = 0; j < mac_addresses.length; j++){
                        postVars += "&mac_address=" + encodeURIComponent(mac_addresses[j].mac_address);
                    }
                }

            for (var i = 0; i < links.length; i++){
                postVars += "&link="+encodeURIComponent(links[i]);
            }

            for (var i = 0; i < backups.length; i++){
                postVars += "&backup_link="+encodeURIComponent(backups[i]);
            }

            var ds = new YAHOO.util.DataSource("services/provisioning.cgi");
            ds.connMethodPost = true;
            ds.connTimeout    = 30 * 1000; // 30 seconds
            ds.responseType   = YAHOO.util.DataSource.TYPE_JSON;
            ds.responseSchema = {
            resultsList: "results",
            fields: [{key: "success", parser: "number"},
                         {key: "circuit_id", parser: "number"}
                 ],
            metaFields: {
                error: "error",
                warning: "warning"
            }
            };

            ds.sendRequest(postVars,{success: handleLocalSuccess, failure: handleLocalFailure, scope: this});

              }
              else {
                window.location = "?action=loop_circuit";
                }

        });
  }
  else{

  }  

  var tabs = new YAHOO.widget.TabView("details_tabs");

  var graph = setupMeasurementGraph();

  nddi_map.on("clickNode", function(e, args){

		var node = args[0].name;
		var valid_node = false;
		// make sure this node is part of the circuit
		for (var i = 0; i < session.data.endpoints.length; i++){
		  if (session.data.endpoints[i].node == node){
       
            valid_node = true;
		  }
		}

		// if they clicked on some random node not part of the circuit just ignore it
		  //if (! valid_node) return;

		if (graph.updating){
		  clearTimeout(graph.updating);
		}

		graph.options.node      = node;
		graph.options.interface = null;
		graph.options.link      = null;

		graph.render();
	      });

  nddi_map.on("clickLink", function(e, args){
		var links = args[0].links;
                var link = args[0].name;
                if (links && links.length > 0){
                    var link_id = args[0].link_id;
                    for (i=0; i< links.length; i++){
                        if (links[i].link_id=link_id){
                            link = links[i].link_name;
                            break;
                        }
                    }
                }
		if (graph.updating){
		  clearTimeout(graph.updating);
		}

		graph.options.link      = link;
		graph.options.interface = null;
		graph.options.node      = null;

		graph.render();
	      });

  setupScheduledEvents();

  setupHistory();
  setupCLR();

  // we can poll the map to show intradomain status updates unless we're interdomain
  
  if (session.data.interdomain == 0){
      setInterval(function(){

	      var ds = make_circuit_details_datasource();
          
        //make sure we didn't upset the user's view.
          var keep_map_position = true;

	      ds.sendRequest("", {success: function(req, resp){
			  var details = resp.results[0];
			  save_session_from_datasource(details);

			  for (var i = 0; i < session.data.endpoints.length; i++){
			      nddi_map.removeNode(session.data.endpoints[i].node);
			  } 

			  nddi_map.updateMapFromSession(session, true, keep_map_position);
              },
			  failure: function(req, resp){

		      }
		  });


	  }, 10000);
  }

}

function pollTracerouteStatus(status_table,start_button){

    var ds = new YAHOO.util.DataSource("services/traceroute.cgi?method=get_circuit_traceroute&circuit_id=" + session.data.circuit_id + "&workgroup_id=" + session.data.workgroup_id); 
                                      ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
				  
				      ds.connTimeout    = 30 * 1000; // 30 seconds
                                      				  ds.responseSchema = {
				      resultsList: "results",
				      fields: [{key: "remaining_endpoints", parser: "number"},
                                               {key: "nodes_traversed"},
                                               {key: "interfaces_traversed"},
                                               {key: "status" }
	
					       ],
				      metaFields: {
				          error: "error",
				          warning: "warning"
				      }
				  };

                                  ds.sendRequest("",
                                                        {

                                                            success: function (req, resp){

                                                                var results = resp.results[0];                                       
                                                                
                                                                //set status
                                                                var trace_status = YAHOO.util.Dom.get("trace_status");
                                                                var help_text = { active:"",
                                                                                  Complete: "Traceroute has reached all endpoints successfully",
                                                                                  invalidated: "A Network event has caused a disruption in the traceroute, please try again.",
                                                                                  "timed out": "The traceroute was unable to complete traversal of the circuit in the time alotted"
                                                                                  }
                                                                trace_status.innerHTML="<p class='"+(results.status.replace(/ /g,'').toLowerCase())+"'>"+
                                                                    results.status+"</p>"+"<p class='helptext'>"+help_text[results.status]+"</p>";
                                                                var nodes_traversed = results.nodes_traversed;
                                                                var interfaces_traversed = results.interfaces_traversed;
                                                                //rebuild results table from nodes_traversed;
                                                                //clear current rows
                                                                
                                                                if (nodes_traversed.length > 0){
                                                                    var nodes_array = [];
                                                                    status_table.deleteRows(0, status_table.getRecordSet().getRecords().length);
                                                                    for (var i=0; i < nodes_traversed.length; i++){
                                                                        nodes_array[i] ={
                                                                          node: nodes_traversed[i],
                                                                          interface: interfaces_traversed[i],
                                                                            isLast:0
                                                                        };
                                                                        if (i == nodes_traversed.length && results.status=="active"){
                                                                            nodes_array[i].isLast=1;
                                                                        }
                                                                    
                                                                    }
                                                                
                                                                    status_table.addRows(nodes_array);
                                                                }
                                                                if (results.status == "active" ){
                                                                    setTimeout(pollTracerouteStatus(status_table,start_button),1000);
                                                                }
                                                                else{ 
                                                                    start_button.set("disabled",false);
                                                                    if (results.nodes_traversed.length ==0){
                                                                        //set MSG_EMPTY to "no nodes traversed";
                                                                        //status_table.configs.MSG_EMPTY= "No Nodes Traversed";
                                                                        //status_table.configs.MSG_LOADING= "No Nodes Traversed";

                                                                    }
                                                                    if (results.status != "Complete"){
                                                                        status_table.addRow({node:"Path Not Found"});
                                                                    }
                                                                };
                                                            }

                                                        }

                                                );


}

function pollTracerouteStatus(status_table){

    var ds = new YAHOO.util.DataSource("services/traceroute.cgi?action=get_circuit_traceroute&circuit_id=" + session.data.circuit_id + "&workgroup_id=" + session.data.workgroup_id); 
                                      ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
				  
				      ds.connTimeout    = 30 * 1000; // 30 seconds
                                      				  ds.responseSchema = {
				      resultsList: "results",
				      fields: [{key: "remaining_endpoints", parser: "number"},
                                               {key: "nodes_traversed"},
                                               {key: "interfaces_traversed"},
                                               {key: "status" }
	
					       ],
				      metaFields: {
				          error: "error",
				          warning: "warning"
				      }
				  };

                                  ds.sendRequest("",
                                                        {

                                                            success: function (req, resp){

                                                                var results = resp.results[0];                                       
                                                                
                                                                //set status
                                                                var trace_status = YAHOO.util.Dom.get("trace_status");
                                                                trace_status.innerHTML=results.status;
                                                                var nodes_traversed = results.nodes_traversed;
                                                                var interfaces_traversed = results.interfaces_traversed;
                                                                //rebuild results table from nodes_traversed;
                                                                //clear current rows
                                                                
                                                                //status_table.deleteRows(0,status_table.getRows.length);
                                                                var nodes_array = [];
                                                                status_table.deleteRows(0, status_table.getRecordSet().getRecords().length);
                                                                for (var i=0; i < nodes_traversed.length; i++){
                                                                    
                                                                    
                                                                    nodes_array[i] ={
                                                                        node: nodes_traversed[i],
                                                                        interface: interfaces_traversed[i]
                                                                    };
                                                                    
                                                                }
                                                                
                                                                status_table.addRows(nodes_array);
                                                                
                                                                if (results.status == "active" ){
                                                                    setTimeout(pollTracerouteStatus(status_table),1000);
                                                                }
                                                            }

                                                        }

                                                );


}

function setupMeasurementGraph(){

    var date = new Date();

    var now  = date.valueOf() / 1000;

    var then = now - 600;

    var graph = new MeasurementGraph("traffic_graph",
				     "traffic_legend",
				     {
					 title:      session.data.description,
					 title_div:    YAHOO.util.Dom.get("traffic_title"),
					 circuit_id: session.data.circuit_id,
                                         timeframe:  600,
                                         start:      then,
					 end:        now
				     }
				     );

    var time_select = new YAHOO.util.Element(YAHOO.util.Dom.get("traffic_time"));
    time_select.on("change", function(){
	    var new_start = this.get('element').options[this.get('element').selectedIndex].value;
            graph.options.timeframe = new_start;
            var date = new Date();
            graph.options.end   = date.valueOf() / 1000;
	    graph.options.start = graph.options.end - new_start;
	    graph.render();
	});

    return graph;
}

function setupScheduledEvents(){


    var ds = new YAHOO.util.DataSource("services/data.cgi?method=get_circuit_scheduled_events&circuit_id="+session.data.circuit_id);
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;

    ds.responseSchema = {
	resultsList: "results",
	fields: [
    {key: "username"},
    {key: "scheduled"},
    {key: "activated"},
    {key: "action"},
    {key: "layout"},
    {key: "completed"}
		 ]
    };

    var cols = [{key: "username", label: "By", width: 101},
		{key: "scheduled", label: "Scheduled", width: 122},
		{key: "action", label: "Action", width: 100, formatter: function(elLiner,oRec,oCol,oData){
			var txt = oRec.getData('layout');
			//browsers that don't suck
			if(window.DOMParser){
			    parser = new DOMParser();
			    xmlDoc = parser.parseFromString(txt,"text/xml");
			    
			}
			//IE
			else{
			    xmlDoc=new ActiveXObject("Microsoft.XMLDOM");
			    xmlDoc.async=false;
			    xmlDoc.loadXML(txt);
			}

			var opt = xmlDoc.childNodes[0];
			elLiner.innerHTML = opt.attributes.action.value;
		    }},
		{key: "activated", label: "Activated", width: 121},
		{label: "Completed", formatter: function(el, rec, col, data){
			if (rec.getData('completed')){
			    el.innerHTML = "Yes";
			}
			else {
			    el.innerHTML = "No";
			}
		    }
		}
		];

    var config = {
	height: "255px"
    };

    var table = new YAHOO.widget.ScrollingDataTable("scheduled_events_table", cols, ds, config);

    table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
    table.subscribe("rowMouseoutEvent", table.onEventUnhighlightRow);

    table.subscribe("rowClickEvent", function(oArgs){
	    var record = this.getRecord(oArgs.target);
	    if (! record) return;
	    var region = YAHOO.util.Dom.getRegion(oArgs.target);
	    showActionPanel(record, [region.left, region.top]);
	});

    return table;
}

function setupCLR(){
    var ds = new YAHOO.util.DataSource("services/data.cgi?method=generate_clr&circuit_id=" + session.data.circuit_id);
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "clr"}]
    };

    ds.sendRequest('',{success: function(Req,Resp){
		var data = Resp.results;
		if(data.length == 1){
		    YAHOO.util.Dom.get("CLR_table").innerHTML = "<pre>" + data[0].clr;
		}else{
		    YAHOO.util.Dom.get("CLR_table").innerHTML = "Error occured fetching CLR data.  Error: " + data.error;
		}
	    },
		failure: function(Req,Resp){
		//do something
	    }});

    var ds2 = new YAHOO.util.DataSource("services/data.cgi?method=generate_clr&circuit_id=" + session.data.circuit_id + "&raw=1");
    ds2.responseType = YAHOO.util.DataSource.TYPE_JSON;

    ds2.responseSchema = {
	resultsList: "results",
        fields: [{key: "clr"}]
    };

    ds2.sendRequest('',{success: function(Req,Resp){
		var data = Resp.results;
		if(data.length == 1){
                    YAHOO.util.Dom.get("CLR_table_raw").innerHTML = "<pre>" + data[0].clr;
                }else{
                    YAHOO.util.Dom.get("CLR_table_raw").innerHTML = "Error occured fetching CLR data.  Error: " + data.error;
		}
            },
                failure: function(Req,Resp){
                //do something
            }});

}

function setupHistory(){

    var ds = new YAHOO.util.DataSource("services/data.cgi?method=get_circuit_history&circuit_id=" + session.data.circuit_id);
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;

    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "fullname"},
                 {key: "scheduled"},
                 {key: "activated"},
                 {key: "layout"},
    {key: "completed"},
    {key: "reason"}
		 ]
    };

    var cols = [{key: "fullname", label: "By", width: 200},
		{key: "activated", label: "Date/Time", width: 142},
                //		{key: "completed", label: "Done On", width: 141},
		{key: "reason", label: "Event", width: 520}
		];

    var config = {
	height: "300px"
    };

    var table = new YAHOO.widget.ScrollingDataTable("history_table", cols, ds, config);

    table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
    table.subscribe("rowMouseoutEvent", table.onEventUnhighlightRow);

    table.subscribe("rowClickEvent", function(oArgs){
	    var record = this.getRecord(oArgs.target);
	    if (! record) return;
	    var region = YAHOO.util.Dom.getRegion(oArgs.target);
	    showActionPanel(record, [region.left, region.top]);
	});

    return table;

}

function handleLocalSuccess(request, response){

    if (response.meta.error){
    alert("Error - " + response.meta.error);
    return;
    }

    var results = response.results;

    var provision_time = session.data.provision_time;

    if (results && results[0].success == 1){

    if (provision_time == -1){
        session.clear();
        session.data.circuit_id = results[0].circuit_id;
        session.data.state = "active";
        session.save();

        var warning = "";

        if (response.meta && response.meta.warning){
        warning = "Warning: " + response.meta.warning;
        }

        alert("Circuit Loop Removed.<br>" + warning,
          function(){
              window.location = "?action=view_details";
          }
          );
    }
    else{
        alert("Circuit Loop removed.",
          function(){
              window.location = "?action=view_details";
          }
          );
    }
    }
    else {
    alert("Unknown return value in de-looping.");
    }
}

function handleLocalFailure(request, response){
    alert("Error while communicating with server. If this problem continues to exist, please notify your system administrator.");
}


YAHOO.util.Event.onDOMReady(init);

</script>
