<script>
  
  
function init(){  

    setPageSummary("Diagnostic Circuit Loopback", "");

    var nddi_map = new NDDIMap("map");


    var layout = new YAHOO.widget.Layout('layout',
                     {height: 420,
                      width: 550,
                      units: 
                      [{position: "left", id: "left", width: 550, height: 400, resize: true, minWidth: 150, maxWidth: 500, gutter: "0px 9px 25px 0px"},
                                           {position: "center", id: "center", gutter: "0px 0px 0px 3px"},
                       ]   
                     }   
                     );  

  

   layout.on("resize", function(){

      nddi_map.map.updateSize();

      var region = YAHOO.util.Dom.getRegion(this.getUnitByPosition('left'));

      session.data.map_width = region.width;

      nddi_map.map.zoomTo(nddi_map.calculateZoomLevel(region.width));

      }); 

  layout.render();

    legend_init(nddi_map, true);

    //nddi_map.showDefault();

    nddi_map.on("loaded", function(){
        this.updateMapFromSession(session);
          });

    nddi_map.on("clickNode", function(e, args){	  
  
        showConfirm("Are you sure you want to loop this node?  Traffic on this circuit will be impacted while it is in place.",
        function(){
        var description = session.data.description;
        var bandwidth   = parseInt(session.data.bandwidth / (1000 * 1000));
        var provision_time = session.data.provision_time;
        var remove_time    = session.data.remove_time;
        var restore_to_primary = session.data.restore_to_primary;
        var state = "looped";

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

        var node_id    = args[0].node_id;


        var postVars = "action=provision_circuit&circuit_id="+encodeURIComponent(circuit_id)
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

        document.getElementById("loop_status").innerHTML = "Attemping to Loop Circuit.";


        var ds = new YAHOO.util.DataSource("services/provisioning.cgi?");
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
    },
       function(){} 
    );
    });

}

function handleLocalSuccess(request, response){

    document.getElementById("loop_status").innerHTML = "";
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
        session.save();

        var warning = "";

        if (response.meta && response.meta.warning){
        warning = "Warning: " + response.meta.warning;
        }

        alert("Circuit successfully Looped.<br>" + warning,
          function(){
              window.location = "?action=view_details";
          }
          );
    }
    else{
        alert("Circuit successfully Looped.",
          function(){
              window.location = "?action=view_details";
          }
          );
    }
    }
    else {
    alert("Unknown return value in looping.");
    }
}

function handleLocalFailure(request, response){
    document.getElementById("loop_status").innerHTML = "";
    alert("Error while communicating with server. If this problem continues to exist, please notify your system administrator.");
}

YAHOO.util.Event.onDOMReady(init);
  
</script>
