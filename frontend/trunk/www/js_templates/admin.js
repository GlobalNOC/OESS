<script>
function admin_init(){

    var tabs = new YAHOO.widget.TabView("admin_tabs", {orientation: "left"});

    setup_discovery_tab();

    setup_network_tab();

    setup_users_tab();

    setup_workgroup_tab();

    setup_remote_tab();

    setup_remote_dev_tab();
}

function setup_remote_dev_tab(){
    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=get_remote_devices");
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "node_id", parser: "number"},
                 {key: "name"}, 
                 {key: "network"},
                 {key: "latitude", parser: "number"},
                 {key: "longitude", parser: "number"},    
		 ],
	metaFields: {
	    error: "error"
	}
    };

    var columns = [{key: "network", label: "Network", minWidth: 180, sortable: true},
		   {key: "name", label: "Device", minWidth: 180, sortable: true},
		   {key: "latitude", label: "Lat / Long", minWidth: 120, formatter: function(el, rec, col, data){
			   el.innerHTML = rec.getData("latitude") + " / " + rec.getData("longitude");
		       }
		   },
		    ];

    var config = {
	paginator:  new YAHOO.widget.Paginator({rowsPerPage: 10,
						containers: ["remote_dev_table_nav"]
	    })
    };

    var remote_dev_table = new YAHOO.widget.DataTable("remote_dev_table", columns, ds, config);

    remote_dev_table.subscribe("rowMouseoverEvent", remote_dev_table.onEventHighlightRow);
    remote_dev_table.subscribe("rowMouseoutEvent", remote_dev_table.onEventUnhighlightRow);
    
    remote_dev_table.subscribe("rowClickEvent", function(oArgs){
	    
	    var rec = this.getRecord(oArgs.target);
	    
	    if (! rec) return;
	    
	    this.onEventSelectRow(oArgs);
	    
	    var node_id = rec.getData("node_id");

	    var region = YAHOO.util.Dom.getRegion(oArgs.target);
	    
	    var panel = new YAHOO.widget.Panel("remote_node_p",
						   {width: 360,
						    xy: [region.left, region.bottom],
						    zIndex: 10
						   });

	    panel.setHeader("Enter the Lat/Long Information");
	    panel.setBody("<label for='remote_node_lat' class='soft_title'>Latitude:</label>" +
			  "<input id='remote_node_lat' type='text' size='10' style='margin-left: 15px'>" + 
			  "<label for='remote_node_lon' class='soft_title'>Longitude:</label>" +
			  "<input id='remote_node_lon' type='text' size='10'>"
			  );
	    panel.setFooter("<div id='save_remote_node'></div>");
	    
	    panel.render('remote_dev_content');

	    YAHOO.util.Dom.get("remote_node_lat").value = rec.getData("latitude");
	    YAHOO.util.Dom.get("remote_node_lon").value = rec.getData("longitude");

	    var save_button = new YAHOO.widget.Button("save_remote_node", {label: "Save"});

	    save_button.on("click", function(){
		    
		    var new_lat  = YAHOO.util.Dom.get('remote_node_lat').value;
		    var new_lon  = YAHOO.util.Dom.get('remote_node_lon').value;

		    if (! new_lat || ! new_lat.match(/^\-?\d+(\.\d+)?$/) || new_lat < -90 || new_lat > 90){
			alert("You must specify a valid latitude at which this device will be visualized on the map.");
			return;
		    }
		    
		    if (! new_lon || ! new_lon.match(/^\-?\d+(\.\d+)?$/) || new_lon < -180 || new_lon > 180){
			alert("You must specify a valid longitude at which this device will be visualized on the map.");
			return;
		    }

		    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=update_node&node_id="+node_id+
						       "&name="+ encodeURIComponent(rec.getData("name")) +
						       "&latitude=" + new_lat +
						       "&longitude="+ new_lon
						       );
		    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;

		    ds.responseSchema = {
			resultsList: "results",
			fields: [{key: "success"}]
		    };

		    this.set("disabled", true);
		    this.set("label", "Saving...");

		    YAHOO.util.Dom.get("remote_dev_update_status").innerHTML = "";

		    ds.sendRequest("",
				   {
				       success: function(req, resp){
					   this.set("disabled", false);
					   this.set("label", "Save");

					   if (resp.results && resp.results[0].success == 1){
					       YAHOO.util.Dom.get("remote_dev_update_status").innerHTML = "Remote Device Update Successful.";
					       panel.destroy();
					       remote_dev_table.getDataSource().sendRequest("", {success: remote_dev_table.onDataReturnInitializeTable, scope: remote_dev_table});					       
					   }
					   else{
					       alert("Device update unsuccessful.");
					   }
				       },
				       failure: function(req, resp){
					   this.set("disabled", false);
					   this.set("label", "Save");

					   alert("Error while talking to server.");
				       },
				       scope: this
				   }
				   );

		    
		});
	});

}

function setup_remote_tab(){

    var resubmit_button = new YAHOO.widget.Button("remote_submit_button", {label: "Submit Topology"});

    resubmit_button.on("click", function(){
	    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=submit_topology");
	    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
	    ds.responseSchema = {
		resultsList: "results",
		fields: [{key: "success"}],
		metaFields: {
		    error: "error"
		}
	    };
	    
	    this.set("disabled", true);
	    this.set("label", "Submitting Topology...");
	    
	    ds.sendRequest("",
			   {
			       success: function(req, resp){
				   this.set("disabled", false);
				   this.set("label", "Submit Topology");
				   
				   if (resp.meta.error){
				       alert("Error submitting topology: " + resp.meta.error);
				   }
				   else{
				       alert("Topology has been resubmitted successfully.");
				   }
			       },
			       failure: function(req, resp){
				   this.set("disabled", false);
				   this.set("label", "Submit Topology");

				   alert("Server error while submitting topology.");
			       },
			       scope: this
			   }
			   );

	});

    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=get_remote_links");
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "link_id", parser: "number"},
                 {key: "node"}, 
                 {key: "interface"},
                 {key: "urn"}
		 ],
	metaFields: {
	    error: "error"
	}
    };

    var columns = [{key: "node", label: "Endpoint", minWidth: 120, formatter: function(el, rec, col, data){
		         el.innerHTML = rec.getData("node") + " - " + rec.getData("interface");
	               }
	            },
		    {key: "urn", label: "URN"},
		    {label: "Delete", formatter: function(el, rec, col, data){
			    var b = new YAHOO.widget.Button({label: "Remove"});
			    b.appendTo(el);
			    b.on("click", function(){
				    showConfirm("Are you sure you wish to remove link " + rec.getData("urn") + " from your topology?",
						function(){
						    removeRemoteLink(rec.getData("link_id"), b);
						},
						function(){}
						);
				});
			}
		     
		    }
		    ];

    var config = {
	paginator:  new YAHOO.widget.Paginator({rowsPerPage: 10,
						containers: ["remote_link_table_nav"]
	    })
    };

    var remote_link_table = new YAHOO.widget.DataTable("remote_link_table", columns, ds, config);

    var new_button = new YAHOO.widget.Button("add_new_remote_link", {label: "New Remote Link"});

    new_button.on("click", function(){

	    var region = YAHOO.util.Dom.getRegion('remote_content');
	    
	    var add_remote_p = new YAHOO.widget.Panel("add_remote_link_p",
						   {modal: true,
						    width: 750,
						    height: 435,
						    xy: [region.left, 
							 region.top]
						   });
	    
	    add_remote_p.setHeader("New Remote Link");
	    add_remote_p.setBody("<p class='subtitle'>Select the local endpoint to get started:</p>" + 
				 "<div id='remote_map' class='openlayers smaller' style='float: left;'></div>" + 
				 "<div id='remote_interface_table' style='float: right;'></div>" +
				 "<br clear='both'><br>" +
				 "<center><div id='add_remote_status' class='soft_title confirmation'></div></center>" + 
				 "<div style='text-align: right; font-size: 85%'>" + 
				 "<div id='done_adding_remote'></div>" + 
				 "</div>"
			      );
	    
	    add_remote_p.render('remote_content');
	    
	    var done_adding = new YAHOO.widget.Button("done_adding_remote", {label: "Done Adding Remote Links"});
	    done_adding.on("click", function(){
		    add_remote_p.hide();
		});
	    
	    var map = new NDDIMap('remote_map');
	    
	    map.on("loaded", function(){
		    this.showDefault();
		    this.clearAllSelected();
		});
	    
	    add_remote_p.hideEvent.subscribe(function(){
		    map.destroy();
		    this.destroy();
		});
	    
	    map.on("clickNode", function(e, args){
		    
		    this.clearAllSelected();
		    
		    var feature = args[0].feature;
		    var node    = args[0].name;
		    
		    this.changeNodeImage(feature, this.ACTIVE_IMAGE);

		    var ds = new YAHOO.util.DataSource("../services/data.cgi?action=get_node_interfaces&node="+encodeURIComponent(node));
		    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
		    ds.responseSchema = {
			resultsList: "results",
			fields: [
		    {key: "name"},
		    {key: "description"},
		    {key: "vlan_tag_range"},
		    {key: "interface_id", parser: "number"}
				 ],
			metaFields: {
			    error: "error"
			}
		    };
			    
		    var cols = [{key: "name", label: "Local Interface", width: 220}];
		    
		    var configs = {
			height: "400px"
		    };
		    
		    var table = new YAHOO.widget.ScrollingDataTable("remote_interface_table", cols, ds, configs);
			    
		    table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
		    table.subscribe("rowMouseoutEvent", table.onEventUnhighlightRow);

		    table.subscribe("rowClickEvent", function(oArgs){

			    var rec = this.getRecord(oArgs.target);

			    if (! rec) return;

			    this.onEventSelectRow(oArgs);

			    var interface_id   = rec.getData('interface_id');
			    var interface_name = rec.getData('name');

			    var region = YAHOO.util.Dom.getRegion(oArgs.target);

			    var urn_panel = new YAHOO.widget.Panel("remote_urn_p",
								   {width: 370,
								    xy: [region.left, region.bottom],
								    zIndex: 10
								   });

			    urn_panel.setHeader("Enter the Remote URN for this Link:");
			    urn_panel.setBody("<label for='remote_link_name' class='soft_title'>Name:</label>" +
					      "<input id='remote_link_name' type='text' size='35' style='margin-left: 45px'>" + 
					      "<br><label for='remote_urn' class='soft_title'>Remote URN:</label>" +
					      "<input id='remote_urn' type='text' size='35'>"
					      );
			    urn_panel.setFooter("<div id='save_urn'></div>");

			    urn_panel.render('add_remote_link_p_c');


			    var save_button = new YAHOO.widget.Button("save_urn", {label: "Add"});

			    save_button.on("click", function(){
				    var urn  = YAHOO.util.Dom.get("remote_urn").value;
				    var name = YAHOO.util.Dom.get("remote_link_name").value;

				    if (! urn){
					alert("You must specify a URN for this remote link.");
					return;
				    }
				    
				    if (! name){
					alert("You must specify a name for this link.");
					return;
				    }

				    this.set("disabled", true);
				    this.set("label", "Adding Remote URN...");

				    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=add_remote_link" +
								       "&interface_id=" + interface_id +
								       "&urn=" + encodeURIComponent(urn) + 
								       "&name=" + encodeURIComponent(name)
								       );

				    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
				    ds.responseSchema = {
					resultsList: "results",
					fields: [{key: "success"}],
					metaFields: {
					    error: "error"
					}
				    };

				    YAHOO.util.Dom.get("add_remote_status").innerHTML = "";
				    
				    ds.sendRequest("",
						   {
						       success: function(req, resp){
							   this.set("label", "Add");
							   this.set("disabled", false);	

							   if (resp.meta.error){
							       YAHOO.util.Dom.get("add_remote_status").innerHTML = "Error: " + resp.meta.error;
							   }
							   else {
							       YAHOO.util.Dom.get("add_remote_status").innerHTML = "Remote URN saved successfully.";
							       urn_panel.destroy();
							       remote_link_table.getDataSource().sendRequest("", {success: remote_link_table.onDataReturnInitializeTable, scope: remote_link_table});
							   }
						       },
						       failure: function(req, resp){
							   this.set("label", "Add");
							   this.set("disabled", false);
							   alert("Server error while adding remote link.");
						       },
						       scope: this
						   }
						   );

				});
			    
			    urn_panel.show();			    

			});

		});
	});
}
	

