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
        var wtype = record.getData('type');

	    session.data.workgroup_id   = workgroup_id;
	    session.data.workgroup_name = name;
        session.data.workgroup_type = wtype;
	session.save();

	    window.location = "?action=index";
	    
	});
    makeHelpPanel("workgroups_table", "This is the list of all workgroups that you are currently a part of. Each workgroup has access to a different set of edge ports and circuits.");

}

function make_workgroups_table(){

    var ds = new YAHOO.util.DataSource("services/data.cgi?method=get_workgroups");
    ds.responseType   = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
	resultsList: "results",
	fields: [{key: "name"},
                 {key: "workgroup_id"},
                 {key: "type"}
		],
	metafields: {
	    error: "error"
	}
    };
    //sort the workgroups alphabetically
    ds.doBeforeCallback = function (Request, FullResponse, ParsedResponse, Callback) {
        ParsedResponse.results.sort(sortWorkgroups);
        return ParsedResponse;
    };
    
    var cols = [{key: "name", label: "Workgroup", sortable:true, width: 300}
		];
    var config = {
	sortedBy:{key:"name", dir:"asc"},
	height: '200px'
    }
    var dt = new YAHOO.widget.ScrollingDataTable("workgroups_table", cols, ds, config);

    function sortWorkgroups(a, b){
        var nameA=a.name.toLowerCase();
        var nameB=b.name.toLowerCase();
        if (nameA < nameB) 
            return -1;
        if (nameA > nameB)
            return 1;
        return 0; 
    }

    var search = new YAHOO.util.Element(YAHOO.util.Dom.get('workgroup_search'));
    var searchTimeout;
    search.on('keyup', function(e){

        var search_value = this.get('element').value;

        if (e.keyCode == YAHOO.util.KeyListener.KEY.ENTER){
        clearTimeout(searchTimeout);
            table_filter.call(dt,search_value);
        }
        else{
        if (searchTimeout) clearTimeout(searchTimeout);

            searchTimeout = setTimeout(function(){
            table_filter.call(dt,search_value);
            }, 400);

        }  
    });

    dt.subscribe("rowMouseoverEvent", dt.onEventHighlightRow);
    dt.subscribe("rowMouseoutEvent", dt.onEventUnhighlightRow);

    dt.on("dataReturnEvent", function(oArgs){     
        this.cache = oArgs.response;
        return oArgs;
    }); 

    return dt;
}

YAHOO.util.Event.onDOMReady(workgroups_init);

</script>
