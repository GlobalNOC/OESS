<script type='text/javascript' src='../js_utilities/interface_acl_panel.js'></script>
<script type='text/javascript' src='../js_utilities/datatable_utils.js'></script>
<script type='text/javascript' src='../js_utilities/interface_acl_table.js'></script>
<script type='text/javascript' src='../js_utilities/multilink_panel.js'></script>
<script type='text/javascript' src='../js_utilities/misc_funcs.js'></script>

<script>
var add_new_user_to_workgroup = 0;
var remote_link_table;
var link_maint_table;
var node_maint_table;
var int_move_maint_table;
var config_table;
var third_party_mgmt = '[% third_party_mgmt %]';
console.log(third_party_mgmt);
function admin_init(){

    var tabs = new YAHOO.widget.TabView("admin_tabs", {orientation: "left"});

    setup_discovery_tab();

    setup_network_tab();

    setup_users_tab();

    setup_workgroup_tab();

    setup_remote_tab();

    setup_remote_dev_tab();

    setup_maintenance_tab();

    setup_config_changes_tab();
}

function setup_config_changes_tab() {
    makeConfigTable('config_table');
}

function display_mpls(obj) {
    var state = 'none';
    if (obj.checked == true) {
        state = 'table-row';
    }

    var elements = YAHOO.util.Dom.getElementsByClassName('mpls');
    for (var i = 0; i < elements.length; i++) {
        elements[i].style.display = state;
    }
}

function makeConfigPanel(x, y, width, obj) {
    var pre = YAHOO.util.Dom.get('config_diff_pre');
    pre.node_id = obj.getData('node_id');

    YAHOO.util.Dom.setStyle(['config_diff_pre'], 'display', 'block');
    YAHOO.util.Dom.setStyle(['config_diff_pre'], 'padding', '5px');
    YAHOO.util.Dom.setStyle(['config_diff_pre'], 'margin', '5px');
    YAHOO.util.Dom.setStyle(['config_diff_pre'], 'border-style', 'solid');
    YAHOO.util.Dom.setStyle(['config_diff_pre'], 'border-color', '#c1c1c1');
    YAHOO.util.Dom.setStyle(['config_diff_pre'], 'border-width', '2px');
    YAHOO.util.Dom.setStyle(['config_diff_pre'], 'width', '95%');
    YAHOO.util.Dom.setStyle(['config_diff_pre'], 'height', '300px');
    YAHOO.util.Dom.setStyle(['config_diff_pre'], 'overflow', 'auto');

    load_diff = function(node_id) {
      var url    = '../services/admin/admin.cgi?';
      var params = 'method=get_diff_text' + '&node_id='  + node_id;

      var pre = YAHOO.util.Dom.get('config_diff_pre');
      pre.innerHTML = 'Loading diff...';

      var ds = new YAHOO.util.DataSource(url);
      ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
      ds.responseSchema = {
        resultsList: "results",
        fields: [
          {key: 'text'}
        ],
        metaFields: {
          error_text: "error_text"
        }
      };

      ds.sendRequest(params, {
        success: function(req, resp) {
          if (resp.meta.error_text) {
            pre.innerHTML = 'Failed to generate diff: ' + resp.meta.error_text;
            return null;
          }

          if (resp.results[0].text == "\n" || resp.results[0].text == "") {
            // TODO This is here due to a bug in the backend
            pre.innerHTML = "No diff required at this time.";
          } else {
            pre.innerHTML = resp.results[0].text;
          }
          return 1;
        },
        failure: function(req, resp){
          pre.innerHTML = 'Failed to receive diff. Please try again later.';
          console.log('Request failed: ' + resp.error);
        }
      });
    };

    var approve = new YAHOO.widget.Button('approve_diff_btn', {label: 'Approve'});
    approve.node_id = obj.getData('node_id');

    approve.on('click', function() {
        approve.set('label', 'Approving...');

        var url    = '../services/admin/admin.cgi?';
        var params = 'method=set_diff_approval'+
            '&node_id='  + this.node_id +
            '&approved=' + '1';

        var ds = new YAHOO.util.DataSource(url, { connMethodPost: true } );
        ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
        ds.responseSchema = {
            resultsList: "results",
            fields: [ ],
            metaFields: {
                error: "error"
            }
        };

        ds.sendRequest(params, {
            success: function(req, resp){
                if (resp.meta.error){
                    alert("Error adding maintenance: " + resp.meta.error, null, {error: true});
                    return;
                }

                var msg = 'Configuration change was approved.';
                alert(msg);
                panel.hide();
            },
            failure: function(req, resp){
                add_button.set('label', 'Add');
                alert('Server error occured while approving change.' , null, {error: true});
            }
        });
    });

    var panel  = new YAHOO.widget.Panel('config_details', {
        width: width,
        xy: [x, y],
        modal: true
    });
    panel.approve_button = approve;
    panel.load_diff      = load_diff;

    panel.load = function(node_id, name) {
	  this.setHeader('Configuration Details - ' + name);
	  this.setFooter('Approve this pending configuration?');

	  this.approve_button.node_id = node_id;
	  this.load_diff(node_id);
    };

    panel.hideEvent.subscribe(function() {
        pre.innerHTML = 'Loading diff...';
    });

    panel.load(obj.getData('node_id'), obj.getData('name'));
    return panel;
}

function makeConfigTable(div_id) {

    var state_formatter = function(el, rec, col, data) {
        var is_pending = rec.getData("pending_diff");
        var html;

        if (is_pending == "2") {
            html = '<p style="color:#BA2617">Error</p>';
        } else if (is_pending == "1") {
            html = '<p style="color:#BA7717">Pending Approval</p>';
        } else {
            html = '<p style="color:#59BA17">OK</p>';
        }
        el.innerHTML = html;
    };
    
    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=get_diffs");
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
        resultsList: "results",
        fields: [
            {key: "node_id"},
            {key: "name"},
            {key: "pending_diff"}
        ]
    };

    var columns = [
        {key: "node_id", label: "NodeId", hidden: true, sortable: false},
        {key: "name", label: "Switch", width: 180, sortable: true},
        {key: "pending_diff", label: "State", width: 110, sortable: true, formatter: state_formatter}
    ];
    
    var config = {
        sortedBy: {key:'name', dir:'asc'}
    };

    var config_panel;

    var rowClickHandler = function(oArgs) {
        var obj = this.getRecord(oArgs.target);
        if (!obj) {
            return;
        }

        var region = YAHOO.util.Dom.getRegion(oArgs.target);
        var width = 400;

        var x = ((region.left + region.right) / 2) - (width / 2);
        var y = region.bottom;

        if (config_panel == null) {
            config_panel = makeConfigPanel(x, y, width, obj);
            config_panel.render(document.body);
        } else {
	    config_panel.load(obj.getData('node_id'), obj.getData('name'));
            config_panel.show();
        }
    };

    var table = new YAHOO.widget.DataTable(div_id, columns, ds, config);
    table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
    table.subscribe("rowMouseoutEvent", table.onEventUnhighlightRow);
    table.subscribe("rowClickEvent", table.onEventSelectRow);
    table.subscribe("rowClickEvent", rowClickHandler);

    ds.setInterval(15000, null, {
        success: table.onDataReturnInitializeTable,
        failure: function() {},
        scope:   table
    });

    return table;
}


function setup_remote_dev_tab(){

    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=get_remote_devices");
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
        panel.hideEvent.subscribe(function(){
            this.destroy();
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

                    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=update_remote_device&node_id="+node_id+
                                                       "&name="+ encodeURIComponent(rec.getData("name")) +
                                                       "&latitude=" + new_lat +
                                                       "&longitude="+ new_lon
                                                       );
                    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;

                    ds.responseSchema = {
                        resultsList: "results",
                        fields: [{key: "success"}]
                    };

                    //this.set("disabled", true);
                    //this.set("label", "Saving...");

                    YAHOO.util.Dom.get("remote_dev_update_status").innerHTML = "";

                    ds.sendRequest("",
                                   {
                                       success: function(req, resp){
                                           //this.set("disabled", false);
                                           //this.set("label", "Save");

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
                                           //this.set("disabled", false);
                                           //this.set("label", "Save");

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
    var view_topo_button = new YAHOO.widget.Button("view_topo_button", {label: "View Topology"});

    resubmit_button.on("click", function(){
            var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=submit_topology");
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

    view_topo_button.on("click", function(){
            var region = YAHOO.util.Dom.getRegion('remote_content');
            var view_topo_p = new YAHOO.widget.Panel("view_topo_p",
                                               {modal: true,
                                                width: 750,
                                                height: 720,
                                                xy: [region.left,
                                                     region.top]
                                               });

            view_topo_p.setHeader("Current Topology");
            view_topo_p.render("remote_content");
        view_topo_p.hideEvent.subscribe(function(){
            this.destroy();
        });
            var topo_ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=get_topology");
            topo_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
            topo_ds.responseSchema = {
                resultsList: "results",
                fields: [{key: "topo"}],
                metaFields: {
                    error: "error",
            error_text: "error_text"
                }
            };

            topo_ds.sendRequest("",{ success: function(Request,Response){
            var text = "Error Fetching Topology";
            if(!Response.meta.error){
                            text = Response.results[0].topo;
            }
            else if(Response.meta.error){
                text = Response.meta.error_text;
            }
            view_topo_p.setBody("<div style='overflow: scroll; height: 100%; width: 100%'><pre>" + text + "</pre></div>");
                    }, 
                        failure: function(Request,Response){
                            view_topo_p.setBody("<div style='overflow: scroll; height: 100%; width: 100%'><pre>Error Fetching Topology</pre></div>");
                    },
                        scope: topo_ds});
            

        });

    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=get_remote_links");
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
        resultsList: "results",
        fields: [
            {key: "link_id", parser: "number"},
            {key: "link_name"},
            {key: "node"}, 
            {key: "interface"},
            {key: "interface_id"},
            {key: "urn"},
            {key: "vlan_tag_range"}
        ], 
        metaFields: {
            error: "error"
        }
    };

    var columns = [
                   {key: "node", label: "Endpoint", minWidth: 120,maxWidth: 200, sortable: true, formatter: function(el, rec, col, data){
                    el.innerHTML = rec.getData("node") + " - " + rec.getData("interface");
            }},
        {key: "urn", label: "URN", width: 400, sortable: true},
                   {key: "vlan_tag_range", label: "Vlan Range", maxWidth: 300, sortable: true},
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
                }},

                {label: "Edit", formatter: function(el, rec, col, data){
            var b = new YAHOO.widget.Button({label: "Edit"});
            b.appendTo(el);
            b.on("click", function(){
                        editRemoteLink(rec.getData("link_id"), rec.getData("link_name"), rec.getData("urn"),rec.getData("vlan_tag_range"),rec.getData("interface"),rec.getData("interface_id"), b);
            });
                }}
        ];

    var config = {
        paginator:  new YAHOO.widget.Paginator({rowsPerPage: 10,
                                                containers: ["remote_link_table_nav"]
            })
    };

    remote_link_table = new YAHOO.widget.DataTable("remote_link_table", columns, ds, config);

    var new_button = new YAHOO.widget.Button("add_new_remote_link", {label: "New Remote Link"});

    new_button.on("click", function(){

            var region = YAHOO.util.Dom.getRegion('remote_content');
            
            var add_remote_p = new YAHOO.widget.Panel("add_remote_link_p",
                                                   {modal: true,
                                                    width: 750,
                                                    height: 435,
                                                    xy: [region.left, 
                                                         region.top],
                                                    zIndex: 100
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
                    add_remote_p.destroy();
                });
            
            var map = new NDDIMap('remote_map', null, { node_label_status: false });
            
            map.on("loaded", function(){
                    //this.showDefault();
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

                    var ds = new YAHOO.util.DataSource("../services/data.cgi?method=get_node_interfaces&node="+encodeURIComponent(node) + "&show_down=1");
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
                        height: "300px"
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
                                              "<input id='remote_link_name' type='text' size='35' style='margin-bottom: 2px; margin-left: 45px;'>" + 
                                              "<br><label for='remote_urn' class='soft_title'>Remote URN:</label>" +
                                              "<input style='margin-left: 1px; margin-bottom: 2px;' id='remote_urn' type='text' size='35'>" +
                                              "<br><label for='remote_vlan_range' class='soft_title'>Vlan Range:</label>" +
                                              "<input style='margin-left: 10px' id='remote_vlan_range' type='text' size='35'>"
                                              );
                            urn_panel.setFooter("<div id='save_urn'></div>");

                            urn_panel.render('add_remote_link_p_c');


                            var save_button = new YAHOO.widget.Button("save_urn", {label: "Add"});

                            save_button.on("click", function(){
                                    var urn        = YAHOO.util.Dom.get("remote_urn").value;
                                    var name       = YAHOO.util.Dom.get("remote_link_name").value;
                                    var vlan_range = YAHOO.util.Dom.get("remote_vlan_range").value;
                                    var regexp = new RegExp(/ /);
                                    if(regexp.exec(name)){
                                        alert("URN Names can not contain spaces");
                                        return;
                                    }
                                    //validate vlan range
                                    var ranges = vlan_range.split(",");
                                    for (var i = 0; i < ranges.length; i++){
                                        var segment = ranges[i];
                                        if (! segment.match(/^\d+$/) && ! segment.match(/^\d+-\d+$/)){
                                            alert("You must specify a valid vlan range in the format \"1-3,5,7,8-10\"");
                                            return;
                                        }
                                    }

                                    if (! urn){
                                        alert("You must specify a URN for this remote link.");
                                        return;
                                    }
                                    
                                    if (! name){
                                        alert("You must specify a name for this link.");
                                        return;
                                    }

                    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=get_remote_links");
                    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                    ds.responseSchema = {
                        resultsList: "results",
                        fields: [
                            {key: "link_id", parser: "number"},
                            {key: "node"}, 
                            {key: "interface"},
                            {key: "interface_id"},
                            {key: "urn"},
                            {key: "vlan_tag_range"},
                            {key: "link_name"}
                        ],
                        metaFields: {
                            error: "error"
                        }
                    };

                                    ds.sendRequest("",
                                                   {
                                                       success: function(req, resp){
                                                           this.set("label", "Add");
                                                           this.set("disabled", false); 

                                                           if (resp.meta.error){
                                                           }
                                                           else {
                                    var index;
                                    var alert_same;
                                    var name_conflict;
                                    var alert_message = "Warning! Duplicate remote link information found on interface " + interface_name + "!<br/><br/>";
                                    for (index = 0; index < resp.results.length; ++index){
                                        if (resp.results[index].vlan_tag_range == vlan_range && resp.results[index].interface_id == interface_id){
                                            alert_same = 1;
                                            alert_message += "Link '" + name + "' has the same vlan_range as the link you are trying to create!<br/>"
                                        }
                                        if (resp.results[index].urn == urn && resp.results[index].interface_id == interface_id){
                                            alert_same =1;
                                            alert_message += "Link '" + name + "' has the same urn as the link you are trying to create!<br/>";
                                        }

                                        if (resp.results[index].link_name ==name && resp.results[index].interface_id == interface_id){
                                            name_conflict = 1;
                                        }

                                    }

                                    
                                    if (alert_same){


                                        if (name_conflict){
                                            name_conflict = 0;
                                            alert("You cannot create a link with this name: '" + name + "' <br/>Duplicate name found.");
                                        }
                                        else{
                                            alert_message += "Are you sure you want to create this link with duplicate information?";
                                            showConfirm(alert_message, 
                                                   function(){

                                                        add_the_link(save_button);
                                                   }, 
                                                   function(){
                                                   });
                                        }
                                    }
                                    else {
                                        if (name_conflict){
                                            name_conflict = 0;
                                            alert("You cannot create a link with this name: '" + name + "' <br/>Duplicate name found.");
                                        }
                                        else{
                                            add_the_link(save_button);
                                        }
                                    }

                                    function add_the_link(save_button){ 
                                        save_button.set("disabled", true);
                                        save_button.set("label", "Adding Remote URN...");

                                        var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=add_remote_link" +
                                                           "&interface_id=" + interface_id +
                                                           "&urn=" + encodeURIComponent(urn) + 
                                                           "&name=" + encodeURIComponent(name) +
                                                           "&vlan_tag_range=" + encodeURIComponent(vlan_range)
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
                                                   save_button.set("label", "Add");
                                                   save_button.set("disabled", false);  

                                                   if (resp.meta.error){
                                                       YAHOO.util.Dom.get("add_remote_status").innerHTML = "Error: " + resp.meta.error;
                                                       alert_same = 0;
                                                   }
                                                   else {
                                                       YAHOO.util.Dom.get("add_remote_status").innerHTML = "Remote URN saved successfully.";
                                                       urn_panel.destroy();
                                                       remote_link_table.getDataSource().sendRequest("", {success: remote_link_table.onDataReturnInitializeTable, scope: remote_link_table});
                                                       remote_link_table.reload();
                                                       alert_same = 0;
                                                   }
                                                   },
                                                   failure: function(req, resp){
                                                   save_button.set("label", "Add");
                                                   save_button.set("disabled", false);
                                                   alert("Server error while adding remote link.");
                                                   alert_same=0;
                                                   },
                                                   scope: save_button
                                               }
                                               );

                                               }
                                                }
                                               },
                                               failure: function(req, resp){
                                               save_button.set("label", "Add");
                                               save_button.set("disabled", false);
                                               alert("Server error while checking for remote link conflicts.");
                                               },
                                               scope: save_button
                                           }
                                           );


                                    });
                            
                            urn_panel.show();                       

                        });

                });
        });
}