function removeRemoteLink(link_id, button){
    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=remove_remote_link&link_id="+link_id);
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "success"}],
	metaFields: {
	    error: "error"
	}
    };

    button.set("label", "Removing..");
    button.set("disabled", true);

    ds.sendRequest("",
		   {
		       success: function(req, resp){
			   button.set("label", "Removing..");
			   button.set("disabled", true);

			   if (resp.meta.error){
			       alert("Error while removing link: " + resp.meta.error);
			       return;
			   }

			   setup_remote_tab();

		       },
		       failure: function(req, resp){
			   button.set("label", "Remove");
			   button.set("disabled", false);
			   alert("Server error while removing remote link.");
		       }
		   }
		   );
}


function setup_users_tab(){

	
	 	

    var user_table = makeUserTable("user_table","search_users");

	var user_search = new YAHOO.util.Element(YAHOO.util.Dom.get('user_search'));
    
	var user_searchTimeout;
	 	user_search.on('keyup', function(e){
			var search_value = this.get('element').value;
			
	 		if (e.keyCode == YAHOO.util.KeyListener.KEY.ENTER){
				clearTimeout(user_searchTimeout);
				table_filter.call(user_table,search_value);
			}
			else{
				if (user_searchTimeout) clearTimeout(user_searchTimeout);
				
				user_searchTimeout = setTimeout(function(){
					table_filter.call(user_table,search_value);
				}, 400);
				
			} 
	    
		}
				 );





    user_table.subscribe("rowClickEvent", function(oArgs){

	    var record = this.getRecord(oArgs.target);

	    if (! record){
		return;
	    }

	    var user_id    = record.getData('user_id');
	    var first      = record.getData('first_name');
	    var family     = record.getData('family_name');
	    var email      = record.getData('email_address');
	    var auth_names = (record.getData('auth_name') || []).join(",")
	    	    
	    var region = YAHOO.util.Dom.getRegion(oArgs.target);

	    if (first.toLowerCase() == "system"){
		alert("You cannot edit this user.");
		this.unselectAllRows();
		return;
	    }
	    

	    showUserInfoPanel.call(this, user_id, first, family, email, auth_names, [region.left, region.bottom], oArgs);
	});

    function showUserInfoPanel(user_id, first_name, family_name, email, auth_names, xy, target){

	if (this.user_panel){
	    this.user_panel.destroy();
	    this.user_panel = null;
	}
	
	var p = new YAHOO.widget.Panel("user_details",
				       {width: 450,
					xy: xy,
					modal: true
				       }
				       );
	
	this.user_panel = p;
	
	p.setHeader("User Details");					    
	
	p.setBody("<table>" + 
		  "<tr>" +
		  "<td>First Name:</td>" +
		  "<td><input type='text' id='user_given_name' size='38'></td>" +
		  "</tr>" +
		  "<tr>" +
		  "<td>Last Name:</td>" +
		  "<td><input type='text' id='user_family_name' size='38'></td>" +
		  "</tr>" +
		  "<tr>" +
		  "<td>Email Address:</td>" +
		  "<td><input type='text' id='user_email_address' size='38'></td>" +
		  "</tr>" +
		  "<tr>" +
		  "<td>Username(s)<br>(comma separated)</td>" +
		  "<td><input type='text' id='user_auth_names' size='38'></td>" +
		  "</tr>"+
		  "</table>"+
		  "<div id='workgroup_membership_table'> </div>"
		  );
		
	p.setFooter("<div id='submit_user'></div><div id='delete_user'></div>");

	p.render(document.body);
		
	makeHelpPanel("user_given_name", "This is the user's first name(s).");
	makeHelpPanel("user_family_name", "This is the user's last, or family, name(s).");
	makeHelpPanel("user_email_address", "This is the user's email address. This will be used to notify the user about events that happen to circuits in this workgroup.");
	makeHelpPanel("user_auth_names", "These are the usernames that this user is identified by. These are typically what the REMOTE_USER field will be set to for whatever authentication method you are using. If multiple values would like to be used, just separate them with a comma.");

	YAHOO.util.Dom.get("user_given_name").value    = first_name  || "";
	YAHOO.util.Dom.get("user_family_name").value   = family_name || "";
	YAHOO.util.Dom.get("user_email_address").value = email || "";
	YAHOO.util.Dom.get("user_auth_names").value    = auth_names || "";

	YAHOO.util.Dom.get("user_given_name").focus();

	var submit_button = new YAHOO.widget.Button("submit_user", {label: "Save"});

	if (user_id){
	    var delete_button = new YAHOO.widget.Button("delete_user", {label: "Delete"});

	    delete_button.on("click", function(){

		    YAHOO.util.Dom.get("user_status").innerHTML = "";

		    var fname = YAHOO.util.Dom.get("user_given_name").value;
		    var lname = YAHOO.util.Dom.get("user_family_name").value;
		    
		    showConfirm("Are you sure you wish to delete user \"" + fname + " " + lname + "\"? Note that this action cannot be undone.",
				function(){
				    delete_button.set("label", "Deleting...");
				    delete_button.set("disabled", true);
				    submit_button.set("disabled", true);

				    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=delete_user&user_id="+user_id);
				    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
				    ds.responseSchema = {
					resultsList: "results",
					fields: [{key: "success"}],
					metaFields: {
					    error: "error"
					}
				    };
				    
				    ds.sendRequest("",
						   {
						       success: function(req, resp){
							   delete_button.set("label", "Delete");
							   delete_button.set("disabled", false);
							   submit_button.set("disabled", false);			
			   
							   if (resp.meta.error){
							       alert("Error delete user: " + resp.meta.error);
							   }
							   else{
							       p.destroy();
							       user_table.deleteRow(target.target);
							       YAHOO.util.Dom.get("user_status").innerHTML = "User deleted successfully.";
							   }
						       },
						       failure: function(req, resp){
							   delete_button.set("label", "Delete");
							   delete_button.set("disabled", false);
							   submit_button.set("disabled", false);
							   							   
							   alert("Server error while removing user.");
						       }
						   }
						   );
			
				},
				function(){}
				);

		});
	}

	submit_button.on("click", function(){
		this.set("label", "Saving...");
		this.set("disabled", true);

		var url = "../services/admin/admin.cgi?"

		if (! user_id){
		    url += "action=add_user";
		}
		else{
		    url += "action=edit_user&user_id="+user_id;
		}

		var fname = YAHOO.util.Dom.get("user_given_name").value;
		var lname = YAHOO.util.Dom.get("user_family_name").value;
		var email = YAHOO.util.Dom.get("user_email_address").value;
		var auth  = YAHOO.util.Dom.get("user_auth_names").value;

		if (! fname || !lname){
		    alert("You must specify a first and last name for this user.");
		    this.set("label", "Save");
		    this.set("disabled", false);
		    return;
		}

		if (! email){
		    alert("You must specify an email address for this user.");
		    this.set("label", "Save");
                    this.set("disabled", false);
		    return;
		}

		if (! auth){
		    alert("You must specify at least one username for this user.");
		    this.set("label", "Save");
                    this.set("disabled", false);
		    return;
		}

		url += "&first_name="+encodeURIComponent(fname);
		url += "&family_name="+encodeURIComponent(lname);
		url += "&email_address="+encodeURIComponent(email);

		var names = auth.split(",");

		for (var i = 0; i < names.length; i++){
		    url += "&auth_name="+encodeURIComponent(names[i]);
		}

		var ds = new YAHOO.util.DataSource(url);
		ds.responseType   = YAHOO.util.DataSource.TYPE_JSON;
		ds.responseSchema = {
		    resultsList: "results",
		    fields: [{key: "success"}],
		    metaFields: {
			error: "error"
		    }
		};

		YAHOO.util.Dom.get("user_status").innerHTML = "";

		ds.sendRequest("", 
			       {
				   success: function(req, resp){
				       if (resp.meta.error){
					   YAHOO.util.Dom.get("user_status").innerHTML = "Error saving user: " + resp.meta.error;
				       }
				       else{
					   YAHOO.util.Dom.get("user_status").innerHTML = "User saved successfully.";
				       }

				       p.destroy();

				       setup_users_tab();
				   },
				   failure: function(reqp, resp){
				       this.set("label", "Save");
				       this.set("disabled", false);
				       alert("Server error while saving user.");
				   },
				   scope: this
			       });

	    });

    };

    
    var add_user = new YAHOO.widget.Button("add_user_button", {label: "New User"});

    add_user.on("click", function(){

	    var region = YAHOO.util.Dom.getRegion("users_content");
	    
	    // get the popup nice and centered
	    var xy = [region.left + (region.width / 2) - 225,
		      region.top + (region.height / 2) - 75];

	    showUserInfoPanel.call(user_table, null, null, null, null, null, xy);
	});

}

