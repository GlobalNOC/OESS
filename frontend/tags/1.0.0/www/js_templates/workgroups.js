<script>

function workgroups_init(){

    session.clear(true);

    // hide the "workgroup" display since it's irrelevant here
    YAHOO.util.Dom.get("active_workgroup_container").style.display = "none";

    var table = make_workgroups_table();

    table.subscribe("rowClickEvent", function(oArgs){

	    var record = this.getRecord(oArgs.target);

	    if (! record) return;

	    var workgroup_id = record.getData('workgroup_id');
	    var name         = record.getData('name');

	    session.data.workgroup_id   = workgroup_id;
	    session.data.workgroup_name = name;

	    session.save();

	    window.location = "?action=index";
	    
	});

    makeHelpPanel("workgroups_table", "This is the list of all workgroups that you are currently a part of. Each workgroup has access to a different set of edge ports and circuits.");

}

function make_workgroups_table(){

    var ds = new YAHOO.util.DataSource("services/data.cgi?action=get_workgroups");
    ds.responseType   = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "name"},
                 {key: "workgroup_id"}
		 ],
	metafields: {
	    error: "error"
	}
    };

    var cols = [{key: "name", label: "Workgroup", width: 300}
		];

    var config = {
	paginator: new YAHOO.widget.Paginator({rowsPerPage: 5,
					       containers: ["workgroups_table_nav"]
	    })
    }

    var dt = new YAHOO.widget.DataTable("workgroups_table", cols, ds, config);

    dt.subscribe("rowMouseoverEvent", dt.onEventHighlightRow);
    dt.subscribe("rowMouseoutEvent", dt.onEventUnhighlightRow);

    return dt;
}

YAHOO.util.Event.onDOMReady(workgroups_init);

</script>