function editRemoteLink(link_id,name, urn, vlan_tag_range,interface_name,interface_id, button) {
    var region = YAHOO.util.Dom.getRegion('remote_content');
    var urn_panel = new YAHOO.widget.Panel("remote_urn_p", {
        width: 370,
        xy: [region.left, region.bottom],
        zIndex: 10
    });

    urn_panel.setHeader("Edit the link:");
    urn_panel.setBody("<label for='remote_link_name' class='soft_title'>Name:</label>" +
                      "<input id='remote_link_name' type='text' size='35' style='margin-bottom: 2px; margin-left: 45px;' value='"+name+"'>" +
                      "<br><label for='remote_urn' class='soft_title'>Remote URN:</label>" +
                      "<input style='margin-left: 1px; margin-bottom: 2px;' id='remote_urn' type='text' size='35' value='"+urn+"'>" +
                      "<br><label for='remote_vlan_range' class='soft_title'>Vlan Range:</label>" +
                      "<input style='margin-left: 10px' id='remote_vlan_range' type='text' size='35' value='"+vlan_tag_range+"'>"
                     );
    urn_panel.setFooter("<div id='save_urn'></div>" + 
                        "<br><center><div id='edit_remote_status' class='soft_title confirmation'></div></center>");

    urn_panel.render('remote_content');
    var save_button = new YAHOO.widget.Button("save_urn", {label: "Update"});

    save_button.on("click", function() {
        var urn        = YAHOO.util.Dom.get("remote_urn").value;
        var name       = YAHOO.util.Dom.get("remote_link_name").value;
        var vlan_range = YAHOO.util.Dom.get("remote_vlan_range").value;
        var regexp = new RegExp(/ /);
        if(regexp.exec(name)){
            alert("URN Names can not contain spaces");
            return;
        }
        //validate vlan range
        var ranges = vlan_range.split(",");
        for (var i = 0; i < ranges.length; i++){
            var segment = ranges[i];
            if (! segment.match(/^\d+$/) && ! segment.match(/^\d+-\d+$/)){
                alert("You must specify a valid vlan range in the format \"1-3,5,7,8-10\"");
                return;
            }
        }

        if (! urn){
            alert("You must specify a URN for this remote link.");
            return;
        }

        if (! name){
            alert("You must specify a name for this link.");
            return;
        }

        var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=get_remote_links");
        ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
        ds.responseSchema = {
            resultsList: "results",
            fields: [
                {key: "link_id", parser: "number"},
                {key: "node"},
                {key: "interface"},
                {key: "interface_id"},
                {key: "urn"},
                {key: "vlan_tag_range"},
                {key: "link_name"}
            ],
            metaFields: {
                error: "error"
            }
        };

        ds.sendRequest("", {
            success: function(req, resp){
                this.set("label", "Update");
                this.set("disabled", false);

                if (resp.meta.error){
                }
                else {
                    var index;
                    var alert_same;
                    var name_conflict;
                    var alert_message = "Warning! Duplicate remote link information found on interface " + interface_name + "!<br/><br/>";
                    for (index = 0; index < resp.results.length; ++index) {
                        if (resp.results[index].vlan_tag_range == vlan_range && resp.results[index].interface_id == interface_id) {
                            alert_same = 1;
                            alert_message += "Link '" + name + "' has the same vlan_range you are trying to assign to this link!<br/>"
                        }
                        if (resp.results[index].urn == urn && resp.results[index].interface_id == interface_id) {
                            alert_same = 1;
                            alert_message += "Link '" + name + "' has the same urn as you are trying to assign to this link<br/>";
                        }
                        if (resp.results[index].link_name == name && resp.results[index].interface_id != interface_id) {
                            name_conflict = 1;
                        }
                    }

                    if (alert_same){
                        if (name_conflict) {
                            name_conflict = 0;
                            alert("You cannot change the link to this name: '" + name + "' <br/>Duplicate name found.");
                        }
                        else {
                            alert_message += "Are you sure you want to edit this link so it has duplicate information?";
                            showConfirm(alert_message,
                                        function() {
                                            edit_the_link(save_button);
                                        },
                                        function(){
                                        });
                        }
                    } else {
                        if (name_conflict){
                            name_conflict = 0;
                            alert("You cannot change the link to this name: '" + name + "' <br/>Duplicate name found.");
                        }
                        else{
                            edit_the_link(save_button);
                        }
                    }

                    function edit_the_link(save_button){
                        save_button.set("disabled", true);
                        save_button.set("label", "Updating Remote URN...");

                        var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=edit_remote_link" +
                                                           "&link_id=" + encodeURIComponent(link_id) +
                                                           "&urn=" + encodeURIComponent(urn) +
                                                           "&name=" + encodeURIComponent(name) +
                                                           "&vlan_tag_range=" + encodeURIComponent(vlan_range)
                                                          );

                        ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                        ds.responseSchema = {
                            resultsList: "results",
                            fields: [{key: "success"}],
                            metaFields: {
                                error: "error"
                            }
                        };

                        YAHOO.util.Dom.get("remote_update_status").innerHTML = "";
                        ds.sendRequest("", {
                            success: function(req, resp) {
                                save_button.set("label", "Update");
                                save_button.set("disabled", false);

                                if (resp.meta.error){
                                    YAHOO.util.Dom.get("remote_update_status").innerHTML = "Error: " + resp.meta.error;
                                    alert_same = 0;
                                } else {
                                    YAHOO.util.Dom.get("remote_update_status").innerHTML = "Remote URN saved successfully.";
                                    remote_link_table.getDataSource().sendRequest("", {success: remote_link_table.onDataReturnInitializeTable, scope: remote_link_table});
                                    urn_panel.destroy();
                                    alert_same = 0;
                                }
                            },
                            failure: function(req, resp) {
                                save_button.set("label", "Update");
                                save_button.set("disabled", false);
                                alert("Server error while updating remote link.");
                                alert_same=0;
                            },
                            scope: save_button
                        });
                    }
                }
            },
            failure: function(req, resp){
                save_button.set("label", "Update");
                save_button.set("disabled", false);
                alert("Server error while checking for remote link conflicts.");
            },
            scope: save_button
        });
    });
    urn_panel.show();
}


function removeRemoteLink(link_id, button){
var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=remove_remote_link&link_id="+link_id);
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

                           //setup_remote_tab();
                           remote_link_table.getDataSource().sendRequest('', { success: remote_link_table.onDataReturnInitializeTable, scope: remote_link_table });
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
    
    });
    if (third_party_mgmt === 'n'){
        user_table.subscribe("rowClickEvent", function(oArgs){

            var record = this.getRecord(oArgs.target);

            if (! record){
                return;
            }

            var user_id    = record.getData('user_id');
            var first      = record.getData('first_name');
            var family     = record.getData('family_name');
            var email      = record.getData('email_address');
            var auth_names = (record.getData('auth_name') || []).join(",");
            var type       = record.getData('type');
        var status     = record.getData('status');
                    
            var region = YAHOO.util.Dom.getRegion(oArgs.target);

            if (first.toLowerCase() == "system"){
                alert("You cannot edit this user.");
                this.unselectAllRows();
                return;
            }
            

            showUserInfoPanel.call(this, user_id, first, family, email, auth_names, type, status, [region.left, region.bottom], oArgs);
        });
    }

    function showUserInfoPanel(user_id, first_name, family_name, email, auth_names, type, status, xy, target){
        
            if (this.user_panel){
                this.user_panel.destroy();
                this.user_panel = null;
            }
            
            var p = new YAHOO.widget.Panel("user_details",{
            width: 450,
                    xy: xy,
                    modal: true
            });
            
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
                          "<tr>" +
                          "<td>User Type</td>" +
                          "<td><select id='user_type'><option value='normal'>Normal</option><option value='read-only'>Read-Only</option></select></td>" +
                          "</tr>" +
                          "<tr>" +
                          "<td>Status</td>" +
                          "<td><select id='user_admin_status'><option value='active'>Active</option><option value='decom'>Decom</option></select></td>" +
                          "</tr>" +
                          "</table>"+
                  "<div style='text-align:left;margin-top:5px;'>"+
                  "   <label>Workgroup Membership:</label>"+
                  "</div>"+
                          "<div id='user_workgroup_table'></div>"+
                  "<div id='add_user_to_workgroup'></div>"
                         );
                
            p.setFooter("<div id='submit_user'></div>");
        
            p.render(document.body);
                
            makeHelpPanel("user_given_name", "This is the user's first name(s).");
            makeHelpPanel("user_family_name", "This is the user's last, or family, name(s).");
            makeHelpPanel("user_email_address", "This is the user's email address. This will be used to notify the user about events that happen to circuits in this workgroup.");
            makeHelpPanel("user_auth_names", "These are the usernames that this user is identified by. These are typically what the REMOTE_USER field will be set to for whatever authentication method you are using. If multiple values would like to be used, just separate them with a comma.");
            makeHelpPanel("user_type", "Specifies either a normal user or a read-only user.  If a user is a read-only user then they can view everything that every user can see in their workgroup, however they are unable to affect any changes on the system.  A normal user can make changes that affect the system.");
            makeHelpPanel("user_admin_status", "Specifies the administrative status of the user. Active users may use OESS as their permissions allow. Decom users are prevented from using OESS at all.");
        
            if(type == 'normal'){
                type = 0;
            }else{
                type = 1;
            }

        if(status == 'active'){
            YAHOO.util.Dom.get("user_admin_status").selectedIndex  = 0;
        }
        else if(status == 'decom'){
            YAHOO.util.Dom.get("user_admin_status").selectedIndex  = 1;
        }
        else {
            YAHOO.util.Dom.get("user_admin_status").selectedIndex  = 0;
        }
        
            YAHOO.util.Dom.get("user_given_name").value    = first_name  || "";
            YAHOO.util.Dom.get("user_family_name").value   = family_name || "";
            YAHOO.util.Dom.get("user_email_address").value = email || "";
            YAHOO.util.Dom.get("user_auth_names").value    = auth_names || "";
            YAHOO.util.Dom.get("user_type").selectedIndex  = type || 0;
            YAHOO.util.Dom.get("user_given_name").focus();
        
            var submit_button = new YAHOO.widget.Button("submit_user", {label: "Save"});
        
            submit_button.on("click", function(){
                    this.set("label", "Saving...");
                    this.set("disabled", true);
            
                    var url = "../services/admin/admin.cgi?"
            
                    if (! user_id){
                        url += "method=add_user";
                    }
                    else{
                        url += "method=edit_user&user_id="+user_id;
                    }
            
                    var fname = YAHOO.util.Dom.get("user_given_name").value;
                    var lname = YAHOO.util.Dom.get("user_family_name").value;
                    var email = YAHOO.util.Dom.get("user_email_address").value;
                    var auth  = YAHOO.util.Dom.get("user_auth_names").value;
                    var type  = YAHOO.util.Dom.get("user_type").value;
                    var status  = YAHOO.util.Dom.get("user_admin_status").value;
            
                    if (! type ){
                        type = "normal";
                    }
            
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
            
            if (fname.toLowerCase() == 'system'){
                alert("You cannot use the word 'system', as a first name.");
                this.set("label", "Save");
                this.set("disabled", false);
                return;
            }
            
                    url += "&first_name="+encodeURIComponent(fname);
                    url += "&family_name="+encodeURIComponent(lname);
                    url += "&email_address="+encodeURIComponent(email);
                    url += "&type="+encodeURIComponent(type);
            url += "&status="+encodeURIComponent(status);
                    var names = auth.split(",");
            
                    for (var i = 0; i < names.length; i++){
                        url += "&auth_name="+encodeURIComponent(names[i]);
                    }
            
                    var ds = new YAHOO.util.DataSource(url);
                    ds.responseType   = YAHOO.util.DataSource.TYPE_JSON;
                    ds.responseSchema = {
                        resultsList: "results",
                fields: [
                                {key: "success"},
                    {key: "user_id"}
                        ],
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
                                       user_id = resp.results[0].user_id;
                                       
                                       
                                       if (!add_new_user_to_workgroup) {
                                                           p.destroy();
                                                           setup_users_tab();
                                       }
                                       
                                       else{
                                           
                                           var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=add_user_to_workgroup&workgroup_id=" + add_new_user_to_workgroup + "&user_id="+ user_id + "&role=normal");
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
                                                                  //user_table.undisable();
                                                                  if (resp.meta.error){
                                                                      //YAHOO.util.Dom.get('add_result').innerHTML = "Error while adding user: " + resp.meta.error;
                                                                      alert("User created, but error adding to workgroup requested.");
                                                                      setup_users_tab();
                                                                      p.destroy();
                                                                      add_new_user_to_workgroup;
                                                                  }
                                                                  else{
                                                                      //YAHOO.util.Dom.get('add_result').innerHTML = "User added successfully.";
                                                                      p.destroy();
                                                                      setup_users_tab();
                                                                      
                                                                      add_new_user_to_workgroup = 0;
                                                                  }
                                                              },
                                                              failure: function(req, resp){
                                                                  
                                                                  alert("User created, but server error in adding to workgroup requested.");
                                                                  
                                                                  setup_users_tab();
                                                                  p.destroy();
                                                                  add_new_user_to_workgroup;
                                                                  //user_table.undisable();
                                                                  //YAHOO.util.Dom.get('add_result').innerHTML = "Server error while adding user to workgroup.";
                                                              }
                                                          }
                                                         );
                                           
                                       }
                                   }
                                               },
                                               failure: function(reqp, resp){
                                                   this.set("label", "Save");
                                                   this.set("disabled", false);
                                                   alert("Server error while saving user.");
                                               },
                                               scope: this
                                       });
            
            
            });
        
        makeUserWorkgroupTable(user_id,first_name,family_name)
        
    };
    
    if (third_party_mgmt === 'n') {
        var add_user = new YAHOO.widget.Button("add_user_button", {label: "New User"});
    
        add_user.on("click", function(){
        
            var region = YAHOO.util.Dom.getRegion("users_content");
            
            // get the popup nice and centered
            var xy = [region.left + (region.width / 2) - 225,
                          region.top + (region.height / 2) - 75];
        
            showUserInfoPanel.call(user_table, null, null, null, null, null, null, xy);
        });
    }
    
}