function setup_workgroup_tab(){

    var region = YAHOO.util.Dom.getRegion("workgroups_content");

    var wg_panel = new YAHOO.widget.Panel("workgroup_details",
					  {
					      width: 850,
					      height: 600,
					      draggable: false,
					      visible: false,
					      close: false,
					      xy: [region.left, region.top]
					  }
				   );

    YAHOO.widget.Overlay.windowResizeEvent.subscribe(function(){ 
	    var region = YAHOO.util.Dom.getRegion("workgroups_content");
	    wg_panel.moveTo(region.left, region.top);
	});

    wg_panel.render("workgroups_content");

    var close_panel = new YAHOO.widget.Button("close_panel_button", {label: "Done"});
    close_panel.on("click", function(){
	    wg_panel.hide();
	});

    var wg_table = makeWorkgroupTable();

    wg_table.subscribe("rowClickEvent", function(oArgs){
	    try{
	    var record = this.getRecord(oArgs.target);

	    if (! record){
		return;
	    }

	    var workgroup_name = record.getData('name');
	    var workgroup_id   = record.getData('workgroup_id');

	    YAHOO.util.Dom.get('workgroup_title').innerHTML = workgroup_name;

	    var region = YAHOO.util.Dom.getRegion("workgroups_content");	    

	    wg_panel.moveTo(region.left, region.top);

	    var workgroup_user_table = makeWorkgroupUserTable(workgroup_id);

	    var workgroup_acl_table  = makeWorkgroupACLTable(workgroup_id);    

	    workgroup_user_table.subscribe("cellClickEvent", function(oArgs){

		    var col = this.getColumn(oArgs.target);
		    var rec = this.getRecord(oArgs.target);

		    var user_id = rec.getData('user_id');
		    var user    = rec.getData('first_name') + " " + rec.getData('family_name');

		    if (col.label != "Remove"){
			return;
		    }
		
		    showConfirm("Are you sure you wish to remove user \"" + user + "\"?",
				function(){
				    workgroup_user_table.disable();

				    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=remove_user_from_workgroup&user_id="+user_id+"&workgroup_id="+workgroup_id);
				    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
				    ds.responseSchema = {
					resultsList: "results",
					fields: [{key: "success"}],
					metaFields: {
					    error: "error"
					}
				    };
				    
				    ds.sendRequest("",
						   {
						       success: function(req, resp){
							   workgroup_user_table.undisable();
							   
							   if (resp.meta.error){
							       alert("Error removing user: " + resp.meta.error);
							   }
							   else{
							       workgroup_user_table.deleteRow(oArgs.target);
							   }
						       },
						       failure: function(req, resp){
							   workgroup_user_table.undisable();
							   alert("Server error while removing user.");
						       }
						   }
						   );
				},
				function(){}
				);

		});

	    workgroup_acl_table.subscribe("cellClickEvent", function(oArgs){
		    var col = this.getColumn(oArgs.target);
		    var rec = this.getRecord(oArgs.target);

		    var interface_id = rec.getData('interface_id');
		    var node_id      = rec.getData('node_id');

		    var int_name     = rec.getData('interface_name');
		    var node_name    = rec.getData('node_name');

		    if (col.label != "Remove"){
			return;
		    }
		
		    showConfirm("Are you sure you wish to remove interface \"" + int_name + "\" on endpoint \"" + node_name + "\"?",
				function(){
				    workgroup_acl_table.disable();

				    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=remove_workgroup_acl&workgroup_id="+workgroup_id+"&node_id="+node_id+"&interface_id="+interface_id);
				    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
				    ds.responseSchema = {
					resultsList: "results",
					fields: [{key: "success"}],
					metaFields: {
					    error: "error"
					}
				    };
				    
				    ds.sendRequest("",
						   {
						       success: function(req, resp){
							   workgroup_acl_table.undisable();
							   
							   if (resp.meta.error){
							       alert("Error removing ACL: " + resp.meta.error);
							   }
							   else{
							       workgroup_acl_table.deleteRow(oArgs.target);
							   }
						       },
						       failure: function(req, resp){
							   workgroup_acl_table.undisable();
							   alert("Server error while removing ACL.");
						       }
						   }
						   );
				},
				function(){}
				);
		});

	    var add_new_user = new YAHOO.widget.Button("add_new_workgroup_user", {label: "Add User to Workgroup"});

	    // show user select
	    add_new_user.on("click", function(){

		    var region = YAHOO.util.Dom.getRegion("workgroups_content");

		    var new_user_p = new YAHOO.widget.Panel("add_workgroup_user",
							    {modal: true,
							     xy: [region.left + (region.width / 2) - 300,
								  region.top + 75]
							    }
							    );

		    new_user_p.setHeader("Add User to Workgroup - Click to Add User");
		    new_user_p.setBody("<center>" +
				       "<div id='add_new_workgroup_user_table'></div>" +
				       "<div id='add_new_workgroup_user_table_nav'></div>" +
				       "<div id='add_result' class='soft_title confirmation'></div>" +
				       "</center>" + 
				       "<div style='text-align: right; font-size: 85%'>" + 
				       "<div id='done_add_user'></div>" + 
				       "</div>"
				       );

		    new_user_p.render("workgroups_content");		    

		    new_user_p.hideEvent.subscribe(function(){
			    this.destroy();
			});

		    var done_adding_users = new YAHOO.widget.Button('done_add_user', {label: "Done Adding Users"});
		    done_adding_users.on("click", function(){
			    new_user_p.hide();
			});

		    var user_table = makeUserTable('add_new_workgroup_user_table');

		    user_table.subscribe("rowClickEvent", function(oArgs){

			    this.disable();

			    YAHOO.util.Dom.get('add_result').innerHTML = "";

			    var record  = this.getRecord(oArgs.target);
			    var user_id = record.getData('user_id');
			    var first   = record.getData('first_name');
			    var last    = record.getData('family_name');

			    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=add_user_to_workgroup&workgroup_id=" + workgroup_id + "&user_id="+ user_id);
			    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
			    ds.responseSchema = {
				resultsList: "results",
				fields: [{key: "success"}],
				metaFields: { 
				    error: "error"
				}
			    };

			    ds.sendRequest("", 
					   {
					       success: function(req, resp){
						   user_table.undisable();
						   if (resp.meta.error){
						       YAHOO.util.Dom.get('add_result').innerHTML = "Error while adding user: " + resp.meta.error;
						   }
						   else{
						       YAHOO.util.Dom.get('add_result').innerHTML = "User added successfully.";
						       workgroup_user_table.addRow({user_id: user_id,
								                    first_name: first,
								                    family_name: last
								                    });
						   }
					       },
					       failure: function(req, resp){
						   user_table.undisable();
						   YAHOO.util.Dom.get('add_result').innerHTML = "Server error while adding user to workgroup.";
					       }
					   }
					   );
							       

			});

		});


	    var add_new_acl = new YAHOO.widget.Button("add_new_workgroup_acl", {label: "Add Edge Port"});


	    // show map to pick node / endpoint
	    add_new_acl.on("click", function(){

		    var region = YAHOO.util.Dom.getRegion('workgroups_content');

		    var add_acl_p = new YAHOO.widget.Panel("add_acl_p",
							   {modal: true,
							    width: 750,
							    height: 400,
							    xy: [region.left, 
								 region.top]
							   });

		    add_acl_p.setHeader("New Edge Port");
		    add_acl_p.setBody("<div id='acl_map' class='openlayers smaller' style='float: left;'></div>" + 
				      "<div id='new_interface_table' style='float: right;'></div>" +
				      "<br clear='both'><br>" +
				      "<center><div id='add_acl_status' class='soft_title confirmation'></div></center>" + 
				      "<div style='text-align: right; font-size: 85%'>" + 
				      "<div id='done_adding_edges'></div>" + 
				      "</div>"
				      );

		    add_acl_p.render('workgroups_content');

		    var done_adding = new YAHOO.widget.Button("done_adding_edges", {label: "Done Adding Edges"});
		    done_adding.on("click", function(){
			    add_acl_p.hide();
			});

		    var map = new NDDIMap('acl_map');

		    map.on("loaded", function(){
			    this.showDefault();
			    this.clearAllSelected();
			});

		    add_acl_p.hideEvent.subscribe(function(){
			    map.destroy();
			    this.destroy();
			});

		    map.on("clickNode", function(e, args){

			    this.clearAllSelected();

			    var feature = args[0].feature;
			    var node    = args[0].name;

			    this.changeNodeImage(feature, this.ACTIVE_IMAGE);

			    var ds = new YAHOO.util.DataSource("../services/data.cgi?action=get_node_interfaces&show_down=1&node="+encodeURIComponent(node));
			    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
			    ds.responseSchema = {
				resultsList: "results",
				fields: [
			                 {key: "name"},
			                 {key: "description"},
			                 {key: "interface_id", parser: "number"}
					 ],
				metaFields: {
				    error: "error"
				}
			    };
			    
			    var cols = [{key: "name", label: "Interface", width: 220}];
  
			    var configs = {
				height: "277px"
			    };
			    
			    var table = new YAHOO.widget.ScrollingDataTable("new_interface_table", cols, ds, configs);
			    
			    table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
			    table.subscribe("rowMouseoutEvent", table.onEventUnhighlightRow);
			    
			    table.subscribe("rowClickEvent", function(oArgs){
				    this.onEventSelectRow(oArgs);

				    YAHOO.util.Dom.get('add_acl_status').innerHTML = "";

				    var rec = this.getRecord(oArgs.target);

				    if (! rec){
					return;
				    }

				    var interface_id = rec.getData('interface_id');

				    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=add_workgroup_acl&workgroup_id="+workgroup_id+"&interface_id="+interface_id);
				    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
				    ds.responseSchema = {
					resultsList: "results",
					fields: [{key: "success"}],
					metaFields: {
					    error: "error"
					}
				    };

				    this.disable();

				    ds.sendRequest("",
						   {
						       success: function(req, resp){
							   table.undisable();
							   if (resp.meta.error){
							       YAHOO.util.Dom.get('add_acl_status').innerHTML = "Error adding edge port: " + resp.meta.error;
							   }
							   else{
							       YAHOO.util.Dom.get('add_acl_status').innerHTML = "Edge port added successfully.";
							       workgroup_acl_table.getDataSource().sendRequest("", {success: workgroup_acl_table.onDataReturnInitializeTable,scope:workgroup_acl_table});
							   }
						       },
						       failure: function(req, resp){
							   table.undisable();
							   YAHOO.util.Dom.get('add_acl_status').innerHTML = "Server error while adding new edge port.";
						       }
						   }
						   );

				});
			    

			});

		});


	    wg_panel.show();	    
	    }catch(e){alert(e);}
	});
    
    
    var add_workgroup = new YAHOO.widget.Button("add_workgroup_button", {label: "New Workgroup"});

    add_workgroup.on("click", function(){

	    var region = YAHOO.util.Dom.getRegion("workgroups_content");
	    
	    // get the popup nice and centered
	    var xy = [region.left + (region.width / 2) - 175,
		      region.top + (region.height / 2)];


	    var p = new YAHOO.widget.Panel("new_workgroup",
					   {
					       width: 350,
					       xy: xy,
					       modal: true
					   }
					   );

	    p.setHeader("New Workgroup");
	    p.setBody("Name: <input type='text' id='new_workgroup_name' size='38'>" +
				  "External ID: <input type='text' id='new_workgroup_external_id' size='33'>"+
				  "Workgroup Type: <select id='new_workgroup_type'>"+
				  "<option value=\"normal\">Normal</option>"+
				  "<option value=\"demo\">Demo</option>"+
				  "<option value=\"admin\">Admin</option>"+
				  "</select>");
	    p.setFooter("<div id='submit_new_workgroup'></div>");

	    p.render(document.body);

	    YAHOO.util.Dom.get('new_workgroup_name').focus();

	    makeHelpPanel("new_workgroup_name", "This is just the name of the workgroup you are creating. Its only significance is to distinguish between them.");	    

	    var submit_button = new YAHOO.widget.Button("submit_new_workgroup", {label: "Add Workgroup"});

	    submit_button.on("click", function(){
		    
		    var workgroup_name = YAHOO.util.Dom.get('new_workgroup_name').value;
			var external_id = YAHOO.util.Dom.get('new_workgroup_external_id').value;
			var workgroup_type= YAHOO.util.Dom.get('new_workgroup_type');
			workgroup_type= workgroup_type.options[workgroup_type.selectedIndex].value;
		    
			if (! workgroup_name){
			alert("You must specify a workgroup name.");
			return;
		    }

		    this.set("label", "Creating workgroup...");
		    this.set("disabled", true);

		    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=add_workgroup&name="+encodeURIComponent(workgroup_name)+"&external_id="+encodeURIComponent(external_id)+"&type="+encodeURIComponent(workgroup_type) );
		    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
		    ds.responseSchema = {
			resultsList: "results",
			fields: [{key: "success"}],
			metaFields: {
			    error: "error"
			}
		    };

		    YAHOO.util.Dom.get("workgroup_status").innerHTML = "";

		    ds.sendRequest("", 
				   {
				       success: function(req, resp){
					   if (resp.meta.error){
					       alert("Error creating workgroup: " + resp.meta.error);
					   }
					   else {
					       YAHOO.util.Dom.get("workgroup_status").innerHTML = "Workgroup created successfully.";
					       p.destroy();
					       setup_workgroup_tab();
					   }
				       },
				       failure: function(req, resp){
					   this.set("label", "Add Workgroup");
					   this.set("disabled", false);
					   alert("Server error while creating workgroup.");
				       },
				       scope: this
				   }
				   );
				       

		});

	});
}

