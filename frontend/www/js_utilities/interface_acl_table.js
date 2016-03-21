    function get_interface_acl_table(container_id, interface_id, options){
        if(interface_acl_table) {
            interface_acl_table.destroy();
        }
        var options = options || {};

        var dsString="services/workgroup_manage.cgi?method=get_acls&interface_id="+interface_id;
        if(options.url_prefix){
            dsString = options.url_prefix + dsString;
        }

        var ds = new YAHOO.util.DataSource(dsString);
        ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
        ds.responseSchema = {
        resultsList: "results",
        fields: [
            {key: "interface_acl_id", parser: "number"},
            {key: "workgroup_id", parser: "number"},
            {key: "workgroup_name"},
            {key: "interface_id", parser: "number"},
            {key: "allow_deny"},
            {key: "eval_position"},
            {key: "vlan_start"},
            {key: "vlan_end"},
            {key: "notes"}
        ]};

        var columns = [
            {key: "workgroup_name", label: "Workgroup", width: 180 ,sortable:false, formatter: function(el, rec, col, data){
                if(data === null) {
                    el.innerHTML = "All";
                } else {
                    el.innerHTML = data;
                }
            }},
            {key: "allow_deny", label: "Permission",sortable:false},
            {label: "VLAN Range", formatter: function(el, rec, col, data){
                var vlan_start  = rec.getData('vlan_start');
                var vlan_end    = rec.getData('vlan_end');
                if(vlan_start == -1){
                    vlan_start = 'untagged';
                }
                var string = vlan_start;
                if(vlan_end !== null){
                    if(vlan_start == "untagged") {
                        string += ", 1";
                    }
                    string += "-"+vlan_end;
                }
                el.innerHTML = string;
            }},
            {key: "notes", label: "Notes",sortable:false}
        ];

        var config = {};

        $("#"+container_id+"_container").css('display', 'block');
        var interface_acl_table = new YAHOO.widget.DataTable(container_id, columns, ds, config);



        //make drag drop
        var url = "services/workgroup_manage.cgi?method=update_acl";
        if(options.url_prefix){
            url = options.url_prefix + url;
        }

        _makeTableDragDrop(interface_acl_table, {
            url: url,
            position_param: "eval_position",
            ws_params: [
                "interface_acl_id",
                "allow_deny",
                "vlan_start",
                "vlan_end",
                "interface_id",
                "workgroup_id",
                "notes"
            ],
            fields: ["success"],
            onSuccess: function(req, resp, index){
                if(resp.results.length <= 0){
                    alert("Save Unsuccessful", null, { error: true });
                }
                var new_options = options;
                new_options.enableDragDrop = interface_acl_table._dragDrop;
                get_interface_acl_table(container_id, interface_id, new_options);
            },
            onFailure: function(req, resp, index) {
                alert("Save Unsuccessful", null, { error: true });
                var new_options = options;
                new_options.enableDragDrop = interface_acl_table._dragDrop;
                get_interface_acl_table(container_id, interface_id, new_options);
            }
        });

        if(options.enableDragDrop){
            interface_acl_table.enableDragDrop();
        }

        //add editing functionality
        interface_acl_table.subscribe("rowClickEvent", function(oArgs){
            if(this._dragDrop){
                return;
            }
            var record = this.getRecord(oArgs.target);

            options.on_show_edit_panel({
                record: record,
                interface_id: interface_id
            });
        });
        interface_acl_table.subscribe("rowMouseoverEvent", interface_acl_table.onEventHighlightRow);
        interface_acl_table.subscribe("rowMouseoutEvent", interface_acl_table.onEventUnhighlightRow);

        //return owned_interface_table;
        return interface_acl_table;
    }