function setup_workgroup_tab(){



    var wg_table = makeWorkgroupTable();
    var new_workgroup_panel; 
    wg_table.subscribe("rowClickEvent", function(oArgs){       
            
        var wg_details_panel; 
        var new_user_p;
        var add_int_p;
        
        var region = YAHOO.util.Dom.getRegion("workgroups_content");
        
        var record = this.getRecord(oArgs.target);

            if (! record){
                return;
            }

        var wg_panel = new YAHOO.widget.Panel("workgroup_details",
                                          {
                                              width: 875,
                                              height: 600,
                                              draggable: false,
                                              visible: true,
                                              close: false,
                                              xy: [region.left, region.top]
                                          }
                                   );
        
        wg_panel.hideEvent.subscribe(function(){

            wg_panel.destroy(); 
            
            }); 

        YAHOO.widget.Overlay.windowResizeEvent.subscribe(function(){ 
                region = YAHOO.util.Dom.getRegion("workgroups_content");
                wg_panel.moveTo(region.left, region.top);
            });
        console.log(record);
        var workgroup_name = record.getData('name');
        var workgroup_type = record.getData('type');
        var workgroup_id   = record.getData('workgroup_id');
        var workgroup_external = record.getData('external_id');
        if(workgroup_external === null){
            workgroup_external = "";
        }
        var max_mac_address_per_end = record.getData('max_mac_address_per_end');
        var max_circuit_endpoints = record.getData('max_circuit_endpoints');
        var max_circuits = record.getData('max_circuits');

            //YAHOO.util.Dom.get('workgroup_title').innerHTML = workgroup_name;
        
        wg_panel.setBody(
        "<div class='hd'></div>"+
        "<div class='bd' style='overflow: auto; overflow-y: hidden;'>"+
          "<center>"+
        "<div style='margin:auto'>"+
          "<div><p class='title' id='workgroup_title'>"+workgroup_name+"</p></div>"+
          "<div id='edit_workgroup_button'></div>"+
        "</div>"+
        "<div style='width: 35%; float: left;'>"+
          "<p class='soft_title'>Users in Workgroup</p>"+
          "<div id='workgroup_user_table'></div>"+
          "<div id='workgroup_user_table_nav'></div>"+
          "<br>"+
          "<div id='add_new_workgroup_user'></div>"+
        "</div>"+
        "<div style='width: 65%; float: left;'>"+
          "<p class='soft_title'>Owned Interfaces</p>"+
          "<div id='owned_interfaces_table'></div>" +
          "<div id='owned_interfaces_table_nav'></div>" +
          "<br>"+
          "<div id='add_new_owned_interfaces'></div>"+
        "</div>"+
        "<br clear='both'>"+
        "<div style='position: absolute; bottom: 10; right: 10;'>"+
          "<div id='close_panel_button'></div>"+
       "</div>"+
          "</center>"+
        "</div>"+
      "</div>" 
            );

       wg_panel.render("workgroups_content");

       
        
       var close_panel = new YAHOO.widget.Button("close_panel_button", {label: "Done"});
        close_panel.on("click", function(){

                wg_panel.destroy();

            });
        

           var add_new_owned_int = new YAHOO.widget.Button("add_new_owned_interfaces", {label: "Add Interface"});
           if (third_party_mgmt === 'n'){
           var add_new_user = new YAHOO.widget.Button("add_new_workgroup_user", {label: "Add User to Workgroup"});
           var wg_edit_button = new YAHOO.widget.Button("edit_workgroup_button",
                                                 {label: "Edit Workgroup Details"});
           wg_edit_button.on("click",function(){
                    wg_details_panel = new YAHOO.widget.Panel("workgroup_details_p",
                                                                  {width: 400,
                                                                   height: 150,
                                                                   draggable: true,
                                                                   close: true,
                                                                   fixedcenter: true,
                                   modal: true
                                                                  });

            wg_details_panel.hideEvent.subscribe(function(){
                    wg_details_panel.destroy();
                });

                    wg_details_panel.setBody(
                "<label>Workgroup Name:</label>"+
                "<input type='text' id='workgroup_name_edit' value='" + workgroup_name + "'>"+
                "<br>"+
                "<br>"+
                "<label>External ID:</label>"+
                "<input type='text' id='workgroup_external_edit' value='" + workgroup_external + "'>" +
                "<br>"+
                "<label>Circuit Limit:</label>"+
                "<input type='text' id='workgroup_max_circuits_edit' value='" + max_circuits + "'>" +
                "<br>"+
                "<div style='text-align: right; font-size: 85%'>" +
                "<div id='submit_edit_workgroup'></div>" +
                "</div>"
            );
                    //wg_details_panel.setFooter("<div id='submit_edit_workgroup'></div>");
            wg_details_panel.setHeader("Edit Workgroup Details");
                    wg_details_panel.render("workgroups_content");
            var wg_submit_edit = new YAHOO.widget.Button("submit_edit_workgroup",
                                                                 {label: "submit"});
                    wg_submit_edit.on("click", function(){
                max_circuits = document.getElementById("workgroup_max_circuits_edit").value;
                if(!max_circuits.match(/\d+/)){
                    alert("Circuits limit must be an integer");
                    return;
                }
                var submit_ds_url= "../services/admin/admin.cgi?method=edit_workgroup&workgroup_id=" + workgroup_id + "&name=" + encodeURI(document.getElementById('workgroup_name_edit').value) + "&max_circuits=" + max_circuits;
                //determine if workgroup external id is defined
                workgroup_external = document.getElementById('workgroup_external_edit').value;
                if( (workgroup_external !== undefined) &&
                    (workgroup_external !=  "") &&
                    (workgroup_external !== null) ){
                    submit_ds_url += "&external_id=" + encodeURI(workgroup_external);
                }

                            var submit_ds = new YAHOO.util.DataSource(submit_ds_url);
                            submit_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                            submit_ds.responseSchema = {
                                resultsList: "results",
                                fields: ["success","error"]
                            }
                            submit_ds.sendRequest();
                            wg_details_panel.hide();
                        });
                                             });
            }

            var workgroup_user_table = makeWorkgroupUserTable(workgroup_id);

            var owned_interfaces_table  = makeOwnedInterfaceTable(workgroup_id);    

            workgroup_user_table.subscribe("cellClickEvent", function(oArgs){

                    var col = this.getColumn(oArgs.target);
                    var rec = this.getRecord(oArgs.target);

                    var user_id = rec.getData('user_id');
                    var user    = rec.getData('first_name') + " " + rec.getData('last_name');

                    if (col.label != "Remove"){
                        return;
                    }
                
                    showConfirm("Are you sure you wish to remove user \"" + user + "\"?",
                                function(){
                                    workgroup_user_table.disable();

                                    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=remove_user_from_workgroup&user_id="+user_id+"&workgroup_id="+workgroup_id);
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



            owned_interfaces_table.subscribe("cellClickEvent", function(oArgs){
                    var col = this.getColumn(oArgs.target);
                    var rec = this.getRecord(oArgs.target);

                    var interface_id = rec.getData('interface_id');
                    var node_id      = rec.getData('node_id');

                    var int_name     = rec.getData('interface_name');
                    var node_name    = rec.getData('node_name');

                    if (col.label != "Remove"){
                        return;
                    }
                
                    showConfirm("Removing the interface will remove all acl rules the workgroup has associated with it. Are you sure you wish to remove interface \"" + int_name + "\" on endpoint \"" + node_name + "\"?",
                                function(){
                                    owned_interfaces_table.disable();

                                    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=update_interface_owner&interface_id="+interface_id);
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
                                                           owned_interfaces_table.undisable();
                                                           
                                                           if (resp.meta.error){
                                                               alert("Error removing ACL: " + resp.meta.error);
                                                           }
                                                           else{
                                                               owned_interfaces_table.deleteRow(oArgs.target);
                                                           }
                                                       },
                                                       failure: function(req, resp){
                                                           owned_interfaces_table.undisable();
                                                           alert("Server error while removing ACL.");
                                                       }
                                                   }
                                                   );
                                },
                                function(){}
                                );
                });

            
        // show user select
            if (third_party_mgmt === 'n') {
            add_new_user.on("click", function(){

                    var region = YAHOO.util.Dom.getRegion("workgroups_content");

                    new_user_p = new YAHOO.widget.Panel("add_workgroup_user",
                                                            {
                                                  xy: [region.left + (region.width / 2) - 300,
                                                                  region.top + 75],
                                    modal: true
                                                            }
                                                            );

                    new_user_p.setHeader("Add User to Workgroup - Click to Add User");
                    new_user_p.setBody("<center>" +
                                       "<label for='add_new_wg_user_search' id='add_new_wg_user_search_label' class='soft_title'>Search:</label>" +
                                       "<input id='add_new_wg_user_search' type='text' size='25'>" +
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
                            new_user_p.destroy();
                //new_user_p;
                        });

                    var done_adding_users = new YAHOO.widget.Button('done_add_user', {label: "Done Adding Users"});
                    done_adding_users.on("click", function(){
                            new_user_p.destroy();
                        });

                    var user_table = makeUserTable('add_new_workgroup_user_table');

                    var wg_user_search = new YAHOO.util.Element(YAHOO.util.Dom.get('add_new_wg_user_search'));

                    var wg_user_searchTimeout;
                    wg_user_search.on('keyup', function(e){
                            var search_value = this.get('element').value;

                            if (e.keyCode == YAHOO.util.KeyListener.KEY.ENTER){
                                clearTimeout(wg_user_searchTimeout);
                                table_filter.call(user_table,search_value);
                            }
                            else{
                                if (wg_user_searchTimeout) clearTimeout(user_searchTimeout);

                                user_searchTimeout = setTimeout(function(){
                                        table_filter.call(user_table,search_value);
                                    }, 400);

                            }

                        });

                    
                    user_table.subscribe("rowClickEvent", function(oArgs){

                            this.disable();

                            YAHOO.util.Dom.get('add_result').innerHTML = "";

                            var record  = this.getRecord(oArgs.target);
                            var user_id = record.getData('user_id');
                            var first   = record.getData('first_name');
                            var last    = record.getData('family_name');

                            var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=add_user_to_workgroup&workgroup_id=" + workgroup_id + "&user_id="+ user_id + "&role=normal");
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
            }




            // show map to pick node / endpoint
            add_new_owned_int.on("click", function(){
              var region = YAHOO.util.Dom.getRegion('workgroups_content');

              add_int_p = new YAHOO.widget.Panel("add_int_p", {
                width: 850,
                height: 400,
                xy: [
                  region.left, 
                  region.top
                ],
                modal: true
              });
              add_int_p.setHeader("Add Interface to Workgroup");
              add_int_p.setBody("<div id='acl_map' class='openlayers smaller' style='float: left;'></div>" + 
                                "<div id='new_interface_table' style='float: right;'></div>" +
                                "<br clear='both'><br>" +
                                "<center><div id='add_int_status' class='soft_title confirmation'></div></center>" + 
                                "<div style='text-align: right; font-size: 85%'>" + 
                                "<div id='done_adding_edges'></div>" + 
                                "</div>");
              add_int_p.render('workgroups_content');

              var done_adding = new YAHOO.widget.Button("done_adding_edges", {label: "Done Adding Interfaces"});
              done_adding.on("click", function(){
                add_int_p.destroy();
              });

              var map = new NDDIMap('acl_map', null, { node_label_status: false });
              map.on("loaded", function(){
                //this.showDefault();
                this.clearAllSelected();
              });

              add_int_p.hideEvent.subscribe(function(){
                map.destroy();
                add_int_p.destroy();
              });

              map.on("clickNode", function(e, args){
                this.clearAllSelected();

                var feature = args[0].feature;
                var node    = args[0].name;

                this.changeNodeImage(feature, this.ACTIVE_IMAGE);

                var url = "../services/data.cgi?method=get_node_interfaces&node=" + encodeURIComponent(node) + "&show_down=1";
                if (workgroup_type === "admin") {
                  url = url + "&show_trunk=1";
                }
                
                var ds = new YAHOO.util.DataSource(url);
                ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                ds.responseSchema = {
                  resultsList: "results",
                  fields: [
                    {key: "name"},
                    {key: "description"},
                    {key: "int_role"},
                    {key: "interface_id", parser: "number"}
                  ],
                  metaFields: {
                    error: "error"
                  }
                };
                            
                var cols = [
                  {key: "name", label: "Interface", width: 80},
                  {key: "description", label: "Description", width: 150},
                  {key: "int_role", label: "Role", width: 50, formatter: function(elLiner, oRec, oCol, oData) {
                    if (oData === "unknown") {
                      elLiner.innerHTML = "Endpoint";
                    } else {
                      elLiner.innerHTML = "Trunk";
                    }
                  }}
                ];

                // Removes role column from table when not working with
                // the 'admin' workgroup. Assumes role is stored in
                // third column from the left.
                if (workgroup_type !== "admin") {
                  ds.responseSchema.fields.splice(2, 1);
                  cols.splice(2, 1);
                }
  
                var configs = {
                  height: "277px"
                };
                            
                var table = new YAHOO.widget.ScrollingDataTable("new_interface_table", cols, ds, configs);
                console.log(table);
                table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
                table.subscribe("rowMouseoutEvent", table.onEventUnhighlightRow);
                table.subscribe("rowClickEvent", function(oArgs){
                  this.onEventSelectRow(oArgs);

                  YAHOO.util.Dom.get('add_int_status').innerHTML = "";

                  var rec = this.getRecord(oArgs.target);
                  if (!rec) {
                    return;
                  }

                  var interface_id = rec.getData('interface_id');

                  //first check to see if this interface is already owned by another work group
                  var ds = new YAHOO.util.DataSource("../services/data.cgi?method=get_interface&interface_id="+interface_id);
                  ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                  ds.responseSchema = {
                    resultsList: "results",
                    fields: [
                      {
                        key: "workgroup_id",
                        key: "workgroup_name"
                      }
                    ],
                    metaFields: {
                      error: "error"
                    }
                  };
                  ds.sendRequest("", {
                    success: function(req,resp){
                      if(!resp.results){
                        throw("Error fetching interface");
                      } else {
                        var workgroup_name = resp.results[0].workgroup_name;
                        var update_interface_owner = function() {
                          var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=update_interface_owner&workgroup_id="+workgroup_id+"&interface_id="+interface_id);
                          ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                          ds.responseSchema = {
                            resultsList: "results",
                            fields: [
                              {key: "success"}
                            ],
                            metaFields: {
                              error: "error"
                            }
                          };
             
                          table.disable();

                          ds.sendRequest("", {
                            success: function(req, resp){
                              table.undisable();
                              if (resp.meta.error){
                                YAHOO.util.Dom.get('add_int_status').innerHTML = "Error adding interface: " + resp.meta.error;
                              } else{
                                YAHOO.util.Dom.get('add_int_status').innerHTML = "Interface added successfully.";
                                owned_interfaces_table.getDataSource().sendRequest("", {success: owned_interfaces_table.onDataReturnInitializeTable,scope:owned_interfaces_table});
                              }
                            },
                            failure: function(req, resp){
                              table.undisable();
                              YAHOO.util.Dom.get('add_int_status').innerHTML = "Server error while adding new edge interface.";
                            }
                          }, this);
                        }
                        
                        if(workgroup_name) {
                          showConfirm("This interface is already owned by workgroup, "+workgroup_name+". Changing the workgroup will removed all of the acl rules that "+workgroup_name+" has associated to it. Are you sure you want to change the owner?", update_interface_owner, function(){ return; } );
                        } else {
                          update_interface_owner();
                        }
                      }
                    },
                    failure: function(req,resp){
                      throw("Error fetching interface");
                    }
                  }, this);
                }); //end row click
              });
            });
        });
    
    if (third_party_mgmt === 'n') {
    var add_workgroup = new YAHOO.widget.Button("add_workgroup_button", {label: "New Workgroup"});

    add_workgroup.on("click", function(){

        if (new_workgroup_panel) {
            new_workgroup_panel.destroy();
            new_workgroup_panel = undefined;
        }

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
        p.hideEvent.subscribe(function(){
            this.destroy();
        });

            p.setHeader("New Workgroup");
            p.setBody("Name: <input type='text' id='new_workgroup_name' size='38'><br /><br />" +
                                  "External ID: <input type='text' id='new_workgroup_external_id' size='33'><br /><br />"+
                                  "Workgroup Type: <select id='new_workgroup_type'>"+
                                  "<option value=\"normal\">Normal</option>"+
                                  "<option value=\"demo\">Demo</option>"+
                                  "<option value=\"admin\">Admin</option>"+
                                  "</select><br />");
            p.setFooter("<div id='submit_new_workgroup'></div>");

        new_workgroup_panel = p;
            new_workgroup_panel.render(document.body);

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

                    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=add_workgroup&name="+encodeURIComponent(workgroup_name)+"&external_id="+encodeURIComponent(external_id)+"&type="+encodeURIComponent(workgroup_type) );
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
                                               new_workgroup_panel.destroy();
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
}

function do_node_insert(link_id, map, delete_button, save_button, panel){
    showConfirm("This link has active circuits.  However there is a node in the middle of the path.  Would you like to automatically approve the new links and migrate all existing circuits onto the new paths?",
                function(){
                    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=insert_node_in_path&link_id=" + link_id);
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

                    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=decom_link&link_id="+link_id);
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

    var map = new NDDIMap("active_network_map", null, {circuit_type: null});

    map.on("loaded", function(){
            //this.showDefault();
            this.clearAllSelected();
        });

    legend_init(map,false,false,true,true);

    var panel, save_button, delete_button, maint_button;
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
                
            var url  = "../services/admin/admin.cgi?method=update_link&link_id="+link.link_id;
                url += "&name="+encodeURIComponent(new_name);
                    if(new_metric == 0){
                        new_metric = 1;
                    }
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
                    
                    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=is_ok_to_decom_link&link_id=" + link.link_id);
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
                                    do_decom_link(link.link_id,map,delete_button,save_button,panel);
                                }else{
                                    if(data.new_node_in_path == 0){
                                        alert('You can not decomission this link, there are active paths riding on it!');
                                    }else{
                                        do_node_insert(link.link_id,map,delete_button,save_button,panel);
                                    }
                                }
                            }});

                });
        };
    map.on("clickLink", function(e, args){
        YAHOO.util.Dom.get("active_network_update_status").innerHTML = "";

        var self = this;

        self.clearAllSelected();

        if (panel){
            panel.destroy();
            panel = null;
        }

        var init_link_panel = function(args) {

            var link_name = args[0].name;
            var link_id   = args[0].link_id;
            var feature   = args[0].feature;

            self.changeLinkColor(feature, self.LINK_PRIMARY);

            panel = new YAHOO.widget.Panel("link_details",{
                width: 500,
                draggable: false
            });
            panel.render(YAHOO.util.Dom.get("active_element_details"));

            panel.setHeader("Details for Link: " + link_name);
            panel.setBody("<p>Loading data...</p>");

            panel.setFooter("<div id='save_active_link'></div>" +
                            "<div id='delete_active_link'></div>" +
                            "<div id='maint_link'></div>");

            panel.hideEvent.subscribe(function(){
                map.clearAllSelected();
            });

            save_button   = new YAHOO.widget.Button("save_active_link", {label: "Update Link"});
            delete_button = new YAHOO.widget.Button("delete_active_link", {label: "Decomission Link"});
            maint_button    = new YAHOO.widget.Button("maint_link", {label: "Put Link into Maintenance"});

            if (args[0].feature.geometry.maint_epoch) {
                maint_button.set("disabled",true);
            }

            maint_button.on("click", function() {
                showConfirm("Putting the link into maintenance state will cause all circuits with an alternate path to change to that alternate path, causing a small forwarding disruption.  Circuits without an alternate path will continue to forward on this path while the link is up.  No restore to primary events will occur until the link is up and the maintenance has been completed. Are you sure you want to do this?",
                    function() {
                    maint_button.set("disabled",true);
                    var ds = new YAHOO.util.DataSource("../services/admin/maintenance.cgi?method=start_link&link_id=" + link_id);
                    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;

                    ds.responseSchema = {
                        resultsList: "results",
                        fields: [{key: "maintenance_id"}]
                        }; 

                    ds.sendRequest("", 
                           {
                               success: function(req, resp){
                               maint_button.set("disabled", false);
                               maint_button.set("label", "Put Link in Maintenance");

                               if (resp.results && resp.results[0].maintenance_id){
                                   map.reinitialize();
                                   panel.destroy();
                                   panel = null;
                                   YAHOO.util.Dom.get("active_network_update_status").innerHTML = "Link successfully put into maintenance.";
                                   setup_maintenance_tab();
                               }
                               else{
                                   alert("Link maintenance unsuccessful.");
                               }
                               
                               },
                               failure: function(req, resp){
                                   save_button.set("disabled", false);
                                   delete_button.set("disabled", false);
                                   delete_button.set("label", "Put Link in Maintenance");
                                   alert("Error while talking to server.");
                                }
                    }); 
                    
                    },
                    function(){}
                    );

            });

            var url =  "../services/data.cgi?method=get_link_by_name";
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
        };

        if(args[0].links.length > 1) {
            get_multilink_panel("multilink_panel", {
                on_change: function(oArgs){
                    var link_obj = [];
                    for(var i=0; i<this.links.length; i++){
                        if(this.links[i].link_name == oArgs.link) {
                            link_obj[0] = this.links[i];
                            link_obj[0].name = this.links[i].link_name;
                            link_obj[0].feature = this.feature;
                            break;
                        }
                    }
                    init_link_panel( link_obj );
                },
                links: args[0].links,
                feature: args[0].feature,
                render_location: YAHOO.util.Dom.get("active_network_map"),
                fixedcenter: false,
                already_used_check: false
            });
        } else {
            init_link_panel(args);
        }
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
            var short_name = args[0].short_name;
            var tx_delay_ms = args[0].tx_delay_ms;
            var default_drop = args[0].default_drop;
            var default_forward = args[0].default_forward;
            var barrier_bulk = args[0].barrier_bulk;
            var feature = args[0].feature;
            var dpid = convert_dpid_to_hex(args[0].dpid);
	    var max_static_mac_flows = args[0].max_static_mac_flows;
	    var end_epoch = args[0].feature.geometry.end_epoch;
	    var openflow = args[0].openflow;

            var mpls       = args[0].mpls;
            var mgmt_addr  = args[0].mgmt_addr;
            var tcp_port   = args[0].tcp_port;
            var vendor     = args[0].vendor;
            var model      = args[0].model;
            var sw_version = args[0].sw_version;
            var controller = args[0].controller;

	    function show_interface_acl_panel(args){
		var interface_id = args.interface_id;
		var interface_name = args.interface_name;
		var acl_panel = new YAHOO.widget.Panel("interface_acl_view_panel",{
			width: 675,
                centered: true,
			draggable: true
		    });
		
            acl_panel.setHeader("ACL Rules for: "+interface_name);
            acl_panel.setBody(
                "<div id='interface_acl_table_container'>" +
                    //"<a href='#add_acl'><div id='add_interface_acl'>Add Interface ACL</div></a>" +
                    "<div id='interface_acl_table' class='interface_acl_table'></div>" +
                    "<div id='interface_acl_table_actions' class='interface_acl_table'>" +
                    "<span class='yui-button yui-link-button'>" +
                        "<span id='add_interface_acl' class='first-child'>" +
                            "<a href='#add_acl'>Add ACL</a>" +
                        "</span>" +
                    "</span>" +
                    "</div>" +
                "</div>"
            );

            function build_interface_acl_table(interface_id){
                interface_acl_table = get_interface_acl_table("interface_acl_table", interface_id, {
                    url_prefix: "../",
                    on_show_edit_panel: function(oArgs){
                        var record = oArgs.record;
                        var interface_id = oArgs.interface_id;
                        get_interface_acl_panel("interface_acl_panel", interface_id, {
                            render_location: YAHOO.util.Dom.get("active_element_details"),  
                            url_prefix: "../",
                            is_edit: true,
                            record: record,
                            on_remove_success: function(){
                                build_interface_acl_table(interface_id);
                            },
                            on_add_edit_success: function(oArgs){
                                var interface_id = oArgs.interface_id;
                                build_interface_acl_table(interface_id);
                            }
                        });
                    }
                });
            
                return interface_acl_table;
            }


            acl_panel.hideEvent.subscribe(function(o) {
                setTimeout(function() {acl_panel.destroy();}, 0);
            });

            //panel.setFooter("<div id='cancel_interface_acl_panel'></div>");
            acl_panel.render(YAHOO.util.Dom.get("active_element_details"));
            var add_interface_acl = new YAHOO.util.Element('add_interface_acl');
            var oLinkButton1      = new YAHOO.widget.Button("add_interface_acl");
            add_interface_acl.on('click', function(){
                get_interface_acl_panel("interface_acl_panel", interface_id, {
                    render_location: YAHOO.util.Dom.get("active_element_details"),  
                    url_prefix: "../",
                    is_edit: false,
                    on_remove_success: function(){
                        var interface_acl_table = build_interface_acl_table(interface_id);
                    },
                    on_add_edit_success: function(oArgs){
                        //var interface_id = oArgs.interface_id;
                        var interface_acl_table = build_interface_acl_table(interface_id);
                    }
                });
            });
            build_interface_acl_table(interface_id);
        }

        function makeMoveConfigurationPanel(params) {
            var width = 450;
            var container_id = "int_move_panel";

            var move_int_form_creator = getMoveConfigurationForm(container_id, {
                orig_interface_id: params.orig_interface_id,
                node: params.node
            });

            var panel = new YAHOO.widget.Panel(container_id, {
                width: width,
                centered: true
            });
            panel.setHeader(`Move ${params.interface_name} configuration to:` );
            panel.setBody(`<div>${move_int_form_creator.markup()}</div>`);
            panel.setFooter("<div style='text-align: right;' id='move_edge_int_button'></div>");
            panel.render(YAHOO.util.Dom.get("active_element_details"));

            var move_int_form = move_int_form_creator.init();

            //hook up maint submission
            var add_button = new YAHOO.widget.Button("move_edge_int_button", {label: "Apply"});
            add_button.on('click', function(){
                var move_edge_int = function(){
                    add_button.set('label', 'Submitting...');
                    var url = "../services/admin/admin.cgi?";
                    var postVars = "method=move_interface_configuration"+
                                   "&orig_interface_id="+params.orig_interface_id+
                                   "&new_interface_id="+move_int_form.val().new_interface_id;

                    var ds = new YAHOO.util.DataSource(url, { connMethodPost: true } );
                    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                    ds.responseSchema = {
                        resultsList: "results",
                        fields: [
                            {key: "moved_circuits"},
                            {key: "unmoved_circuits"}
                        ],
                        metaFields: {
                            error: "error",
                            error_text: "error_text"
                        }
                    };
                    ds.sendRequest(postVars,{
                        success: function(req, resp){
                            add_button.set('label', 'Add');
                            if (resp.meta.error){
                                alert("Error moving circuits: " + resp.meta.error_text, null, {error: true});
                                return;
                            }
                            var res = resp.results[0];

                            var msg = `
                            <div>Interface configuration move succesful.</div>
                            <div class="success">
                              <ul>
                                <li>ACLs Moved</li>
                                <li>Cloud Configurations Moved</li>
                                <li>Layer2 Endpoints Moved</li>
                                <li>Layer3 Endpoints Moved</li>
                              </ul>
                            </div>
                            <div class="warning">
                            </div>
                            `;

                            panel.destroy();
                            alert(msg);
                            table.load();
                        },
                        failure: function(req, resp){
                            add_button.set('label', 'Add');
                            alert("Server error moving circuits.", null, {error: true});
                        }
                    });
                };
                var msg = "This will cause all selected circuits on this interface to be moved to the "+
                          "selected interface. Circuits with conflicting vlans will remain unmoved."+
                          "Are you sure this is what you want to do?";
                showConfirm(msg, move_edge_int, function(){});
            });

            panel.hideEvent.subscribe(function(){
                this.destroy();
            });
        }
        
        function make_node_intf_table(){
            var ds = new YAHOO.util.DataSource("../services/data.cgi?method=get_node_interfaces&show_down=1&show_trunk=1&node="+encodeURIComponent(node) );
            
                    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                    ds.responseSchema = {
                            resultsList: "results",
                            fields: [
		    {key: "name"},
		    {key: "description"},
		    {key: "vlan_tag_range"},
                    {key: "short_name"},
		    {key: "mpls_vlan_tag_range"},
		    {key: "interface_id", parser: "number"},
		    {key: "workgroup_id", parser: "number"},
                    {key: "workgroup_name"},
                            {key: "int_role"}
                                ],
                            metaFields: {
                                error: "error"
                            }
                    };
                        
            //define actions
            function aclInfoAction(rec){
                var interface_id   = rec.getData("interface_id");
                var interface_name = rec.getData("name");
                var workgroup_id   = rec.getData("workgroup_id");
                if(workgroup_id == null) {
                    alert("You must first add a workgroup as the owner of this interface");
                }else {
                    show_interface_acl_panel({
                        interface_id: interface_id,
                        interface_name: interface_name
                    });
                }
            }
            function moveConfigurationAction(rec){
                makeMoveConfigurationPanel({
                    align_container_id: rec.getId(),
                    orig_interface_id: rec.getData('interface_id'),
                    interface_name: rec.getData('name'),
                    node: node
                });
            }
            
                    var cols = [
				{key:'name', label: "Interface", width: 60},
				{key:'description', label: "Description", width: 200, 
				 editor: new YAHOO.widget.TextboxCellEditor({  
					 asyncSubmitter: function( callback, newValue) {
                                             var record = this.getRecord();
                                             var column = this.getColumn();
                                             var oldValue = this.value;
                                             YAHOO.util.Connect.asyncRequest(
									     'get','../services/admin/admin.cgi?method=update_interface&interface_id='+record.getData('interface_id')+'&description='+encodeURIComponent(newValue),{
										 success:function(o) {
										     var r = YAHOO.lang.JSON.parse(o.responseText);
										     table.destroy();
										     table = make_node_intf_table();
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
											     if(column.key=='mpls_vlan_tag_range' && target.firstChild.innerHTML != 'TRUNK'){
												 table.onEventShowCellEditor(ev);
											     }
											 });
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
				{key: 'vlan_tag_range', label: 'VLAN Tags', width: 180,
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
									     'get','../services/admin/admin.cgi?method=update_interface&interface_id='+record.getData('interface_id')+'&vlan_tag_range='+encodeURIComponent(newValue),{
										 success:function(o) {
										     var r = YAHOO.lang.JSON.parse(o.responseText);
										     table.destroy();
										     table = make_node_intf_table();
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
											     if(column.key=='mpls_vlan_tag_range' && target.firstChild.innerHTML != 'TRUNK'){
                                                                                                 table.onEventShowCellEditor(ev);
                                                                                             }
											 });
										 },
										     failure: function(o){
										     callback(false, oldValue);
										 },
										     scope:this
										     
										     }
									     
									     );
					 }
				     } )},
				{key: 'mpls_vlan_tag_range', label: 'MPLS VLAN Tags', width: 180,
                                 formatter: function(elLiner, oRec, oCol, oData){
                                        if(oRec.getData('int_role') == 'trunk'){
                                            elLiner.innerHTML = 'TRUNK';
                                        }else{
                                            elLiner.innerHTML = oRec.getData('mpls_vlan_tag_range');
                                        }
                                    },
				 
                                 editor:new YAHOO.widget.TextboxCellEditor({
                                         asyncSubmitter: function( callback, newValue) {
                                             var record = this.getRecord();
                                             var column = this.getColumn();
                                             var oldValue = this.value;
                                             YAHOO.util.Connect.asyncRequest(
                                                                             'get','../services/admin/admin.cgi?method=update_interface&interface_id='+record.getData('interface_id')+'&mpls_vlan_tag_range='+encodeURIComponent(newValue),{
                                                                                 success:function(o) {
                                                                                     var r = YAHOO.lang.JSON.parse(o.responseText);
                                                                                     table.destroy();
                                                                                     table = make_node_intf_table();
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
                                                                                             if(column.key=='mpls_vlan_tag_range' && target.firstChild.innerHTML != 'TRUNK'){
                                                                                                 table.onEventShowCellEditor(ev);
                                                                                             }
                                                                                         });
                                                                                 },
                                                                                     failure: function(o){
                                                                                     callback(false, oldValue);
                                                                                 },
                                                                                     scope:this

                                                                                     }

                                                                             );
                                         }
                                     } )},
                {key: "workgroup_name", label: "Workgroup", formatter: function(elLiner, oRec, oCol, oData){
                    if(oData === null){
                        elLiner.innerHTML = 'None';
                    }else {
                        elLiner.innerHTML = oData;
                    }
                }},
                {label: "Actions", width: 80, formatter: function(el, rec, col, data){
                    //create actions menu button
                    var menu_id  = YAHOO.util.Dom.generateId();//'action-menu-'+rec.getId();
                    var menu_div = $('<div />').attr('id', menu_id);
                    $(el).append(menu_div);
                    
                    this.on('postRenderEvent', function(){
                        
                        var menu = new YAHOO.widget.Menu(menu_id,{clicktohide:true});
                        var items = [
                            { text: 'View ACLs',     value: 'View ACLS', 'onclick': { fn: function(){
                                aclInfoAction(rec);
                            }}},
                            { text: 'Move Configuration', value: 'Move Configuration', 'onclick': { fn: function(){
                                moveConfigurationAction(rec);
                            }}}
                        ];
                        menu.addItems(items);
                        menu.render();
                        
                        var menu_button = new YAHOO.widget.Button({
                            type:     "menu",
                            label:    "Actions",
                            container: el,
                            menu: menu
                        });
                        if(rec.getData('int_role') == 'trunk'){
                            menu_button.setAttributes({'disabled': true});
                        }
                        menu_button.getMenu().cfg.config.clicktohide.value = true;
                    });
                }}
                    ];
                    
                    
                    
                    var configs = {
                            //height: "100px",
                paginator:  new YAHOO.widget.Paginator({
                    rowsPerPage: 3//,
                    //containers: ["owned_interfaces_table_nav"]
                })
                    };

                    return new YAHOO.widget.ScrollingDataTable("node_interface_table", cols, ds, configs);   
                }



            this.changeNodeImage(feature, this.ACTIVE_IMAGE);

            panel = new YAHOO.widget.Panel("node_details",
                                           { 
                                               width: 920,
                                               centered: true,
                                               draggable: true
                                           }
                                           );

            panel.setHeader("Details for Network Element: " + node);
        panel.setBody("<table style='width:100%'>" +
                      // Base
                      "<tr>" +
                        "<td colspan='4' class='soft_title'>Base System Description and Information</td>"+
                      "</tr>" +
                      // Base - Name, VLAN Range
                      "<tr>" +
                        "<td><label for='active_node_name'>Name:</label></td>" +
                        "<td><input type='text' size='38' id='active_node_name'></td>" +
                        "<td>Vlan Range:</td>" +
                        "<td><input type='text' id='active_node_vlan_range' size='10'></td>" +
                      "</tr>" +
                      // Base - Latitude, Longitude
                      "<tr>" +
                        "<td><label for='active_node_lat'>Latitude:</label></td>" +
                        "<td><input type='text' id='active_node_lat'></td>" +
                        "<td><label for='active_node_lon'>Longitude:</label></td>" +
                        "<td><input type='text' id='active_node_lon'></td>" +
                      "</tr>" +
                      // Base - OpenFlow Enabled, MPLS Enabled
	              "<tr>" + 
		        "<td></td>" +
		        "<td><input type='hidden' id='openflow_enabled' /></td>" + 
		        "<td><label for='mpls_enabled'>MPLS Enabled</label></td>" +
		        "<td><input type='checkbox' id='mpls_enabled' onchange='display_mpls(this);'checked /></td>" +
		      "</tr>" +
                      "<tr><td>&nbsp;</td></tr>" +
                      // OpenFlow
                      "<tr class='openflow'>" +
                        "<td colspan='4' class='soft_title'>OpenFlow Configuration</td>"+
                      "</tr>" +
                      // OpenFlow - DPID
                      "<tr class='openflow'>" +
                        "<td><label for='dpid_str'>DPID:</label></td>" +
                        "<td><label id='dpid_str'></label></td>" +
                        "<td></td>" +
                        "<td></td>" +
                      "</tr>" +
                      // OpenFlow
                      "<tr class='openflow'>" +
                        "<td>Maximum Number of Flow Mods</td>" +
                        "<td><input type='text' id='active_max_flows' size='10'></td>" +
                        "<td>Static MAC Limit</td>" +
                        "<td><input type='text' id='active_max_static_mac_flows' size='10'></td>" +
                      "</tr>" +
                      // OpenFlow
                      "<tr class='openflow'>" +
                        "<td>FlowMod Processing Delay (ms)</td>" +
                        "<td><input type='text' id='active_tx_delay_ms' size='10'></td>" +
                        "<td>Send Bulk Flow Rules</td>" +
                        "<td><input type='checkbox' id='active_barrier_bulk' checked></td>" +
                      "</tr>" +
                      // OpenFlow
                      "<tr class='openflow'>" +
                        "<td>Default Drop Rule</td>" +
                        "<td><input type='checkbox' id='active_node_default_drop' checked /></td>" +
                        "<td>Default Forward LLDP to controller</td>"+
                        "<td><input type='checkbox' id='active_node_default_forward' checked /></td>" +
                      "<tr>" +
                      "<tr class='openflow'><td>&nbsp;</td></tr>" +
                      // MPLS
                      "<tr class='mpls'>" +
                        "<td colspan='4' class='soft_title'>MPLS Configuration</td>"+
                      "</tr>" +
                      // MPLS - IP Address, TCP Port
                      "<tr class='mpls'>" +
                        "<td>IP Address</td>" +
                        "<td><input type='text' id='mgmt_addr'></td>" +
                        "<td>NetConf SSH Port</td>" +
                        "<td><input type='text' id='tcp_port'></td>" +
                      "</tr>" +
                      // MPLS - Vendor, Model
                      "<tr class='mpls'>" +
                        "<td>Vendor</td>" +
                        "<td><input type='text' id='vendor'></td>" +
                        "<td>Model</td>" +
                        "<td><input type='text' id='model'></td>" +
                      "</tr>" +
                      // MPLS - Software Version
                      "<tr class='mpls'>" +
                        "<td>Software Version</td>" +
                        "<td><input type='text' id='sw_version'></td>" +
                        "<td>Short Name:</td>" +
                        "<td><input type='text' id='short_name'></td>" +
                      "</tr>" +
                      // MPLS - Software Version
                      "<tr class='mpls'>" +
                        "<td>Southbound</td>" +
                        "<td><select style='min-width: 100%' id='controller'><option value='netconf'>NETCONF</option><option value='nso'>NSO</option></select></td>" +
                        "<td></td>" +
                        "<td></td>" +
                      "</tr>" +
                      "<tr class='mpls'><td>&nbsp;</td></tr>" +
                      "</table>" +
                      "<div style='font-weight: bold;color: grey;text-align:left'>Interfaces</div>"+
                      "<div id='node_interface_table' style='margin-top:8px;'> </div>");

            panel.setFooter("<div id='save_active_node'></div>" + 
                            "<div id='delete_active_node'></div>" +
                "<div id='maint_node'></div>");

            panel.hideEvent.subscribe(function(){
                    map.clearAllSelected();
                });

            panel.render(YAHOO.util.Dom.get("active_element_details"));
            
	    $('#controller').on('change', function() {
		if ($('#controller').val() == 'netconf') {
		    $('#vendor').prop('disabled', false);
		    $('#model').prop('disabled', false);
		    $('#sw_version').prop('disabled', false);
		} else {
		    $('#vendor').prop('disabled', true);
		    $('#model').prop('disabled', true);
		    $('#sw_version').prop('disabled', true);
		}
	    });

            var table = make_node_intf_table();
            
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
		    if(column.key=='mpls_vlan_tag_range' && target.firstChild.innerHTML != 'TRUNK'){
			table.onEventShowCellEditor(ev);
		    }
                });

            YAHOO.util.Dom.get('active_node_name').value            = node;
            YAHOO.util.Dom.get('active_node_lat').value             = lat;
            YAHOO.util.Dom.get('active_node_lon').value             = lon; 
            YAHOO.util.Dom.get('active_node_vlan_range').value      = vlan_range;
            YAHOO.util.Dom.get('active_tx_delay_ms').value          = tx_delay_ms;
            YAHOO.util.Dom.get('active_max_flows').value            = max_flows;
            YAHOO.util.Dom.get('dpid_str').innerHTML                = dpid;
            YAHOO.util.Dom.get('active_max_static_mac_flows').value = max_static_mac_flows;
            YAHOO.util.Dom.get('short_name').value = short_name;

	    if (openflow == 0 || openflow == null) {
                YAHOO.util.Dom.get('openflow_enabled').value = false;

                var elements = YAHOO.util.Dom.getElementsByClassName('openflow');
                for (var i = 0; i < elements.length; i++) {
                    elements[i].style.display = 'none';
                }
            } else {
                YAHOO.util.Dom.get('openflow_enabled').value = true;

                var elements = YAHOO.util.Dom.getElementsByClassName('openflow');
                for (var i = 0; i < elements.length; i++) {
                    elements[i].style.display = 'table-row';
                }
            }

	    if (mpls == 0 || mpls == null) {
		YAHOO.util.Dom.get('mpls_enabled').checked = false;

                var elements = YAHOO.util.Dom.getElementsByClassName('mpls');
                for (var i = 0; i < elements.length; i++) {
                    elements[i].style.display = 'none';
                }
	    } else {
                YAHOO.util.Dom.get('mpls_enabled').checked = true;

                var elements = YAHOO.util.Dom.getElementsByClassName('mpls');
                for (var i = 0; i < elements.length; i++) {
                    elements[i].style.display = 'table-row';
                }

                YAHOO.util.Dom.get('mgmt_addr').value  = mgmt_addr;
                YAHOO.util.Dom.get('tcp_port').value   = tcp_port;
                YAHOO.util.Dom.get('vendor').value     = vendor;
                YAHOO.util.Dom.get('model').value      = model;
                YAHOO.util.Dom.get('sw_version').value = sw_version;
                YAHOO.util.Dom.get('controller').value = controller;

		if (controller == 'nso') {
		    YAHOO.util.Dom.get('vendor').disabled     = true;
		    YAHOO.util.Dom.get('model').disabled      = true;
		    YAHOO.util.Dom.get('sw_version').disabled = true;
		}
            }

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
            var maint_button = new YAHOO.widget.Button("maint_node", {label: "Put Device in Maintenance"});
           
        if (end_epoch == -1) {
           maint_button.set("disabled",true); 
        }

        save_button.on("click", function(){
		showConfirm("The new values will take effect immediately.Are you sure you want to update the device?",
			    function(){
				var new_name  = YAHOO.util.Dom.get('active_node_name').value;
				var new_lat   = YAHOO.util.Dom.get('active_node_lat').value;
				var new_lon   = YAHOO.util.Dom.get('active_node_lon').value;
				var new_range = YAHOO.util.Dom.get('active_node_vlan_range').value;
				var new_max_flows = YAHOO.util.Dom.get('active_max_flows').value;
				var new_tx_delay_ms = YAHOO.util.Dom.get('active_tx_delay_ms').value;
				var new_default_drop = YAHOO.util.Dom.get('active_node_default_drop').checked;
				var new_default_forward = YAHOO.util.Dom.get('active_node_default_forward').checked;
				var new_barrier_bulk = YAHOO.util.Dom.get('active_barrier_bulk').checked;
				var new_max_static_mac_flows = YAHOO.util.Dom.get('active_max_static_mac_flows').value;
				var openflow   = YAHOO.util.Dom.get('openflow_enabled').value;
				var mpls       = YAHOO.util.Dom.get('mpls_enabled').checked;
                var mgmt_addr  = YAHOO.util.Dom.get('mgmt_addr').value;
                var tcp_port   = YAHOO.util.Dom.get('tcp_port').value;
                var vendor     = YAHOO.util.Dom.get('vendor').value;
                var model      = YAHOO.util.Dom.get('model').value;
                var sw_version = YAHOO.util.Dom.get('sw_version').value;
                var controller = YAHOO.util.Dom.get('controller').value;
                var short_name = YAHOO.util.Dom.get('short_name').value;

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
            
				if(! new_max_static_mac_flows || ! new_max_static_mac_flows.match(/\d+/) ) {
				    alert("The max mac rules limit must be an integer.");
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

                                var args = "&node_id=" + node_id +
                                    "&name="       + encodeURIComponent(new_name) +
                                    "&latitude="   + new_lat +
                                    "&longitude="  + new_lon +
                                    "&vlan_range=" + encodeURIComponent(new_range) +
                                    "&mpls="       + encodeURIComponent(mpls) +
                                    "&openflow="   + encodeURIComponent(openflow);

                                var mpls_args = "&mgmt_addr=" + encodeURIComponent(mgmt_addr) +
                                    "&tcp_port="   + encodeURIComponent(tcp_port) +
                                    "&vendor="     + encodeURIComponent(vendor) +
                                    "&model="      + encodeURIComponent(model) +
                                    "&sw_version=" + encodeURIComponent(sw_version) +
                                    "&controller=" + encodeURIComponent(controller) +
                                    "&short_name=" + encodeURIComponent(short_name);

                                var openflow_args = "&default_drop=" + encodeURIComponent(new_default_drop) +
                                    "&default_forward=" + encodeURIComponent(new_default_forward) +
                                    "&max_flows="       + encodeURIComponent(new_max_flows) +
                                    "&tx_delay_ms="     + encodeURIComponent(new_tx_delay_ms) +
                                    "&bulk_barrier="    + encodeURIComponent(new_barrier_bulk) +
                                    "&max_static_mac_flows=" + encodeURIComponent(new_max_static_mac_flows);

                                if (mpls) {
                                    args += mpls_args;
                                }

                                if (openflow) {
                                    args += openflow_args;
                                }

				var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=update_node" + args);

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
		    
		    
			    },
			    function(){}
			    );
	    });
	    delete_button.on("click", function(){

		    showConfirm("Decomissioning this device will remove it and all links going to it. This will not impact existing circuits going across it presently, but you will not be able to add any more circuits that traverse this device. Are you sure you wish to continue?", 
				function(){

				    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=decom_node&node_id="+node_id);	
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

        maint_button.on("click", function() {
            showConfirm("Putting the node into maintenance will have the links it is connected to have their associated circuits change to that alternative path, causing a small forwarding disruption. Circuits without an alternate path will continue to forward on this path while the link is up. No restore to primary events will occur until the link is up and the maintenance has been completed. Are you sure you want to do this?",
                function() {

                    var ds = new YAHOO.util.DataSource("../services/admin/maintenance.cgi?method=start_node&node_id=" + node_id);
                    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;

                    ds.responseSchema = {
                        resultsList: "results",
                        fields: [{key: "maintenance_id"}],
                        metaFields: {
                            error: "error",
                            error_text: "error_text"
                        }
                        }; 

                    ds.sendRequest("", 
                           {
                               success: function(req, resp){
                               maint_button.set("disabled", false);
                               maint_button.set("label", "Put Device in Maintenance");
                               save_button.set("disabled", false);

                               if (resp.meta.error) {
                                   var err_txt = resp.meta.error_text;
                                   if (!YAHOO.lang.isString(err_txt)) err_txt = resp.meta.error;
                                   if (!YAHOO.lang.isString(err_txt)) err_txt = "Error putting device into maintenance.";
                                   alert(err_txt);
                               }
                               else if (resp.results && resp.results[0].maintenance_id){
                                   map.reinitialize();
                                   panel.destroy();
                                   panel = null;
                                   YAHOO.util.Dom.get("active_network_update_status").innerHTML = "Device successfully put into maintenance.";
                                   setup_maintenance_tab();
                               }
                               else{
                                   alert("Device maintenance unsuccessful.");
                               }
                               
                               },
                               failure: function(req, resp){
                                   save_button.set("disabled", false);
                                   setup_maintenance_tab();
                                   delete_button.set("disabled", false);
                                   delete_button.set("label", "Put Device in Maintenance");
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

    var add_mpls_switch_button = new YAHOO.widget.Button("add_mpls_switch_button", {label: "Add MPLS switch button"});

    add_mpls_switch_button.on("click", function(e){

	    var new_mpls_switch_details_panel = new YAHOO.widget.Panel("new_switch_details",
						       {width: 600,
							fixedcenter: true,
							modal: true
						       }
						       );

	    this.new_mpls = new_mpls_switch_details_panel;

            this.new_mpls.setHeader("Details for new Device!");

            this.new_mpls.setBody("<table>" +
				  "<tr>" +
				  "<td>Name:</td>" +
				  "<td>" +
				  "<input type='text' id='new_node_name' size='38'>" +
				  "</td>" +
				  "</tr>" +
				  "<tr>" +
				  "<td>Short Name:</td>" +
				  "<td>" +
				  "<input type='text' id='new_node_short_name' size='38'>" +
				  "</td>" +
				  "</tr>" +
				  "<tr>" +
				  "<td>Latitude:</td>" +
				  "<td><input type='text' id='new_node_lat' size='20'></td>" +
				  "<td>Longitude:</td>" +
				  "<td><input type='text' id='new_node_lon' size='20'></td>" +
				  "</tr>" +
				  "<tr>" +
				  "<td>IP Address</td>" +
				  "<td><input type='text' id='new_ip_address' size='38'></td>" +
				  "</tr>" +
                                  "<td>Port</td>" +
                                  "<td><input type='text' id='new_port' size='38'></td>" +
                                  "</tr>" +
				  "<td>Southbound</td>"+
				  "<td colspan='1'><select style='min-width: 100%' id='controller'><option value='netconf' selected>NETCONF</option><option value='nso'>NSO</option></select></td>" +
				  "</tr>" +
				  "<td>Vendor</td>"+
				  "<td colspan='1'><select style='min-width: 100%' id='new_mpls_vendor'><option value=''>Select One...</option><option value='Juniper'>Juniper</option></select></td>" +
				  "</tr>" +
				  "<tr>" +
				  "<td>Model</td>" +
				  "<td colspan='1'><select style='min-width: 100%' id='new_mpls_model'><option value=''>Select a vendor first</option></select></td>" +
				  "</td>" +
				  "</tr>" +
				  "<tr>" +
				  "<td>Software Version</td>" +
				  "<td><input type='text' id='new_mpls_software' size='38'></td>" +
				  "</tr>" +
				  "</table>"
				  );

            this.new_mpls.setFooter("<div id='add_node'></div><div id='node_add_cancel'></div>");

            this.new_mpls.render(document.body);

	    $('#controller').on('change', function() {
		if ($('#controller').val() == 'netconf') {
		    $('#new_mpls_vendor').prop('disabled', false);
		    $('#new_mpls_model').prop('disabled', false);
		    $('#new_mpls_software').prop('disabled', false);
		} else {
		    $('#new_mpls_vendor').prop('disabled', true);
		    $('#new_mpls_model').prop('disabled', true);
		    $('#new_mpls_software').prop('disabled', true);
		}
	    });

	    $('#new_mpls_vendor').on('change', function(){
		    var vendor = $('#new_mpls_vendor').val();
		    if(vendor == 'Juniper'){
			var options = {"MX": "MX", "qfx": "QFX"};
			var $el = $("#new_mpls_model");
			$el.empty();
		        $.each(options, function(value, key){
			   $el.append($("<option></option>").attr("value", value).text(key));
			});
		    }else if( vendor == 'Brocade'){

		    }
		});

            var add_button = new YAHOO.widget.Button("add_node", {label: "Add Switch"});
	    var cancel_button = new YAHOO.widget.Button("node_add_cancel", {label: "Cancel"});

	    add_button.on('click', function(){
                    
		    var lat   = YAHOO.util.Dom.get('new_node_lat').value;
                    var lon   = YAHOO.util.Dom.get('new_node_lon').value;
                    var name  = YAHOO.util.Dom.get('new_node_name').value;
                    var short_name = YAHOO.util.Dom.get('new_node_short_name').value;
		    var ip    = YAHOO.util.Dom.get('new_ip_address').value;
		    var port  = YAHOO.util.Dom.get('new_port').value;
		    var controller = YAHOO.util.Dom.get('controller').value;
		    var vendor = $('#new_mpls_vendor').prop('disabled')   ? null : YAHOO.util.Dom.get('new_mpls_vendor').value;
		    var model  = $('#new_mpls_model').prop('disabled')    ? null : YAHOO.util.Dom.get('new_mpls_model').value;
		    var sw_ver = $('#new_mpls_software').prop('disabled') ? null : YAHOO.util.Dom.get('new_mpls_software').value;

		    if (! name){
                        alert("You must specify a name for this device.");
                        return;
                    }

		    if( !ip || !port ){
			alert('You must specify and IP, SSH port, and password');
			return;
		    }

		    if (!ip.match(/^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$/)) {
		        alert("You must specify a valid IPv4 Address.");
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

		    if (controller === 'netconf' && (vendor === '' || model === '' || sw_ver === '')) {
			alert('Hardware vendor, model, and software version are required for NETCONF controlled devices.');
			return;
		    }

		    add_button.set("disabled", true);
		    add_button.set("label", "Adding device....");

                var url = "../services/admin/admin.cgi?method=add_mpls_switch";
                url += `&name=${encodeURIComponent(name)}`;
                url += `&short_name=${encodeURIComponent(short_name)}`;
                url += `&latitude=${encodeURIComponent(lat)}`;
                url += `&longitude=${encodeURIComponent(lon)}`;
                url += `&ip_address=${encodeURIComponent(ip)}`;
                url += `&port=${encodeURIComponent(port)}`;
                url += `&controller=${encodeURIComponent(controller)}`;
                if (vendor) url += `&vendor=${encodeURIComponent(vendor)}`;
                if (model) url += `&model=${encodeURIComponent(model)}`;
                if (sw_ver) url += `&sw_ver=${encodeURIComponent(sw_ver)}`;

		var ds = new YAHOO.util.DataSource(url);
		ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
		    
                ds.responseSchema = {
                      resultsList: "results",
                      fields: [{key: "success"}],
                      metaFields: { 
                        error: "error", 
                        error_text: "error_text" 
                      } 
                    };
		    
                    ds.sendRequest("", {success: function(req, resp) {
                      if (resp.meta.error) { 
                        alert(`Error creating Switch: ${resp.meta.error_text}`); 
                        add_button.set("disabled", false); 
                        add_button.set("label", "Add Switch"); 
                        return; 
                      }
				add_button.set("disabled", false);
				add_button.set("label", "Add MPLS Device");

				new_mpls_switch_details_panel.hide();
				setup_network_tab();				
			    },
				
				failure: function(req, resp){
				add_button.set("disabled", false);
				add_button.set("label", "Add MPLS Device");
				
				alert("Server error while adding MPLS device");
			    }
			});
		});
	});


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

            this.details_panel.setHeader("Details for Device: " + convert_dpid_to_hex(record.getData('dpid')));

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

            this.details_panel.setFooter("<div id='confirm_node'></div><div id='deny_node'></div>");

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

            if(record.getData('short_name')){
                YAHOO.util.Dom.get('short_name').value = record.getData('short_name');
            }

            if(record.getData('tx_delay_ms')){
                YAHOO.util.Dom.get('tx_delay_ms').checked = record.getData('tx_delay_ms');
            }

            if(record.getData('bulk_barrier')){
                YAHOO.util.Dom.get('bulk_barrier').checked = record.getData('bulk_barrier');
            }
            
            YAHOO.util.Dom.get("node_name").focus();

            var confirm_button = new YAHOO.widget.Button("confirm_node", {label: "Confirm Device"});
	    var deny_button = new YAHOO.widget.Button("deny_node", {label: "Deny Device"});
	    
	    deny_button.on("click", function(e){
            
                    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=deny_device&node_id=" + record.getData('node_id') + "&ipv4_addr="+ record.getData('ip_address') + "&dpid=" + record.getData('dpid'));
                    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                 
                    ds.responseSchema = {
                        resultsList: "results",
                        fields: [{key: "success"}]
                    };
         
                    deny_button.set("disabled", true);
                    deny_button.set("label", "Denying device...");

                    YAHOO.util.Dom.get("node_confirm_status").innerHTML = "";
                    YAHOO.util.Dom.get("node_confirm_status").innerHTML = "";
            ds.sendRequest("", {success: function(req, resp){

                                deny_button.set("disabled", false);
                                deny_button.set("label", "Deny Device");

                                if (resp.results && resp.results[0].success == 1){
                                    YAHOO.util.Dom.get("node_confirm_status").innerHTML = "Device successfully denied.";
                                    node_table.deleteRow(record);
                                    details_panel.hide();
                                    setup_network_tab();
                                }
                                else{
                                    alert("Device denial unsuccessful.")
                                }
                            },
                            failure: function(req, resp){
                                deny_button.set("disabled", false);
                                deny_button.set("label", "Deny Device");

                                alert("Server error while denying device.");
                            }
                        });

        }); 

            confirm_button.on("click", function(e){

                    var lat   = YAHOO.util.Dom.get('node_lat').value;
                    var lon   = YAHOO.util.Dom.get('node_lon').value;
                    var name  = YAHOO.util.Dom.get('node_name').value;
                    var range = YAHOO.util.Dom.get('vlan_range').value;
                    var default_drop = YAHOO.util.Dom.get('default_drop').checked;
                    var default_forward = YAHOO.util.Dom.get('default_forward').checked;
                    var max_flows = YAHOO.util.Dom.get('max_flows').value;
                    var tx_delay_ms = YAHOO.util.Dom.get('tx_delay_ms').value;
                    var bulk_barrier = YAHOO.util.Dom.get('bulk_barrier').checked;
                    
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

                    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=confirm_node&node_id=" + record.getData('node_id') + "&name=" + encodeURIComponent(name) + "&latitude=" + encodeURIComponent(lat) + "&longitude=" + encodeURIComponent(lon) + "&vlan_range=" + encodeURIComponent(range) + "&default_drop=" + encodeURIComponent(default_drop) + "&default_forward=" + encodeURIComponent(default_forward) + "&max_flows=" + encodeURIComponent(max_flows) + "&tx_delay_ms=" + encodeURIComponent(tx_delay_ms) + "&bulk_barrier=" + encodeURIComponent(bulk_barrier));

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

function setup_maintenance_tab(){    

    if (link_maint_table) {
        link_maint_table = undefined;
    }

    link_maint_table = makeLinkMaintenanceTable();   

    if (node_maint_table) { 
        node_maint_table = undefined;
    }

    node_maint_table = makeNodeMaintenanceTable(); 
}

function makeNodeMaintenanceTable() {

    var url = "../services/admin/maintenance.cgi?method=nodes";
    var ds  = new YAHOO.util.DataSource(url);
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
        resultsList: "results",
        fields: [
            {key: "node"},
            {key: "description", parser: "number"},
            {key: "start_epoch", parser: "number"},
            {key: "end_epoch", parser: "number"},
            {key: "maintenance_id", parser: "number"},
        ]
    };

    var columns = [
        {key: "node", label: "Node", sortable:true, formatter: function(el,rec,col,data) {
                if (rec) {
                    el.innerHTML = rec._oData.node.name;
                } 
        }                
        },
        {key: "description", label: "Description", sortable:true },
        {key: "start_epoch", label: "Activated On", formatter: function(el, rec, col, data){
            el.innerHTML = new Date(data * 1000 ).toLocaleString(); 
        }, sortable: true},
        {label: "Complete", formatter: function(el, rec, col, data){
            var b = new YAHOO.widget.Button({label: "Complete"});
            var bid = b.get('id');
            b.appendTo(el);
            b.on("click", function(){
                var maintComplete = function(node, table){
                    var node_id = node.id;
                    b.set('label', 'Submitting...');
                                    b.set("enable", false);
                    var url = "../services/admin/maintenance.cgi?method=end_node"+
                              "&node_id="+node_id;
                      
                    var ds = new YAHOO.util.DataSource(url);
                    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                    ds.responseSchema = {
                        resultsList: "results",
                        fields: [
                            {key: "maintenance_id"}
                        ],
                        metaFields: {
                            error: "error"
                        }
                    };
                    ds.sendRequest("",{
                        success: function(req, resp){
                            if (resp.meta.error){
                                b.set('label', 'Complete');
                                b.set("enabled", true);
                                alert("Error submitting maintenance completion: " + resp.meta.error, null, {error: true});
                                return;
                            }
                            var res = resp.results[0];
                                            setup_network_tab();
                            table.load();
                        },
                        failure: function(req, resp){
                            b.set('label', 'Complete');
                            b.set('enabled',"true");
                            alert("Server error submitting maintenance completion", null, {error: true});
                        }
                    });
                };
                var msg = "This will end the node maintenance for this node. Are you sure you wish to do this?";
                showConfirm(msg,
                    $.proxy(function(){
                        maintComplete(rec.getData("node"), this);
                    },this),
                    function(){}
                );
            },null,this);
        }, sortable: true}
    ];

    var config = {
        paginator:  new YAHOO.widget.Paginator({
            rowsPerPage: 10,
            containers: ["owned_interfaces_table_nav"]
        })
    };

    var table = new YAHOO.widget.DataTable("node_maint_table", columns, ds, config);
    table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
    table.subscribe("rowMouseoutEvent",  table.onEventUnhighlightRow);

    return table;
}

function makeLinkMaintenanceTable(){
    var url = "../services/admin/maintenance.cgi?method=links";
    var ds  = new YAHOO.util.DataSource(url);
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
        resultsList: "results",
        fields: [
            {key: "link"},
            {key: "description", parser: "number"},
            {key: "start_epoch", parser: "number"},
            {key: "end_epoch", parser: "number"},
            {key: "maintenance_id", parser: "number"},
        ]
    };

    var columns = [
        {key: "link", label: "Link", sortable:true, formatter: function(el,rec,col,data) { 
                if (rec) {
                    el.innerHTML = rec._oData.link.name;
                } 
        }                
        },
        {key: "start_epoch", label: "Activated On", formatter: function(el, rec, col, data){
            el.innerHTML = new Date(data * 1000 ).toLocaleString(); 
        }, sortable: true},
        {label: "Complete", formatter: function(el, rec, col, data){
            var b = new YAHOO.widget.Button({label: "Complete"});
            var bid = b.get('id');
            b.appendTo(el);
            b.on("click", function(){
                var maintComplete = function(link, table){
                    var link_id = link.id;
                    b.set('label', 'Submitting...');
                    b.set('enabled',"false");
                    var url = "../services/admin/maintenance.cgi?method=end_link"+
                              "&link_id="+link_id;
                    var ds = new YAHOO.util.DataSource(url);
                    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                    ds.responseSchema = {
                        resultsList: "results",
                        fields: [
                            {key: "maintenance_id"}
                        ],
                        metaFields: {
                            error: "error"
                        }
                    };
                    ds.sendRequest("",{
                        success: function(req, resp){
                            if (resp.meta.error){
                                b.set('label', 'Complete');
                                alert("Error submitting maintenance completion: " + resp.meta.error, null, {error: true});
                                 b.set('enabled',"true");
                                return;
                            }
                            var res = resp.results[0];
                                            setup_network_tab();
                            table.load();
                        },
                        failure: function(req, resp){
                            b.set('label', 'Complete');
                            b.set('enabled',"true");
                            alert("Server error submitting maintenance completion", null, {error: true});
                        }
                    });
                };
                var msg = "This will end the link maintenance for this link. Are you sure you wish to do this?";
                showConfirm(msg,
                    $.proxy(function(){
                        maintComplete(rec.getData("link"), this);
                    },this),
                    function(){}
                );
            },null,this);
        }, sortable: true}
    ];

    var config = {
        paginator:  new YAHOO.widget.Paginator({
            rowsPerPage: 10,
            containers: ["owned_interfaces_table_nav"]
        })
    };

    var table = new YAHOO.widget.DataTable("link_maint_table", columns, ds, config);
    table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
    table.subscribe("rowMouseoutEvent",  table.onEventUnhighlightRow);

    return table;
}

function getMoveConfigurationForm(container_id, config){
    config = config || {};
    var selector_ids = {
        node: container_id+'_mei_node_selector',
        oint: container_id+'_mei_oint_selector',
        nint: container_id+'_mei_nint_selector'
    };
    var ckt_select_container_id = container_id+"_circuit_select_container";
    var ckt_toggle_id           = container_id+"_circuit_select_toggle";
    var ckt_options_table_id    = container_id+"_circuit_options_table"; 
    var ckt_selected_table_id   = container_id+"_circuit_selected_table";

    var markup = function(){
        let nodeSelector = `
        <div>
          <p>Node:</p>
          <select id="${selector_ids.node}"></select>
        </div>
        `;

        let ointSelector = `
        <div>
          <p>Original Interface:</p>
          <select id="${selector_ids.oint}"></select>
        </div>
        `;

        let markup = `
        <div class="move_edge_int_form">
          <p><b>Warning:</b> Moving this interface's configuration will move all layer2 circuits,
             all layer3 circuits, all ACLs, all Cloud Interconnect information, and will trigger
             a diff of the affected node.</p>
          <br/>

          ${(!config.node)              ? nodeSelector : ''}
          ${(!config.orig_interface_id) ? ointSelector : ''}
          <div>
            <p>New Interface:</p>
            <select id="${selector_ids.nint}"></select>
          </div>
          <div class="yui-buttongroup" id="${ckt_toggle_id}">
            <input type="radio" value="Move Configuration" checked>
          </div>
        </div>
        <!-- TODO remove circuit selector -->
        <div class="ckt_table_holder" id="${ckt_select_container_id}">
          <!-- <p class="subtitle">Circuits on Original Interface</p> -->
          <div id="${ckt_options_table_id}"></div>
          <!-- <p class="subtitle">Selected Circuits</p> -->
          <div id="${ckt_selected_table_id}"></div>
        </div>
        `;

        return markup;
    };

    //function to update placeholder messages for selectors
    var updatePlaceholder = function(selector_type, msg, disable){
        disable = disable || false;
        $('#'+selector_ids[selector_type]).attr('data-placeholder', msg);
        $('#'+selector_ids[selector_type]).prop('disable', disable);
        $('#'+selector_ids[selector_type]).trigger("liszt:updated");
    };

    //adds options to a selector
    var addOptions = function(selector_type, options){
        //if null was passed in for the options set loading message and clear 
        //current options
        if(options === null){
            $('#'+selector_ids[selector_type]).empty();
            updatePlaceholder(selector_type, "Loading...");
        }else {
            $.each(options, function(i, option){
                var opt = '<option value="'+option.value+'">'+option.name+'</option>';
                $('#'+selector_ids[selector_type]).append(opt);
            });
            updatePlaceholder(selector_type, "Choose One");
        }
        $('#'+selector_ids[selector_type]).trigger("change");
    };

    //gets options for a selector
    var getOptions = function(selector_types, obj){
        var url;
        if ((selector_types.length === 1) && (selector_types[0] === "node")) {
            url = "../services/data.cgi?method=get_nodes";
        } else {
            url = "../services/data.cgi?method=get_node_interfaces"+
                  "&show_down=1"+
                  "&show_trunk=0"+
                  "&node="+obj.node;
        }
        var ds = new YAHOO.util.DataSource(url);
        ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
        ds.responseSchema = {
            resultsList: "results",
            fields: [
                {key: obj.fields.name},
                {key: obj.fields.value}
            ],
            metaFields: {
                error: "error"
            }
        };
        ds.sendRequest("",{
            success: function(req, resp){
                if (resp.meta.error){
                    $.each(selector_types, function(i, selector_type){ 
                        updatePlaceholder(selector_type, "Data Error");
                    });
                    return;
                }
                var options = [];
                $.each(resp.results, function(i, result){
                    options.push({
                        value: result[obj.fields.value],
                        name:  result[obj.fields.name]
                    });
                });
                $.each(selector_types, function(i, selector_type){ 
                    addOptions(selector_type, null);
                    addOptions(selector_type, options);
                });
            },
            failure: function(req, resp){
                $.each(selector_types, function(i, selector_type){ 
                    updatePlaceholder(selector_type, "Data Error");
                });
            }
        });
    };

    var isAllCircuits;
    var init = function(){

        //set up circuit selection toggle
        var circuit_toggle = new YAHOO.widget.ButtonGroup(ckt_toggle_id);

        var isAllCircuits = function(){
            var value;
            $.each(circuit_toggle.getButtons(), function(i, button){
                if (button.get('checked')) {
                    value = (button.get('value') === 'Move Configuration') ? true : false;
                }
            });
            return value;
        };

        //set loading messages and init chosen selectors
        $.each(selector_ids, function(type, selector_id){
            if ((type === 'node') && config.node) {
                return true;
            }
            if ((type === 'oint') && config.orig_interface_id) {
                return true;
            }
            updatePlaceholder(type, "Loading...", true);
            $('#'+selector_id).chosen();
        });

        //on node change event fetch interface options
        $('#'+selector_ids.node).on('change', function(){
            var types = ['oint', 'nint'];
            //clear current options
            $.each(types, function(i, type){
                addOptions(type, null);
            });

            //fetch new ones
            getOptions(types, {
                node: $('#'+selector_ids.node).chosen().val(),
                fields:  { 
                    name:  'name',
                    value: 'interface_id'
                }
            });
        });
    
        // get the node options
        if (config.node) {
            var types = ['nint'];
            if (!config.orig_interface_id) {
                types.push('oint');
            }
            //fetch new ones
            getOptions(types, {
                node: config.node,
                fields:  { 
                    name:  'name',
                    value: 'interface_id'
                }
            });
        } else {
            getOptions(['node'], {
                fields: {
                    name:  'name',
                    value: 'name'
                }
            });
        }

        var val = function() {
            var orig_interface_id;
            if (config.orig_interface_id) {
                orig_interface_id = config.orig_interface_id;
            } else {
                orig_interface_id = $('#'+selector_ids.oint).chosen().val();
            }
            return {
                orig_interface_id: orig_interface_id,
                new_interface_id:  $('#'+selector_ids.nint).chosen().val()
            };
        };
        return { val: val };
    };

    return {
        markup: markup,
        init:   init
    };
}

function makeOwnedInterfaceTable(id){
    var ds = new YAHOO.util.DataSource("../services/data.cgi?method=get_workgroup_interfaces&workgroup_id="+id);

    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
        resultsList: "results",
        fields: [{key: "node_id", parser: "number"},
                 {key: "interface_id", parser: "number"},
                 {key: "description"},
                 {key: "node_name"},
                 {key: "interface_name"},
                 ]
    };

    var columns = [{key: "node_name", label: "Endpoint", width: 180 ,sortable:true},
                                   {key: "interface_name", label: "Interface", width: 60 ,sortable:true},         
                   {key: "description", label: "Description", width: 140},
                   {label: "Remove", formatter: function(el, rec, col, data){
                                           var b = new YAHOO.widget.Button({label: "Remove"});
                                                  b.appendTo(el);
                                                }
                   }
                   ];

    var config = {
                sortedBy: {key:'node_name', dir:'asc'},
                paginator:  new YAHOO.widget.Paginator({rowsPerPage: 10,
                                                                                                containers: ["owned_interfaces_table_nav"]
            })
    };

    var table = new YAHOO.widget.DataTable("owned_interfaces_table", columns, ds, config);
        
    table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
    table.subscribe("rowMouseoutEvent", table.onEventUnhighlightRow);

    return table;

}

function makeWorkgroupUserTable(id){

    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=get_users_in_workgroup&workgroup_id="+id);

    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
        resultsList: "results",
        fields: [{key: "user_id", parser: "number"},
                 {key: "first_name"},
                 {key: "last_name"},
                 {key: "email_address"},
                 {key: "auth_name"}
                 ]
    };

    var columns;
    if (third_party_mgmt === 'n') {
        columns = [{key: "first_name", label: "Name", width: 140,
                    formatter: function(el, rec, col, data){
                                    el.innerHTML = rec.getData("first_name") + " " + rec.getData("last_name");
                               }
                   },
                   {label: "Remove", formatter: function(el, rec, col, data){
                                                   var b = new YAHOO.widget.Button({label: "Remove"});
                                                   b.appendTo(el);
                                                }
                   }
                   ];
    } else {
         columns = [{key: "first_name", label: "Name", width: 140,
                    formatter: function(el, rec, col, data){
                                    el.innerHTML = rec.getData("first_name") + " " + rec.getData("last_name");
                               }
                   }
                   ];
    }
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
    
    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=get_users");
    
    
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
            resultsList: "results",
            fields: [{key: "user_id", parser: "number"},
                 {key: "first_name"},
                 {key: "family_name"},
                 {key: "email_address"},
                 {key: "auth_name"},
                 {key: "type"},
                 {key: "status"}
                        ]
    };
    
    var columns = [{key: "first_name", label: "First Name", width: 100,sortable:true
                            /*formatter: function(el, rec, col, data){
                              el.innerHTML = rec.getData("first_name") + " " + rec.getData("family_name");
                          }*/
                       },
                                   {key: "family_name",label:"Last Name", width: 100,sortable:true },
                                   {key: "auth_name", label: "Username", width: 175,sortable:true},
                   {key: "email_address", label: "Email Address", width: 175,sortable:true},
                   {key: "type", label: "User Type", width: 90, sortable: true},
                   {key: "status", label: "User Status", wdith: 90, sortable: true}
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

function makeUserWorkgroupTable(user_id,first_name,family_name) {

    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=get_workgroups&user_id="+user_id);

    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
    resultsList: "results",
    fields: [ {key: "workgroup_id", parser: "number"},
        {key: "name"},
        {key: "description"},
        {key: "external_id"},
        {key: "max_mac_address_per_end"},
        {key: "max_circuit_endpoints"},
        {key: "max_circuits"}
    ]};

    var columns = [{key: "name", label: "Name", sortable:true,width: 180},
                     {label: "Remove", formatter: function(el, rec, col, data){
                                                   var b = new YAHOO.widget.Button({label: "Remove"});
                                                   b.appendTo(el);
                                                }
                   }
                  ];

    var config = {
        paginator: new YAHOO.widget.Paginator({
            rowsPerPage: 10,
            containers: ["workgroup_table_nav"]
        }),
        sortedBy: {key:'name', dir:'asc'}
    };


    var table = new YAHOO.widget.DataTable("user_workgroup_table", columns, ds, config);

    table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
    table.subscribe("rowMouseoutEvent", table.onEventUnhighlightRow);
   
    table.subscribe("cellClickEvent", function(oArgs){
        
        var col = this.getColumn(oArgs.target);
        var rec = this.getRecord(oArgs.target);
        
        var user    = first_name + " " + family_name;
        var workgroup = rec.getData('name');
        var workgroup_id = rec.getData('workgroup_id');
        if (col.label != "Remove"){
            return;
        }

        showConfirm("Are you sure you wish to remove user " + user + " from workgroup " +workgroup+ "\?",
                    function(){
                        table.disable();
                        
                        var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=remove_user_from_workgroup&user_id="+user_id+"&workgroup_id="+workgroup_id);
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
                                               table.undisable();
                                               
                                               if (resp.meta.error){
                                                   alert("Error removing user: " + resp.meta.error);
                                                           }
                                               else{
                                                   table.deleteRow(oArgs.target);
                                               }
                                           },
                                           failure: function(req, resp){
                                               table.undisable();
                                               alert("Server error while removing user.");
                                           }
                                       }
                                      );
                    },
                                
                    function(){}
                   );

    });
        var add_user_workgroup = new YAHOO.widget.Button('add_user_to_workgroup', {label: "Add User to Workgroup"});

        // show user select
        add_user_workgroup.on("click", function(){

            var region = YAHOO.util.Dom.getRegion("user_details");

            var new_wg_p = new YAHOO.widget.Panel("add_workgroup_user",
                                                    {
                                                        width:500,
                                                        xy: [region.left,
                                                             region.top]
                                                    }
                                                   );

            new_wg_p.setHeader("Add User to Workgroup - Click to Add to Workgroup");
            new_wg_p.setBody("<center>" +
                               "<div id='add_new_user_workgroup_table'></div>" +
                               "<div id='add_new_user_workgroup_table_nav'></div>" +
                               "<div id='add_result' class='soft_title confirmation'></div>" +
                               "</center>" + 
                               "<div style='text-align: right; font-size: 85%'>" + 
                               "<div id='done_add_workgroup_user'></div>" + 
                               "</div>"
                              );

            new_wg_p.render("user_details");                

            new_wg_p.hideEvent.subscribe(function(){
                this.destroy();
            });

            var done_adding_users = new YAHOO.widget.Button('done_add_workgroup_user', {label: "Done Adding Workgroups"});

            done_adding_users.on("click", function(){
                new_wg_p.hide();
            });

                var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=get_workgroups");

                ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                ds.responseSchema = {
                    resultsList: "results",
                    fields: [ {key: "workgroup_id", parser: "number"},
                              {key: "name"},
                              {key: "description"},
                              {key: "external_id"},
                              {key: "max_mac_address_per_end"},
                              {key: "max_circuit_endpoints"},
                              {key: "max_circuits"} 
                            ]};

                var columns = [{key: "name", label: "Name", sortable:true,width: 180}
                              ];

                var config = {
                    paginator: new YAHOO.widget.Paginator({rowsPerPage: 10,
                                                           containers: ["add_new_user_workgroup_table_nav"]
                                                          }),
                    sortedBy:{key:'name',dir:'asc'}
                };


            var my_wg_table = new YAHOO.widget.DataTable("add_new_user_workgroup_table", columns, ds, config);

            my_wg_table.subscribe("rowMouseoverEvent", my_wg_table.onEventHighlightRow);
            my_wg_table.subscribe("rowMouseoutEvent", my_wg_table.onEventUnhighlightRow);
            my_wg_table.subscribe("rowClickEvent", my_wg_table.onEventSelectRow);
            
                          


            my_wg_table.subscribe("rowClickEvent", function(oArgs){

                this.disable();

                YAHOO.util.Dom.get('add_result').innerHTML = "";
                
                var record  = this.getRecord(oArgs.target);
                //var user_id = record.getData('user_id');
                //var first   = record.getData('first_name');
                //var last    = record.getData('family_name');
                var workgroup_id = record.getData('workgroup_id');
                var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=add_user_to_workgroup&workgroup_id=" + workgroup_id + "&user_id="+ user_id + "&role=normal");
                ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                ds.responseSchema = {
                    resultsList: "results",
                    fields: [{key: "success"}],
                    metaFields: { 
                        error: "error"
                    }
                };

        if (!user_id){
        add_new_user_to_workgroup =  workgroup_id;
        YAHOO.util.Dom.get('add_result').innerHTML = "Workgroup request received. User will be added to workgroup when user is created."
        }
        else {
            ds.sendRequest("", 
                       {
                       success: function(req, resp){
                           my_wg_table.undisable();
                           if (resp.meta.error){
                           YAHOO.util.Dom.get('add_result').innerHTML = "Error while adding user: " + resp.meta.error;
                           }
                           else{
                           YAHOO.util.Dom.get('add_result').innerHTML = "User added successfully.";
                                               table.addRow({name:record.getData('name'),});
                           }
                       },
                       failure: function(req, resp){
                           my_wg_table.undisable();
                           YAHOO.util.Dom.get('add_result').innerHTML = "Server error while adding user to workgroup.";
                       }
                       }
                      );
                
        }
            });

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
        
    });
        
    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=get_workgroups");
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
        resultsList: "results",
        fields: [
            {key: "workgroup_id", parser: "number"},
            {key: "name"},
            {key: "type"},
            {key: "description"},
            {key: "external_id"},
            {key: "max_mac_address_per_end"},
            {key: "max_circuit_endpoints"},
            {key: "max_circuits"} 
        ]};

    var columns = [
        {
            key: "name",
            label: "Name", sortable:true,width: 180
        }
    ];

    var config = {
        paginator: new YAHOO.widget.Paginator({
            rowsPerPage: 10,
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

    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=get_pending_nodes");

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
                   {key: "dpid", label: "Datapath ID", width: 135,
            formatter: function(el, rec){
                var dpid = rec.getData("dpid");
                var formatted_dpid = convert_dpid_to_hex(dpid);
                el.innerHTML = formatted_dpid;
            }
           },
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

    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=get_pending_links");

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

            this.details_panel.setFooter("<div id='confirm_link'></div> <div id='deny_link'></div>");

            this.details_panel.render(document.body);

            YAHOO.util.Dom.get("link_name").focus();

            if (record.getData('name')){
                YAHOO.util.Dom.get('link_name').value = record.getData('name');
            }

            var confirm_button = new YAHOO.widget.Button("confirm_link", {label: "Confirm Link"});
        var deny_button = new YAHOO.widget.Button("deny_link", {label: "Deny Link"});
        deny_button.on("click", function(e){
            
                    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=deny_link&link_id=" + record.getData('link_id') + "&interface_a_id="+ record.getData('endpoints')[0].interface_id + "&interface_z_id=" + record.getData('endpoints')[1].interface_id);
                    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                 
                    ds.responseSchema = {
                        resultsList: "results",
                        fields: [{key: "success"}]
                    };
         
                    deny_button.set("disabled", true);
                    deny_button.set("label", "Denying link...");

                    YAHOO.util.Dom.get("link_confirm_status").innerHTML = "";
                    YAHOO.util.Dom.get("node_confirm_status").innerHTML = "";
            ds.sendRequest("", {success: function(req, resp){

                                deny_button.set("disabled", false);
                                deny_button.set("label", "Deny Link");

                                if (resp.results && resp.results[0].success == 1){
                                    YAHOO.util.Dom.get("link_confirm_status").innerHTML = "Link successfully denied.";
                                    table.deleteRow(record);
                                    details_panel.hide();
                                    setup_network_tab();
                                }
                                else{
                                    alert("Link denial unsuccessful.")
                                }
                            },
                            failure: function(req, resp){
                                deny_button.set("disabled", false);
                                deny_button.set("label", "Deny Link");

                                alert("Server error while denying link.");
                            }
                        });

        }); 
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
                   
                    var ds = new YAHOO.util.DataSource("../services/admin/admin.cgi?method=confirm_link&link_id=" + record.getData('link_id') + "&name=" + encodeURIComponent(name));
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