function do_node_insert(link_id, map, delete_button, save_button, panel){
    showConfirm("This link has active circuits.  However there is a node in the middle of the path.  Would you like to automatically approve the new links and migrate all existing circuits onto the new paths?",
		function(){
		    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=insert_node_in_path&link_id=" + link_id);
		    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
		    
		    ds.responseSchema = {
			resultsList: "results",
			fields: [{key: "success"}]
		    };
		    save_button.set("disabled",true);
		    delete_button.set("disabled",true);
		    delete_button.set("label","Migrating circuits...");
		    
		    ds.sendRequest("",{ success: function(req,resp){
				delete_button.set("disabled", false);
				delete_button.set("label", "Decomission Link");
				save_button.set("disabled", false);

				if(resp.results[0].success == 1){
				    map.reinitialize();
				    panel.destroy();
				    panel = null;
				    YAHOO.util.Dom.get("active_network_update_status").innerHTML = "Link successfully decomissioned.";
				}else{
				    alert('Error while migrating circuits');
				}
			    },failure: function(req,resp){
				alert('error while communicating with server');
			    }

		},
		function(){}
		);
		});
}

function do_decom_link(link_id,map,delete_button,save_button,panel){

    showConfirm("Decomissioning this link will remove it. Are you sure you wish to continue?",
		function(){

		    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=decom_link&link_id="+link_id);
		    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;

		    ds.responseSchema = {
			resultsList: "results",
			fields: [{key: "success"}]
		    };

		    ds.sendRequest("",
				   {
				       success: function(req, resp){
					   delete_button.set("disabled", false);
					   delete_button.set("label", "Decomission Link");
					   save_button.set("disabled", false);

					   if (resp.results && resp.results[0].success == 1){
					       map.reinitialize();
					       panel.destroy();
					       panel = null;
					       YAHOO.util.Dom.get("active_network_update_status").innerHTML = "Link successfully decomissioned.";
					   }
					   else{
					       alert("Link decomission unsuccessful.");
					   }

				       },
					   failure: function(req, resp){
					   save_button.set("disabled", false);
					   delete_button.set("disabled", false);
					   delete_button.set("label", "Decomission Link");
					   alert("Error while talking to server.");
				       }
				   });

		},
		function(){}
		);

};


