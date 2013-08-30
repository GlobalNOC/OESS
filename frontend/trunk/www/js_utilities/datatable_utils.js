
    function _makeTableDragDrop(table, ds_options){


        table.createEvent("rowDrag", {scope: table});
        var ddtargets = {};

        table.enableDragDrop = function(){
            //table._dragDrop = true;
            this._dragDrop = true;

            var _makeInitTargets = function(){
                var allRows = table.getTbodyEl().rows;

                // create a drag/drop target instance for each row
                for(var i=0; i<allRows.length; i++){
                    var id = allRows[i].id;
                    ddtargets[id] = new YAHOO.util.DDTarget(id);
                }
            };

            //may be called before rows returned
            table.subscribe("initEvent", _makeInitTargets);
            _makeInitTargets();

            // whenever a new row is added we need to make it drag/drop target
            table.subscribe("rowAddEvent", function(e){
                var id = e.record.getId();
                ddtargets[id] = new YAHOO.util.DDTarget(id);
            });

            // actually handle the drag/drop stuff
            table.subscribe('cellMousedownEvent', function(e){
                // drag/drop turned off, don't respond
                if (! this._dragDrop){
                    return;
                }

                var tr    = table.getTrEl(YAHOO.util.Event.getTarget(e));
                var ddRow = new YAHOO.util.DDProxy(tr.id);

                ddRow.handleMouseDown(e.event);

                var proxy, src, srcData, srcIndex, displaced, displacedRecord;
                var seenRows = {};
                var tmpIndex = null;

                // when we start dragging a row, we make the proxyEl look like the src Element. We get also cache all the data related to it
                ddRow.startDrag = function(){
                    proxy    = this.getDragEl();
                    src      = this.getEl();
                    srcData  = table.getRecord(src).getData();
                    srcIndex = src.sectionRowIndex;

                    // make the proxy look like the source element
                    YAHOO.util.Dom.setStyle(src, "visibility", "hidden");
                    proxy.innerHTML = "<table><tbody>"+src.innerHTML+"</tbody></table>";
                };


                ddRow.endDrag = function(x, y){
                    YAHOO.util.Dom.setStyle(proxy, "visibility", "hidden");
                    YAHOO.util.Dom.setStyle(src, "visibility", "");
                    var record = table.getRecord(tmpIndex);
                    var newRow = table.getTrEl(record);
                    table.fireEvent("rowDrag", {
                        row: newRow,
                        displacedRow: displaced,
                        record: record,
                        displacedRecord: displacedRecord,
                        newIndex: tmpIndex
                    });
                };
            
                // as we move over, swap one row with another.
                ddRow.onDragOver = function(e, id) {
                    var dest  = YAHOO.util.Dom.get(id),
                    destIndex = dest.sectionRowIndex;
        
                    // don't do anything if we're mousing over the same row
                    if (tmpIndex == destIndex){
                        return;
                    }
    
                    if (dest.nodeName.toLowerCase() === "tr") {
                        // keep track of where we are originally in case we need to backtrack
                        if ( seenRows[id] === undefined ){
                            seenRows[id] = destIndex;
                        }

                        // we're backtracking somehow in this drag (ie overshot our target)
                        // so figure out what this would have looked like if we didn't overshoot
                        if ( destIndex != seenRows[id] ){
                            var row_id; 
                            for (row_id in seenRows){
                                if (seenRows.hasOwnProperty(row_id) && seenRows[row_id] == destIndex){                               
                                    displaced = YAHOO.util.Dom.get(row_id);
                                    break;
                                }
                            }
                        }
                        else {
                            displaced = dest;
                        }
                        
                        displacedRecord = table.getRecord(displaced);
                        
                        if (tmpIndex !== null) {
                            table.deleteRow(tmpIndex);
                        }
                        else {
                            table.deleteRow(srcIndex);
                        }

                        table.addRow(srcData, destIndex);
                        tmpIndex = destIndex;

                        YAHOO.util.DragDropMgr.refreshCache();
                    }
                };

            });
            //$('#'+link_id).html("Disable Reordering");
            $('#'+link_id+' a').html("Disable Reordering");

        };

        // makes internal hooks not react to drag and drop, also removes the
        // class that make things look draggable
        table.disableDragDrop = function(){
            this._dragDrop = false;
            //$('#'+link_id).html("Enable Reordering");
            $('#'+link_id+' a').html("Enable Reordering");
        };


        //automagically hook it up to a datasource if they passed in options
        if(ds_options) {
            table.on("rowDrag", function(e){
                var dragged_record  = e.record;
                var replaced_record = e.displacedRecord;
        
                if (! dragged_record || ! replaced_record){
                    return;
                }
        
                table.disable();
        
                var url = ds_options.url; 
                // position param
                var position_param_value = replaced_record.getData(ds_options.position_param);
                url += "&"+ds_options.position_param+"="+position_param_value;
                for(var i=0; i<ds_options.ws_params.length; i++){
                    var ws_param_value = dragged_record.getData(ds_options.ws_params[i]);
                    if(ws_param_value){
                        url += "&"+ds_options.ws_params[i]+"="+ws_param_value;
                    }
                }
        
                var ds = new  YAHOO.util.DataSource(url);
                ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                ds.responseSchema = {
                    resultsList: "results",
                    fields: ds_options.fields
                };
        
                ds.sendRequest("",{
                    success: function(req, resp, index){
                        table.undisable();
                        ds_options.onSuccess(req,resp,index);
                    },
                    failure: function(req, resp, index){
                        table.undisable();
                        ds_options.onFailure(req,resp,index);
                    },
                    scope: this
                });
            });
        }
        //create toggle link
        var link_id     = table.get("id")+'_dd_toggle';
        //check to make sure link doesn't already exist
        if($('#'+link_id).length){
            $('#'+link_id).remove();
        }
        //var link_markup = '<a href="#"><div id="'+link_id+'">Enable Reordering</div></a>';
        var link_markup = '<div id="'+link_id+'"><a href="#">Enable Reordering</a></div>';
        $(link_markup).insertAfter('#'+table.get("id"));
        $('#'+link_id).click(function(event) {
            event.preventDefault();
            if(table._dragDrop){
                table.disableDragDrop();
            }else {
                table.enableDragDrop();
            }
        });

        //return table;
    }
