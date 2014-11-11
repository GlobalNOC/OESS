function onClickLink(path_table, e, args, save_session) {
    var modify_path_table = function( params ) {
        params = params || [];
        var link = params.link;

        var records = path_table.getRecordSet().getRecords();

        //remove rows
        var removals = [];
        removed_selected = false;
        for (var i = 0; i < records.length; i++){
          //unselect if same link selected
          if (records[i].getData('link') == link){
            removed_selected = true;
            removals.push(i);
            break;
          }
          //unselect if in multilink list but is no longer selected
          else {
            for (var j = 0; j < args[0].links.length; j++) {
              var option_link = args[0].links[j].link_name;
              if ( (records[i].getData('link') == option_link) &&
                   (records[i].getData('link') != link) ){
                removals.push(i);
              }
            }
          }
        }

        // if it was previous selected, deselect and remove from table
        for( var i = 0; i < removals.length; i++) {
            var row_index = removals[i];
            path_table.deleteRow(row_index);
        }

        if(!removed_selected && link) path_table.addRow({link: link});
        save_session();
    };

    var feature = args[0].feature;
    if(args[0].links.length){
        get_multilink_panel("multilink_panel", {
            on_change: function(oArgs){
                modify_path_table( {link: oArgs.link} );
            },
            links: args[0].links,
            //hide_down_links 
        });
        return;
    } else {
        modify_path_table( {link: args[0].name} );
    }
}