function setup_network_tab(){

    // clear out the old map if we have it (ie, might have confirmed something)
    YAHOO.util.Dom.get("active_network_map").innerHTML = "";

    var map = new NDDIMap("active_network_map");

    map.on("loaded", function(){
	    this.showDefault();
	    this.clearAllSelected();
	});

    var panel, save_button, delete_button;
    var _generate_link_panel = function(link) {
	    panel.setBody(
            "<table>" +
                //name field
			    "<tr>" + 
			    "<td>Name:</td>" +
			    "<td>" + 
			    "<input type='text' id='active_link_name' size='38'>" +
			    "</td>" +
			    "</tr>" +
                //metric field
			    "<tr>" + 
			    "<td>Metric:</td>" +
			    "<td>" + 
			    "<input type='text' id='active_link_metric' size='38'>" +
			    "</td>" +
			    "</tr>" +
            "</table>"
		);

        var editable_fields = [
            "name",
            "metric"
        ];
        //set values in all editable fields
        for( var i=0; i<editable_fields.length; i++){
            var field = editable_fields[i];
	        var input = YAHOO.util.Dom.get('active_link_'+field);
            input.value = link[field];
        }
	    
	    save_button.on("click", function(){

		    var new_name   = YAHOO.util.Dom.get('active_link_name').value;
		    var new_metric = YAHOO.util.Dom.get('active_link_metric').value;
		    
		    if (! new_name){
			alert("You must specify a name for this link.");
			return;
		    }
		
            var url  = "../services/admin/admin.cgi?action=update_link&link_id="+link.link_id;
                url += "&name="+encodeURIComponent(new_name);
            if(new_metric){
                url += "&metric="+encodeURIComponent(new_metric);
            }
           
		    var ds = new YAHOO.util.DataSource(url);
		    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
		    ds.responseSchema = {
			    resultsList: "results",
			    fields: [{key: "success"}]
		    };

		    delete_button.set("disabled", true);
		    save_button.set("disabled", true);
		    save_button.set("label", "Updating Link...");

		    ds.sendRequest("", {
                success: function(req, resp){
                    delete_button.set("disabled", false);
				    save_button.set("disabled", false);
				    save_button.set("label", "Update Link");

					if (resp.results && resp.results[0].success == 1){
					    map.reinitialize();
					    panel.destroy();
					    panel = null;
					    YAHOO.util.Dom.get("active_network_update_status").innerHTML = "Link successfully updated."
				    }
				    else{
					    alert("Link update unsuccessful.");
				    }

				},
				failure: function(req, resp){
				    delete_button.set("disabled", false);
				    save_button.set("disabled", false);
				    save_button.set("label", "Update Link");
				    alert("Error while talking to server.");
				}
            });
		    
		});
	    
	    delete_button.on("click", function(){
		    
		    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=is_ok_to_decom_link&link_id=" + link_id);
		    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
		    ds.responseSchema = {
			resultsList: "results",
			fields: [{key: "success"},
		                 {key: "active_circuits"},
		                 {key: "new_node_in_path"}]
		    }

		    ds.sendRequest("",{
			    success: function(req,resp){
				var data = resp.results[0];
				if(data.active_circuits.length <= 0){
				    do_decom_link(link_id,map,delete_button,save_button,panel);
				}else{
				    if(data.new_node_in_path == 0){
					alert('You can not decomission this link, there are active paths riding on it!');
				    }else{
					do_node_insert(link_id,map,delete_button,save_button,panel);
				    }
				}
			    }});

		});
	};
    map.on("clickLink", function(e, args){
        YAHOO.util.Dom.get("active_network_update_status").innerHTML = "";

        this.clearAllSelected();

        if (panel){
            panel.destroy();
            panel = null;
        }

        var link_name = args[0].name;
        var link_id   = args[0].link_id;
        var feature   = args[0].feature;

        this.changeLinkColor(feature, this.LINK_PRIMARY);

        panel = new YAHOO.widget.Panel("link_details",{
            width: 500,
            draggable: false
        });
	    panel.render(YAHOO.util.Dom.get("active_element_details"));

        panel.setHeader("Details for Link: " + link_name);
        panel.setBody("<p>Loading data...</p>");

        panel.setFooter("<div id='save_active_link'></div>" +
                        "<div id='delete_active_link'></div>");

        panel.hideEvent.subscribe(function(){
            map.clearAllSelected();
        });

        save_button   = new YAHOO.widget.Button("save_active_link", {label: "Update Link"});
        delete_button = new YAHOO.widget.Button("delete_active_link", {label: "Decomission Link"});

        var url =  "../services/data.cgi?action=get_link_by_name";
            url += "&name="+ encodeURIComponent(link_name);

        var ds = new YAHOO.util.DataSource(url);
        ds.responseType = YAHOO.util.DataSource.TYPE_JSON;

        ds.responseSchema = {
            resultsList: "results",
            fields: [
                {key: "link_id"},
                {key: "status"},
                {key: "remote_urn"},
                {key: "metric"},
                {key: "name"}
            ]
        };
        ds.sendRequest("",{
            success: function(req, resp){
                if (resp.results){
                    _generate_link_panel(resp.results[0]);
                }else{
                    alert("Could not fetch link data.");
                }
            },
            failure: function(req, resp){
                alert("Error while talking to server.");
            }
        });
    });

    map.on("clickNode", function(e, args){

	    YAHOO.util.Dom.get("active_network_update_status").innerHTML = "";

	    this.clearAllSelected();

	    if (panel){
		panel.destroy();
		panel = null;
	    }

	    var node_id    = args[0].node_id;
	    var node       = args[0].name;
	    var lat        = args[0].lat;
	    var lon        = args[0].lon;
	    var vlan_range = args[0].vlan_range;
	    var max_flows = args[0].max_flows;
	    var tx_delay_ms = args[0].tx_delay_ms;
	    var default_drop = args[0].default_drop;
	    var default_forward = args[0].default_forward;
	    var barrier_bulk = args[0].barrier_bulk;
	    var feature = args[0].feature;

       
        var ds = new YAHOO.util.DataSource("../services/data.cgi?action=get_node_interfaces&show_down=1&show_trunk=1&node="+encodeURIComponent(node) );
                
		    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
		    ds.responseSchema = {
			resultsList: "results",
			fields: [
		    {key: "name"},
		    {key: "description"},
		    {key: "vlan_tag_range"},
		    {key: "interface_id", parser: "number"},
		    {key: "int_role"}
				 ],
			metaFields: {
			    error: "error"
			}
		    };
			    
		    var cols = [{key:'name', label: "Interface", width: 60},
				{key:'description', label: "Description", width: 200, 
				 editor: new YAHOO.widget.TextboxCellEditor({  
					 asyncSubmitter: function( callback, newValue) {
					     var record = this.getRecord();
					     var column = this.getColumn();
					     var oldValue = this.value;
					     YAHOO.util.Connect.asyncRequest(
									     'get','../services/admin/admin.cgi?action=update_interface&interface_id='+record.getData('interface_id')+'&description='+encodeURIComponent(newValue),{
										 success:function(o) {
										     var r = YAHOO.lang.JSON.parse(o.responseText);
										     callback(true,  newValue );
										 },
										     failure: function(o){

										     callback(false, oldValue);
										 },
										     scope:this
										     
										     }
									     
									     );
					 }
				     } ) 
				},
				{key: 'vlan_tag_range', label: 'VLAN Tags', width: 220,
				 formatter: function(elLiner, oRec, oCol, oData){
					if(oRec.getData('int_role') == 'trunk'){
					    elLiner.innerHTML = 'TRUNK';
					}else{
					    elLiner.innerHTML = oRec.getData('vlan_tag_range');
					}
				    },
				 editor:new YAHOO.widget.TextboxCellEditor({
					    asyncSubmitter: function( callback, newValue) {
						var record = this.getRecord();
						var column = this.getColumn();
						var oldValue = this.value;
						YAHOO.util.Connect.asyncRequest(
										'get','../services/admin/admin.cgi?action=update_interface&interface_id='+record.getData('interface_id')+'&vlan_tag_range='+encodeURIComponent(newValue),{
										    success:function(o) {
											var r = YAHOO.lang.JSON.parse(o.responseText);
											callback(true,  newValue );
										    },
											failure: function(o){
											callback(false, oldValue);
										    },
											scope:this
											
											}
										
										);
					    }
					} )}
				
				];
		    
		    
		    
		    var configs = {
			height: "100px"
		    };
		    
		    



	    this.changeNodeImage(feature, this.ACTIVE_IMAGE);

	    panel = new YAHOO.widget.Panel("node_details",
					   { 
					       width: 700,
					       height: 400,
					       centered: true,
					       draggable: true
					   }
					   );

	    panel.setHeader("Details for Network Element: " + node);
	    panel.setBody("<table>" +
			  "<tr>" + 
			  "<td>Name:</td>" +
			  "<td colspan='4'>" + 
			  "<input type='text' id='active_node_name' size='38'>" +
			  "</td>" +
			  "</tr>" +
			  "<tr>" +
			  "<td>Latitude:</td>" +
			  "<td><input type='text' id='active_node_lat' size='10'></td>" +
			  "<td>Longitude:</td>" +
			  "<td><input type='text' id='active_node_lon' size='10'></td>" +
			  "</tr>" + 
			  "<tr>" +
			  "<td>Vlan Range:</td>" + 
			  "<td><input type='text' id='active_node_vlan_range' size='10'></td>" +
			  "</tr>" +
			  "<tr>" +
			  "<td colspan='2'>Default Forward LLDP to controller</td>"+
			  "<td><input type='checkbox' id='active_node_default_forward' checked /></td>" +
			  "</tr>" +
			  "<tr>" +
			  "<td colspan='2'>Default Drop Rule</td>" +
			  "<td><input type='checkbox' id='active_node_default_drop' checked /></td>" +
			  "</td>" +
			  "</tr>" +
			  "<tr>" + 
			  "<td colspan='2'>Maximum Number of Flow Mods</td>" +
			  "<td><input type='text' id='active_max_flows' size='10'></td>" +
			  "</tr>" +
			  "<tr>" +
			  "<td colspan='2'>FlowMod Processing Delay (ms)</td>" +
                          "<td><input type='text' id='active_tx_delay_ms' size='10'></td>" +
                          "</tr>" +
			  "<tr>" +
                          "<td colspan='2'>Send Bulk Flow Rules</td>" +
                          "<td><input type='checkbox' id='active_barrier_bulk' checked></td>" +
                          "</tr>" +
			  "</table>" +
			  "<div id='node_interface_table' style='margin-top:8px;'> </div>"
                     );

	    panel.setFooter("<div id='save_active_node'></div>" + 
			    "<div id='delete_active_node'></div>");
        
        

	    panel.hideEvent.subscribe(function(){
		    map.clearAllSelected();
		});

	    panel.render(YAHOO.util.Dom.get("active_element_details"));
	    
	    var table = new YAHOO.widget.ScrollingDataTable("node_interface_table", cols, ds, configs);
	    
	    table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
	    table.subscribe("rowMouseoutEvent", table.onEventUnhighlightRow);
	    table.subscribe("cellClickEvent", function (ev){ 
		    var target= YAHOO.util.Event.getTarget(ev);
		    var column = table.getColumn(target);
		    if (column.key=='description'){
			table.onEventShowCellEditor(ev);
		    }
		    if(column.key=='vlan_tag_range' && target.firstChild.innerHTML != 'TRUNK'){
			table.onEventShowCellEditor(ev);
		    }
		});

	    YAHOO.util.Dom.get('active_node_name').value        = node;
	    YAHOO.util.Dom.get('active_node_lat').value         = lat;
	    YAHOO.util.Dom.get('active_node_lon').value         = lon; 
	    YAHOO.util.Dom.get('active_node_vlan_range').value  = vlan_range;
	    YAHOO.util.Dom.get('active_tx_delay_ms').value             = tx_delay_ms;
	    YAHOO.util.Dom.get('active_max_flows').value                        = max_flows;
	    
	    if(default_drop == 0){
		YAHOO.util.Dom.get('active_node_default_drop').checked = false;
	    }

	    if(default_forward == 0){
		YAHOO.util.Dom.get('active_node_default_forward').checked = false;
	    }

	    if(barrier_bulk == 0){
		YAHOO.util.Dom.get('active_barrier_bulk').checked = false;
	    }

	    var save_button   = new YAHOO.widget.Button("save_active_node", {label: "Update Device"});
	    var delete_button = new YAHOO.widget.Button("delete_active_node", {label: "Decomission Device"});

	    save_button.on("click", function(){
		    var new_name  = YAHOO.util.Dom.get('active_node_name').value;
		    var new_lat   = YAHOO.util.Dom.get('active_node_lat').value;
		    var new_lon   = YAHOO.util.Dom.get('active_node_lon').value;
		    var new_range = YAHOO.util.Dom.get('active_node_vlan_range').value;
		    var new_max_flows = YAHOO.util.Dom.get('active_max_flows').value;
		    var new_tx_delay_ms = YAHOO.util.Dom.get('active_tx_delay_ms').value;
		    var new_default_drop = YAHOO.util.Dom.get('active_node_default_drop').checked;
		    var new_default_forward = YAHOO.util.Dom.get('active_node_default_forward').checked;
		    var new_barrier_bulk = YAHOO.util.Dom.get('active_barrier_bulk').checked;
		    if (! new_name){
			alert("You must specify a name for this device.");
			return;
		    }
		   
		    if (! new_lat || ! new_lat.match(/^\-?\d+(\.\d+)?$/) || new_lat < -90 || new_lat > 90){
			alert("You must specify a valid latitude at which this device will be visualized on the map.");
			return;
		    }
		    
		    if (! new_lon || ! new_lon.match(/^\-?\d+(\.\d+)?$/) || new_lon < -180 || new_lon > 180){
			alert("You must specify a valid longitude at which this device will be visualized on the map.");
			return;
		    }

		    var ranges = new_range.split(",");

		    for (var i = 0; i < ranges.length; i++){
		    	var segment = ranges[i];
		    	if (! segment.match(/^\d+$/) && ! segment.match(/^\d+-\d+$/)){
			   alert("You must specify a valid vlan range in the format \"1-3,5,7,8-10\"");
			   return;
			}				
		    }

		    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=update_node&node_id="+node_id+"&name="+encodeURIComponent(new_name)+"&latitude="+new_lat+"&longitude="+new_lon+"&vlan_range="+encodeURIComponent(new_range) + "&default_drop=" + encodeURIComponent(new_default_drop) + "&default_forward=" + encodeURIComponent(new_default_forward) + "&max_flows=" + encodeURIComponent(new_max_flows) + "&tx_delay_ms=" + encodeURIComponent(new_tx_delay_ms) + "&bulk_barrier=" + encodeURIComponent(new_barrier_bulk));
		    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;

		    ds.responseSchema = {
			resultsList: "results",
			fields: [{key: "success"}]
		    };

		    delete_button.set("disabled", true);
		    save_button.set("disabled", true);
		    save_button.set("label", "Updating Device...");

		    ds.sendRequest("", 
				   {
				       success: function(req, resp){
					   delete_button.set("disabled", false);
					   save_button.set("disabled", false);
					   save_button.set("label", "Update Device");

					   if (resp.results && resp.results[0].success == 1){
					       map.reinitialize();
					       panel.destroy();
					       panel = null;
					       YAHOO.util.Dom.get("active_network_update_status").innerHTML = "Device successfully updated."
					   }
					   else{
					       alert("Device update unsuccessful.");
					   }

				       },
				       failure: function(req, resp){
					   delete_button.set("disabled", false);
					   save_button.set("disabled", false);
					   save_button.set("label", "Update Device");
					   alert("Error while talking to server.");
				       }
				   });

		});

	    delete_button.on("click", function(){

		    showConfirm("Decomissioning this device will remove it and all links going to it. This will not impact existing circuits going across it presently, but you will not be able to add any more circuits that traverse this device. Are you sure you wish to continue?", 
				function(){

				    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=decom_node&node_id="+node_id);	
				    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
				    
				    ds.responseSchema = {
					resultsList: "results",
					fields: [{key: "success"}]
				    };
				    
				    save_button.set("disabled", true);
				    delete_button.set("disabled", true);
				    delete_button.set("label", "Decomissioning Device...");
				    
				    ds.sendRequest("", 
						   {
						       success: function(req, resp){
							   delete_button.set("disabled", false);
							   delete_button.set("label", "Decomission Device");
							   save_button.set("disabled", false);

							   if (resp.results && resp.results[0].success == 1){
							       map.reinitialize();
							       panel.destroy();
							       panel = null;
							       YAHOO.util.Dom.get("active_network_update_status").innerHTML = "Device successfully decomissioned.";
							   }
							   else{
							       alert("Device decomission unsuccessful.");
							   }
							   
						       },
						       failure: function(req, resp){
							   save_button.set("disabled", false);
							   delete_button.set("disabled", false);
							   delete_button.set("label", "Decomission Device");
							   alert("Error while talking to server.");
						       }
						   }); 
				    
				},
				function(){}
				);

		});
	});

}

function setup_discovery_tab(){    

    var node_table = makePendingNodeTable();
    
    var link_table = makePendingLinkTable();

    node_table.subscribe("rowClickEvent", function(oArgs){

	    var record = this.getRecord(oArgs.target);

	    if (! record){
		return;
	    }

	    var region = YAHOO.util.Dom.getRegion(oArgs.target);

	    if (this.details_panel){
		this.details_panel.destroy();
		this.details_panel = null;
	    }

	    var details_panel = new YAHOO.widget.Panel("node_details",
							{width: 400,
							 xy: [region.left, region.bottom],
							 modal: true
							}
							);

	    this.details_panel = details_panel;

	    this.details_panel.setHeader("Details for Device: " + record.getData('dpid'));

	    this.details_panel.setBody("<table>" +
				       "<tr>" + 
				       "<td>Name:</td>" +
				       "<td colspan='4'>" + 
				       "<input type='text' id='node_name' size='38'>" +
				       "</td>" +
				       "</tr>" +
				       "<tr>" +
				       "<td>Latitude:</td>" +
				       "<td><input type='text' id='node_lat' size='10'></td>" +
				       "<td>Longitude:</td>" +
				       "<td><input type='text' id='node_lon' size='10'></td>" +
				       "</tr>" + 
				       "<tr>" + 
				       "<td>Vlan Range:</td>" + 
				       "<td><input type='text' id='vlan_range' size='10'></td>" +
				       "</tr>" +
				       "<tr>" +
				       "<td colspan='2'>Default Forward LLDP to controller</td>"+
				       "<td><input type='checkbox' id='default_forward' checked /></td>" +
				       "</tr>" +
				       "<tr>" +
				       "<td colspan='2'>Default Drop Rule</td>" + 
				       "<td><input type='checkbox' id='default_drop' checked /></td>" +
				       "</td>" +
				       "</tr>" +
				       "<tr>" +
				       "<td colspan='2'>Maximum Number of Flow Mods</td>" +
				       "<td><input type='text' id='max_flows' size='10'></td>" +
				       "</tr>" +
				       "<tr>" +
				       "<td colspan='2'>FlowMod Processing Delay (ms)</td>" +
				       "<td><input type='text' id='tx_delay_ms' size='10'></td>" +
				       "</tr>" +
				       "<tr>" +
				       "<td colspan='2'>Send Bulk Flow Rules</td>" +
				       "<td><input type='checkbox' id='bulk_barrier' checked></td>" +
				       "</table>"
				       );

	    this.details_panel.setFooter("<div id='confirm_node'></div>");

	    this.details_panel.render(document.body);

	    if (record.getData('name')){
		YAHOO.util.Dom.get('node_name').value = record.getData('name');
	    }

	    if (record.getData('latitude')){
		YAHOO.util.Dom.get('node_lat').value = record.getData('latitude');
	    }

	    if (record.getData('longitude')){
		YAHOO.util.Dom.get('node_lon').value = record.getData('longitude');
	    }

	    if (record.getData('vlan_range')){
	       YAHOO.util.Dom.get('vlan_range').value = record.getData('vlan_range');
	    }	    

	    if(record.getData('default_forward')){
		YAHOO.util.Dom.get('default_forward').checked = record.getData('default_forward');
	    }

	    if(record.getData('default_drop')){
		YAHOO.util.Dom.get('default_drop').checked = record.getData('default_drop');
            }

	    if(record.getData('max_flows')){
		YAHOO.util.Dom.get('max_flows').checked = record.getData('max_flows');
            }

	    if(record.getData('tx_delay_ms')){
		YAHOO.util.Dom.get('tx_delay_ms').checked = record.getData('tx_delay_ms');
            }

	    if(record.getData('bulk_barrier')){
		YAHOO.util.Dom.get('bulk_barrier').checked = record.getData('bulk_barrier');
	    }

	    YAHOO.util.Dom.get("node_name").focus();

	    var confirm_button = new YAHOO.widget.Button("confirm_node", {label: "Confirm Device"});

	    confirm_button.on("click", function(e){

		    var lat   = YAHOO.util.Dom.get('node_lat').value;
		    var lon   = YAHOO.util.Dom.get('node_lon').value;
		    var name  = YAHOO.util.Dom.get('node_name').value;
		    var range = YAHOO.util.Dom.get('vlan_range').value;
		    var default_drop = YAHOO.util.Dom.get('default_drop').checked;
		    var default_forward = YAHOO.util.Dom.get('default_forward').checked;
		    var max_flows = YAHOO.util.Dom.get('max_flows').value;
		    var tx_delay_ms = YAHOO.util.Dom.get('tx_delay_ms').value;
		    var bulk_barrier = YAHOO.util.Dom.get('bulk_barrier').value;

		    if (! name){
			alert("You must specify a name for this device.");
			return;
		    }

		    if (name.match(/:/) || name.match(/\s/)){
			alert("You may not have spaces or colons in the name.");
			return;
		    }
		   
		    if (! lat || ! lat.match(/^\-?\d+(\.\d+)?$/) || lat < -90 || lat > 90){
			alert("You must specify a valid latitude at which this device will be visualized on the map.");
			return;
		    }
		    
		    if (! lon || ! lon.match(/^\-?\d+(\.\d+)?$/) || lon < -180 || lon > 180){
			alert("You must specify a valid longitude at which this device will be visualized on the map.");
			return;
		    }

		    var ranges = range.split(",");

		    for (var i = 0; i < ranges.length; i++){
		    	var segment = ranges[i];
		    	if (! segment.match(/^\d+$/) && ! segment.match(/^\d+-\d+$/)){
			   alert("You must specify a valid vlan range in the format \"1-3,5,7,8-10\"");
			   return;
			}				
		    }

		    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=confirm_node&node_id=" + record.getData('node_id') + "&name=" + encodeURIComponent(name) + "&latitude=" + encodeURIComponent(lat) + "&longitude=" + encodeURIComponent(lon) + "&vlan_range=" + encodeURIComponent(range) + "&default_drop=" + encodeURIComponent(default_drop) + "&default_forward=" + encodeURIComponent(default_forward) + "&max_flows=" + encodeURIComponent(max_flows) + "&tx_delay_ms=" + encodeURIComponent(tx_delay_ms) + "&bulk_barrier=" + encodeURIComponent(bulk_barrier));

		    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;

		    ds.responseSchema = {
			resultsList: "results",
			fields: [{key: "success"}]
		    };

		    confirm_button.set("disabled", true);
		    confirm_button.set("label", "Confirming Device...");

		    YAHOO.util.Dom.get("node_confirm_status").innerHTML = "";
		    YAHOO.util.Dom.get("link_confirm_status").innerHTML = "";

		    ds.sendRequest("", {success: function(req, resp){

				confirm_button.set("disabled", false);
				confirm_button.set("label", "Confirm Device");

				if (resp.results && resp.results[0].success == 1){
				    YAHOO.util.Dom.get("node_confirm_status").innerHTML = "Device successfully confirmed.";
				    node_table.deleteRow(record);
				    details_panel.hide();				 
				    makePendingLinkTable();
				    setup_network_tab();				 
				}
				else{
				    alert("Device confirmation unsuccessful.");
				}
			    },
			    failure: function(req, resp){
				confirm_button.set("disabled", false);
				confirm_button.set("label", "Confirm Device");

				alert("Server error while confirming device.");
			    }
			});
			
		});

       
	    this.details_panel.show();

	});

}

function makeWorkgroupACLTable(id){
    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=get_workgroup_acls&workgroup_id="+id);

    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "node_id", parser: "number"},
                 {key: "interface_id", parser: "number"},
                 {key: "node_name"},
                 {key: "interface_name"},
		 ]
    };

    var columns = [{key: "node_name", label: "Endpoint", width: 180 ,sortable:true},
				   {key: "interface_name", label: "Interface", width: 60 ,sortable:true},	  
	           {label: "Remove", formatter: function(el, rec, col, data){
			                           var b = new YAHOO.widget.Button({label: "Remove"});
						   b.appendTo(el);
		                                }
		   }
	           ];

    var config = {
		sortedBy: {key:'node_name', dir:'asc'},
		paginator:  new YAHOO.widget.Paginator({rowsPerPage: 10,
												containers: ["workgroup_acl_table_nav"]
	    })
    };

    var table = new YAHOO.widget.DataTable("workgroup_acl_table", columns, ds, config);
	
    table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
    table.subscribe("rowMouseoutEvent", table.onEventUnhighlightRow);

    return table;

}

function makeWorkgroupUserTable(id){

    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=get_users_in_workgroup&workgroup_id="+id);

    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "user_id", parser: "number"},
                 {key: "first_name"},
                 {key: "family_name"},
                 {key: "email_address"},
                 {key: "auth_name"}
		 ]
    };

    var columns = [{key: "first_name", label: "Name", width: 220,
		    formatter: function(el, rec, col, data){
		                    el.innerHTML = rec.getData("first_name") + " " + rec.getData("family_name");
	                       }
	           },
	           {label: "Remove", formatter: function(el, rec, col, data){
			                           var b = new YAHOO.widget.Button({label: "Remove"});
						   b.appendTo(el);
		                                }
		   }
	           ];

    var config = {
	paginator:  new YAHOO.widget.Paginator({rowsPerPage: 10,
						containers: ["workgroup_user_table_nav"]
	    })
    };

    var table = new YAHOO.widget.DataTable("workgroup_user_table", columns, ds, config);

    table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
    table.subscribe("rowMouseoutEvent", table.onEventUnhighlightRow);

    return table;
}

function makeUserTable(div_id,search_id){
    
    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=get_users");
    	
    
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "user_id", parser: "number"},
                 {key: "first_name"},
                 {key: "family_name"},
                 {key: "email_address"},
                 {key: "auth_name"}
		 ]
    };

    var columns = [{key: "first_name", label: "First Name", width: 100,sortable:true
		    /*formatter: function(el, rec, col, data){
		                    el.innerHTML = rec.getData("first_name") + " " + rec.getData("family_name");
	                       }*/
	           },
				   {key: "family_name",label:"Last Name", width: 100,sortable:true },
				   {key: "auth_name", label: "Username", width: 175,sortable:true},
				   {key: "email_address", label: "Email Address", width: 175,sortable:true}
	];

    var config = {
		sortedBy: {key:'first_name', dir:'asc'},
	paginator:  new YAHOO.widget.Paginator({rowsPerPage: 10,
						containers: [div_id + "_nav"]
	    })
    };

    var table = new YAHOO.widget.DataTable(div_id, columns, ds, config);

    table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
    table.subscribe("rowMouseoutEvent", table.onEventUnhighlightRow);
    table.subscribe("rowClickEvent", table.onEventSelectRow);
	//Caching Data for search
	table.on("dataReturnEvent", function(oArgs){		       		     
	    this.cache = oArgs.response;
	    return oArgs;
    });
    return table;
}

function makeWorkgroupTable(){

	var searchTimeout;
    
    var search = new YAHOO.util.Element(YAHOO.util.Dom.get('workgroup_search'));
    
    search.on('keyup', function(e){
		
	    var search_value = this.get('element').value;
		
	    if (e.keyCode == YAHOO.util.KeyListener.KEY.ENTER){
		clearTimeout(searchTimeout);
			table_filter.call(table,search_value);
	    }
	    else{
		if (searchTimeout) clearTimeout(searchTimeout);
		
		searchTimeout = setTimeout(function(){
			table_filter.call(table,search_value);
		    }, 400);
		
	    } 
	    
	}
	);
    
	
    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=get_workgroups");

    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "workgroup_id", parser: "number"},
                 {key: "name"},
                 {key: "description"}
		 ]
    };

    var columns = [{key: "name", label: "Name", sortable:true,width: 180}
		   ];

    var config = {
	paginator: new YAHOO.widget.Paginator({rowsPerPage: 10,
										   containers: ["workgroup_table_nav"]
										  }),
		sortedBy:{key:'name',dir:'asc'}
    };


    var table = new YAHOO.widget.DataTable("workgroup_table", columns, ds, config);

    table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
    table.subscribe("rowMouseoutEvent", table.onEventUnhighlightRow);
    table.subscribe("rowClickEvent", table.onEventSelectRow);

	table.on("dataReturnEvent", function(oArgs){		       		     
	    this.cache = oArgs.response;
	    return oArgs;
    });
    


    return table;
}

function makePendingNodeTable(){

    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=get_pending_nodes");

    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "node_id", parser: "number"},
                 {key: "dpid"},
                 {key: "ip_address"},
                 {key: "longitude"},
                 {key: "latitude"},
                 {key: "name"},
		 {key: "vlan_range"},
		 ]
    };

    var columns = [{key: "name", label: "Name", width: 205},
		   {key: "dpid", label: "Datapath ID", width: 135},
		   {key: "ip_address", label: "IPv4 Address", width: 100}
		   ];

    var config = {
	paginator: new YAHOO.widget.Paginator({rowsPerPage: 10,
					       containers: ["node_table_nav"]
	    })
    };

    
    var table = new YAHOO.widget.DataTable("node_table", columns, ds, config);
    var dsCallback = {
        success: table.onDataReturnInitializeTable,
        failure: function(){
        },
        scope: table
    };
            

    ds.setInterval(15000,null,dsCallback);
    table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
    table.subscribe("rowMouseoutEvent", table.onEventUnhighlightRow);
    table.subscribe("rowClickEvent", table.onEventSelectRow);

    return table;
}

function makePendingLinkTable(){

    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=get_pending_links");

    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "link_id", parser: "number"},
                 {key: "name"},
                 {key: "endpoints"}
		 ]
    };

    var columns = [{label: "Endpoint A", width: 230, formatter: function(el, rec, col, data){
		         var endpoints = rec.getData('endpoints');
			 el.innerHTML = endpoints[0].node + " - " + endpoints[0].interface;
	            }
	           },
	           {label: "Endpoint Z", width: 230, formatter: function(el, rec, col, data){
			 var endpoints = rec.getData('endpoints');
			 el.innerHTML = endpoints[1].node + " - " + endpoints[1].interface;
		    }
		   }
		   ];

    var config = {
	paginator: new YAHOO.widget.Paginator({rowsPerPage: 10,
					       containers: ["link_table_nav"]
	    })
    };


    var table = new YAHOO.widget.DataTable("link_table", columns, ds, config);

    var dsCallback = {
        success: table.onDataReturnInitializeTable,
        failure: function(){
        },
        scope: table
    };

    ds.setInterval(15000,null,dsCallback);

    table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
    table.subscribe("rowMouseoutEvent", table.onEventUnhighlightRow);
    table.subscribe("rowClickEvent", table.onEventSelectRow);

    table.subscribe("rowClickEvent", function(oArgs){
	    
	    var record = this.getRecord(oArgs.target);

	    if (! record){
		return;
	    }
	    
	    var region = YAHOO.util.Dom.getRegion(oArgs.target);

	    if (this.details_panel){
		this.details_panel.destroy();
		this.details_panel = null;
	    }

	    var details_panel = new YAHOO.widget.Panel("link_details",
							{width: 400,
							 xy: [region.left, region.bottom],
							 modal: true
							}
							);

	    this.details_panel = details_panel;

	    this.details_panel.setHeader("Details for New Link");

	    this.details_panel.setBody("<table>" +
				       "<tr>" + 
				       "<td>Name:</td>" +
				       "<td>" + 
				       "<input type='text' id='link_name' size='38'>" +
				       "</td>" +
				       "</tr>" +
				       "</table>"
				       );

	    this.details_panel.setFooter("<div id='confirm_link'></div>");

	    this.details_panel.render(document.body);

	    YAHOO.util.Dom.get("link_name").focus();

	    if (record.getData('name')){
		YAHOO.util.Dom.get('link_name').value = record.getData('name');
	    }

	    var confirm_button = new YAHOO.widget.Button("confirm_link", {label: "Confirm Link"});

	    confirm_button.on("click", function(e){

		    var name = YAHOO.util.Dom.get('link_name').value;

		    if (! name){
			alert("You must specify a name for this link.");
			return;
		    }

		    if (name.match(/:/) || name.match(/\s/)){
			alert("You may not have spaces or colons in the name.");
			return;
		    }
		   
		    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?action=confirm_link&link_id=" + record.getData('link_id') + "&name=" + encodeURIComponent(name));
		    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;

		    ds.responseSchema = {
			resultsList: "results",
			fields: [{key: "success"}]
		    };

		    confirm_button.set("disabled", true);
		    confirm_button.set("label", "Confirming Link...");

		    YAHOO.util.Dom.get("link_confirm_status").innerHTML = "";
		    YAHOO.util.Dom.get("node_confirm_status").innerHTML = "";

		    ds.sendRequest("", {success: function(req, resp){

				confirm_button.set("disabled", false);
				confirm_button.set("label", "Confirm Link");

				if (resp.results && resp.results[0].success == 1){
				    YAHOO.util.Dom.get("link_confirm_status").innerHTML = "Link successfully confirmed.";
				    table.deleteRow(record);
				    details_panel.hide();
				    setup_network_tab();
				}
				else{
				    alert("Link confirmation unsuccessful.")
				}
			    },
			    failure: function(req, resp){
				confirm_button.set("disabled", false);
				confirm_button.set("label", "Confirm Link");

				alert("Server error while confirming link.");
			    }
			});
			
		});

	    this.details_panel.show();

	});
    
    return table;
    
}


YAHOO.util.Event.onDOMReady(admin_init);

</script>
