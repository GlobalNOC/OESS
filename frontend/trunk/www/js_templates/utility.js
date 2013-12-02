<script>

window.originalAlert = window.alert;

// override the default alert so we can make it prettier / standardized
window.alert = function(text, callback){

     var width  = YAHOO.util.Dom.getClientWidth();

     var alert_box = new YAHOO.widget.Panel("alert", 
                                            {
						width: 350,
						close: false,
						draggable: false,
						zindex: 9999999,
						visible: false,
						underlay: 'shadow',
						xy: [(width / 2) - 175, 175]
					    });

     alert_box.setHeader("Notice");
     alert_box.setBody("<center>"+text+"</center>" + 
		       "<div style='text-align: right;'><div id='close_alert'></div></div>"
		       );

     alert_box.render(document.body);

     var close_button = new YAHOO.widget.Button('close_alert', {label: "Ok"});

     close_button.on("click", function(){
	     alert_box.destroy();

	     if (callback) callback();
	 });

     alert_box.show();

     close_button.focus();

     YAHOO.util.Dom.addClass("alert", "popup_box");

};

function showConfirm(text, yesCallback, noCallback){

    var width  = YAHOO.util.Dom.getClientWidth();
    
    var confirm_box = new YAHOO.widget.Panel("confirm", 
					     {
						 width: 350,
						 close: true,
						 draggable: false,
						 zindex: 9999999,
						 visible: false,
						 underlay: 'shadow',
						 xy: [(width / 2) - 175, 175]
					     });
    
    confirm_box.setHeader("Confirm");
    confirm_box.setBody("<center>"+text+"</center>" + 
			"<div style='text-align: right;'>" + 
			"  <div id='yes_button'></div>" + 
			"  <div id='no_button'></div>" + 
			"</div>"
			);
    
    confirm_box.render(document.body);
    
    var yes_button = new YAHOO.widget.Button('yes_button', {label: "Yes"});
    var no_button = new YAHOO.widget.Button('no_button', {label: "No"});

    yes_button.on("click", function(){
	    confirm_box.destroy();
	    yesCallback();
	});

    no_button.on("click", function(){
	    confirm_box.destroy();
	    noCallback();
	});

    confirm_box.show();
    
    no_button.focus();

    YAHOO.util.Dom.addClass("confirm", "popup_box");    
}

function table_filter(search_term){

	//expects this to be a Yahoo.widget.DataTable Could simplify by making this a prototype method of DataTable but for now table_filter.call(myTable,searchTerm) should suffice


      if (! this.cache){
	return;
      }
      
      var new_rows = [];
      
      // empty search term, show everything again
      if (! search_term){
	new_rows = this.cache.results;
      }
      else{

	var regex = new RegExp(search_term, "i");
		  var columns = this.getColumnSet().getDefinitions();
	for (var i = 0; i < this.cache.results.length; i++){
	
	  var row = this.cache.results[i];
	 
	  for (var j = 0; j < columns.length; j++){
	    var col_name = columns[j]['key'];
	    
	    var value = row[col_name];

	    if (regex.exec(value)){
	      new_rows.push(row);
	      break;
	    }
	    
	  }
	  
	} 	
	
      }
      
      this.deleteRows(0, this.getRecordSet().getRecords().length);
    if(new_rows !== undefined  && new_rows.length > 0){
      this.addRows(new_rows);
	}
}


function setPageSummary(mainText, secondaryText){
  
  var holder_div = YAHOO.util.Dom.get('page_summary_container');
  
  if (! holder_div) return;
  
  holder_div.innerHTML = "";

  var mainP = document.createElement('p');
  var secP  = document.createElement('p');
  
  mainP.appendChild(document.createTextNode(mainText));
  secP.appendChild(document.createTextNode(secondaryText));
  
  mainP.className = "title";
  secP.className  = "subtitle";
  
  holder_div.appendChild(mainP);
  holder_div.appendChild(secP);
}

function setSubmitButton(text, callback){
  var button = new YAHOO.widget.Button("next_button", {label: text});
  
  button.on("click", callback);
  
  return button;
}

function setNextButton(text, url, verification_callback){
  
  verification_callback = verification_callback || function(){return true;};
  
  var button = new YAHOO.widget.Button("next_button", {label: text});
  
  button.on("click", function(){	      
		if (verification_callback()){		
		  window.location = url;  
		}	     
	    });
  
  return button;
  
}

function hookupRadioButtons(name, value, callback){
  
  var radios = document.getElementsByName(name);
  
  for (var i = 0; i < radios.length; i++){

      var el = new YAHOO.util.Element(radios[i]);

      el.on("click", callback);
    
  }
  
  for (var i = 0; i < radios.length; i++){
    
    if (radios[i].value == value){
      radios[i].checked = true;
    }
    
  }
  
}


function makeCalendarPopup(position, selected_time){

    var selected_hour, 
	selected_minute,
	selected_month,
	selected_day,
	selected_year;

    selected_time = parseInt(selected_time);

    if (selected_time && selected_time != -1 && ! isNaN(selected_time)){

	var date  = new Date(selected_time);
	
	selected_month  = date.getUTCMonth();
	selected_day    = date.getUTCDate();
	selected_year   = date.getUTCFullYear();	
	selected_hour   = date.getUTCHours();
	selected_minute = date.getUTCMinutes();
	
	
    }

    var panel = new YAHOO.widget.Panel("calendar_panel",
				       {
					   width: "200px",
					   height: "310px",
					   closeable: true,
					   draggable: true,
					   xy: position
				       }
				       );

    panel.setHeader("Time Selection");
    panel.setBody("<div id='calendar' style='border: none;'></div>" +
		  "<div style='clear: both; padding-top: 10px; text-align: center;'>" +		  
		  "<select id='hour'></select>" +
		  ":" + 
		  "<select id='minute'></select>" +
		  "UTC" + 
		  "</div>" +
		  "<div id='calendar_button_holder' style='padding-top: 10px; font-size: 80%; text-align: right;'>" +
		  "<div id='calendar_button'></div>" +
		  "</div>"
		  );

    panel.render(document.body);

    var hour_select = YAHOO.util.Dom.get('hour');

    // set up the hour options (nothing special, writing out 24 + 60 options is just tedious)
    for (var i = 0; i < 24; i++){
	var hour = i;
	if (hour < 10){
	    hour = "0" + hour;
	}
	hour_select.options[i] = new Option(hour, hour);

	if (hour == selected_hour){
	    hour_select.selectedIndex = i;
	}

    }

    var minute_select = YAHOO.util.Dom.get('minute');

    // set up the minute options
    for (var i = 0; i < 60; i++){
	var minute = i;
	if (minute < 10){
	    minute = "0" + minute;
	}
	minute_select.options[i] = new Option(minute, minute);

	if (minute == selected_minute){
	    minute_select.selectedIndex = i;
	}
    }

    // create the button we can hook up on outside
    var cal_button = new YAHOO.widget.Button('calendar_button', {label: 'Select'});

    panel.show();

    // create the calendar. YUI calendar auto defaults to today
    var cal = new YAHOO.widget.Calendar('calendar');

    if (selected_month != null){

	var timeString = (selected_month+1) + "/" + selected_day + "/" + selected_year;
	
	cal.setMonth(selected_month);
	cal.setYear(selected_year);

	cal.cfg.setProperty("selected", timeString);

    }

    cal.render();

    return {panel: panel, calendar: cal, button: cal_button};
}

function makePageLayout(nddi_map, options){

    options = options || {};

    var max_resize  = options.max_resize || 700;

    var map_width   = options.map_width  || 700;

    var layout = new YAHOO.widget.Layout('layout',
					 {height: 400,
					  width: 950,
					  units: 
					  [{position: "left", id: "left", width: map_width, height: 400, resize: true, minWidth: 150, maxWidth: max_resize, gutter: "0px 9px 0px 0px"},
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

  return layout;

}

function makeStaticMacTable( body, header ) {
  
    header = "Static MAC Addresses & " + header; 
    body += "<div id='tag_selection_mac_table' style='margin-bottom: 2px;'></div>"; 
    //body += "<div id='tag_selection_mac_table'></div>"; 
    //body += "<label for='mac_address_input' class='soft_title'>MAC Address:</label>";
    var style = "'height: 27px; vertical-align: top;'";
    body += "<input id='mac_address_input' type='text' size='13' style="+style+">";
    body += "<span class='yui-button yui-link-button'>";
    body +=     "<span id='add_mac_address' class='first-child'>";
    body +=         "<a href='#add_acl'>Add MAC Address</a>";
    body +=     "</span>";
    body += "</span>";

   
    //can't create the table until the panel has been rendered 
    init_table = function(){ 
        var ds = new YAHOO.util.DataSource([]);
        ds.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;

        var cols = [
            {key: "mac_address", width: 130, label: "MAC Address"},
            {label: "Delete", width: 65, formatter: function(el, rec, col, data){
                var del_button = new YAHOO.widget.Button({label: "Delete"});
                YAHOO.util.Dom.addClass(del_button, "mac_address_remove_button");
                var t = this;
                del_button.on("click", function(){
                    var interface = rec.getData('interface');
                    t.deleteRow(t.getRecordSet().getRecordIndex(rec));
                    /*
                    showConfirm("Are you sure you wish to delete interface " + interface + "?",
                    function(){
                        t.deleteRow(t.getRecordSet().getRecordIndex(rec));
                    },
                    function(){}
                    );
                    */
                });
                del_button.appendTo(el);
            }}
        ];

        var config = {};
        var table = new YAHOO.widget.ScrollingDataTable("tag_selection_mac_table", cols, ds, config);
    
        // create a function to create an add mac address dialog
        var add_mac_address = new YAHOO.util.Element('add_mac_address');
        var oLinkButton1    = new YAHOO.widget.Button("add_mac_address");
        add_mac_address.on('click', function(){
            var mac_address_input = YAHOO.util.Dom.get('mac_address_input');
            var mac_address = mac_address_input.value; 
            mac_address = mac_address.toLowerCase();
            //if(mac_address.match(/^([0-9A-F]{2}:){5}([0-9A-F]{2})$/)){
            if(mac_address.match(/^([0-9a-f]{2}:){5}([0-9a-f]{2})$/)){
                table.addRow({
                    mac_address: mac_address
                });
            }else {
                alert("Invalid format, must match XX:XX:XX:XX:XX:XX");
            }

            /*
            var ds = new YAHOO.util.DataSource(
                "services/data.cgi?action=is_vlan_tag_available"+
                "&interface="+encodeURIComponent(interface)
            );
            ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
            ds.responseSchema = {
            resultsList: "results",
            fields: [{key: "available", parser: "number"}],
                metaFields: {
                  "error": "error"
                }
            };

            add_tag_button.set("label", "Validating...");
            add_tag_button.set("disabled", true);

            ds.sendRequest("", {success: function(req, resp){
            add_tag_button.set("label", "Add Tag");
            add_tag_button.set("disabled", false);

            if (resp.meta.error){
                alert("Error - " + resp.meta.error);
                return;
            }
            else if (resp.results[0].available == 1){
                endpoint_table.addRow({
                    interface: interface,
                    interface_description: description,
                    node: node,
                    tag: new_tag
                });

                save_session();

                nddi_map.table.unselectAllRows();
                nddi_map.table.vlan_panel.destroy();
                nddi_map.table.vlan_panel = undefined;
            }
            else{
                if (new_tag == -1){
                alert("Untagged traffic is currently in use by another circuit on interface " + interface + " on endpoint " + node + ".");
                }
                else {
                alert("Tag " + new_tag + " is not currently available on interface " + interface + " on endpoint " + node + ".");
                }
            }

            },
            failure: function(reqp, resp){
            add_tag_button.set("label", "Add Tag");
            add_tag_button.set("disabled", false);

            alert("Error validating endpoint.");
            }
            });
            */
        });

        return table;
    };

    return { 
        body: body, 
        header: header, 
        init_table: init_table 
    };
}

function makeTagSelectPanel(coordinates, options ){
    options = options || {};

    var interface = options.interface;

    if(options.align_right){
        coordinates[0] = coordinates[0] - (options.panel_width || 200); 
    }
    
    var tag_selection_panel = YAHOO.util.Dom.get("tag_selection");
    if(tag_selection_panel){
        tag_selection_panel = new YAHOO.util.Element(tag_selection_panel);
        tag_selection_panel.destroy();
    }
    var panel = new YAHOO.widget.Panel("tag_selection",{
        width: options.panel_width || 280,
        xy: coordinates,
        close: true
    });
    panel.hide = function(){
        this.destroy();
        //this = undefined;
    };
    /*
    panel.close = function(){
        this.destroy();
    };
    */
    //remove the default click handler (._doClose)
    //YAHOO.util.Event.removeListener(panel.close, "click");   

    //add a new click handler (._doClose)
    /*
    YAHOO.util.Event.on(panel.hideEvent, "click", function(){
        this.destroy();
    }, panel, true);
    */

    /*
    panel.on('visibleChange', function(e) {
        var hidden = !e.newVal; // e.newVal will be true when showed, false when hidden
        if (hidden) {
            panel.destroy();
        }
    });
    */
  
    var vlan_tag_attr_style = "margin-bottom: 4px'"; 
    var header = "VLAN Tag for Interface " + interface; 
    var body   = 
    "<div style='margin-bottom: 4px'>" +
        "<label class='soft_title' style='padding-right: 5px;' for='new_vlan_tag'>VLAN Tag:</label>" +
        "<input id='new_vlan_tag' type='text' value='' size='4'>" +
        "<span style='padding-left: 5px;font-size: 10px;font-style: italic;vertical-align:top;'>" + 
           "*<label style='vertical-align: top;'>Range:</label>" +
           "(<span style='vertical-align: top;' id='new_vlan_tag_range'></span>)" +
        "</span>"+
    "</div>" +
    "<div style="+vlan_tag_attr_style+">" +
        "<label for='tagged' class='soft_title' style='padding-left: 16px;padding-right: 5px;'>Tagged:</label>" + 
        "<input id='tagged' style='padding-left: 5px;' type='checkbox' checked='checked'>" + 
    "</div>";


    var static_mac_table_init;
    //if(options.include_static_mac_table){
    if(session.data.static_mac_routing){
        var components = makeStaticMacTable( body, header );
        body   = components.body;
        header = components.header;
        static_mac_table_init = components.init_table;
    }

    panel.setHeader(header);
    panel.setBody(body);
    panel.setFooter(
        "<div id='save_endpoint_button'></div>"+
        "<div id='remove_endpoint_button'></div>"
    )
    panel.render(document.body);

    //set the vlan_tag_range
    var tag_range_holder = YAHOO.util.Dom.get('new_vlan_tag_range');
    tag_range_holder.innerHTML = options.tag_range;

    var save_button = new YAHOO.widget.Button('save_endpoint_button');
    save_button.set('label','Save');

    var remove_button = new YAHOO.widget.Button('remove_endpoint_button');
    remove_button.set('label','Remove');


    var vlan_input = YAHOO.util.Dom.get('new_vlan_tag');
    
    vlan_input.focus();

    var tagged = new YAHOO.util.Element(YAHOO.util.Dom.get("tagged"));
    tagged.on("click", function(){
	    if (this.get('element').checked){
            vlan_input.disabled = false;
            vlan_input.focus();
	    }
	    else {
            vlan_input.disabled = true;
            vlan_input.value = "";
	    }
	});  


    /*    
    var add_tag_button = new YAHOO.widget.Button("add_new_vlan_tag_button", {label: "Add Tag"});
    
    var tagged = new YAHOO.util.Element(YAHOO.util.Dom.get("tagged"));
    
    tagged.on("click", function(){
	    if (this.get('element').checked){
            vlan_input.disabled = false;
            vlan_input.focus();
            add_tag_button.set("label", "Add Tag");
	    }
	    else {
            vlan_input.disabled = true;
            vlan_input.value = "";
            add_tag_button.set("label", "Add Untagged");
	    }
	});  
    */
    var table;
    var get_mac_addresses;
    if(session.data.static_mac_routing){
        table = static_mac_table_init();
        get_mac_addresses = function(){
            var mac_addrs = [];
            var records = table.getRecordSet().getRecords();
            for(var i=0; i < records.length; i++){
                mac_addrs.push({
                    mac_address: records[i].getData("mac_address")
                });
            } 
            return mac_addrs;
        }
    }


    var obj = {
        panel: panel, 
        tagged_input: tagged,
        save_button: save_button,
        remove_button: remove_button
    };

    if(session.data.static_mac_routing){
        obj.static_mac_table = table;
        obj.get_mac_addresses = get_mac_addresses;
    }

    function verify_and_add_endpoint(){
        var vlan_input = YAHOO.util.Dom.get('new_vlan_tag');
        //--- determine if tag is untagged and validate input
        var new_tag;
        if (tagged.get('element').checked){
            new_tag = vlan_input.value;
            if (! new_tag){
              alert("You must specify an outgoing VLAN tag.");
              return;
            }
            if (! new_tag.match(/^\d+$/) || new_tag >= 4096 || new_tag < 1){
              alert("You must specify a VLAN tag between 1 and 4095.");
              return;
            }
        }else {
            new_tag = -1;
        }

        //--- save function
        var tag_verified = false;
        var mac_limit_verified = false;
        function save(){
            // only save if both input has been validated
            if( tag_verified && mac_limit_verified ){
                save_button.set("label", "Save");
                save_button.set("disabled", false);

                if(!session.data.static_mac_routing) {
                    options.save_action({
                        tag: new_tag
                    });
                }else {
                    options.save_action({
                        get_mac_addresses: get_mac_addresses,
                        tag: new_tag
                    });
                }

                panel.hide();
                /*
                endpoint_table.addRow({
                    interface: interface,
                    interface_description: description,
                    node: node,
                    tag: new_tag,
                    mac_addrs: components.get_mac_addresses()
                });

                save_session();

                nddi_map.table.unselectAllRows();
                nddi_map.table.vlan_panel.destroy();
                nddi_map.table.vlan_panel = undefined;
                */
            }
        }

        //--- validate the tag input
        // if this is an edit and we haven't changed the tag don't try to 
        // validate b/c it will be incorrect
        if( options.is_edit && (new_tag == options.current_values.tag) ){
            tag_verified = true;
        } else {
            var tag_ds = new YAHOO.util.DataSource(
                "services/data.cgi?action=is_vlan_tag_available"+
                "&vlan="+new_tag+
                "&interface="+encodeURIComponent(options.interface)+
                "&node="+encodeURIComponent(options.node)+
                "&workgroup_id="+options.workgroup_id
            );
            tag_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
            tag_ds.responseSchema = {
                resultsList: "results",
                fields: [{key: "available", parser: "number"}],
                metaFields: {
                  "error": "error"
                }
            };

            save_button.set("label", "Validating...");
            save_button.set("disabled", true);
            tag_ds.sendRequest("", {
            success: function(req, resp){
                if (resp.meta.error){
                    alert("Error - " + resp.meta.error);
                    return;
                }
                else if (resp.results[0].available == 1){
                    tag_verified = true;
                    save();
                }
                else{
                    if (new_tag == -1){
                        alert("Untagged traffic is currently in use by another circuit on interface " + options.interface + " on endpoint " + options.node + ".");
                    }
                    else {
                        alert("Tag " + new_tag + " is not currently available on interface " + options.interface + " on endpoint " + options.node + ".");
                    }
                    save_button.set("label", "Save");
                    save_button.set("disabled", false);
                }

            },
            failure: function(reqp, resp){
                save_button.set("label", "Save");
                save_button.set("disabled", false);

                alert("Error validating endpoint.");
            }});
        }

        //only validate mac addresses if the static mac flag was set
        if(!session.data.static_mac_routing) {
            mac_limit_verified = true;
            if(tag_verified){
                save(); 
            }
        }else {
            //--- verfiy mac addrs don't go over limits
            // build mac address string
            var mac_address_string = "";
            var mac_addresses = get_mac_addresses();
            for(var i=0; i< mac_addresses.length; i++){
                var mac_address = mac_addresses[i].mac_address;
                mac_address_string += "&mac_address="+mac_address;
            }

            var mac_ds = new YAHOO.util.DataSource(
                "services/data.cgi?action=is_within_mac_limit"+
                mac_address_string+
                "&interface="+encodeURIComponent(options.interface)+
                "&node="+encodeURIComponent(options.node)+
                "&workgroup_id="+options.workgroup_id
            );
            mac_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
            mac_ds.responseSchema = {
                resultsList: "results",
                fields: [
                    {key: "verified", parser: "number"},
                    {key: "explanation"}
                ],
                metaFields: {
                  "error": "error"
                }
            };

            save_button.set("label", "Validating...");
            save_button.set("disabled", true);
            mac_ds.sendRequest("", {
            success: function(req, resp){
                if (resp.meta.error){
                    alert("Error - " + resp.meta.error);
                    save_button.set("label", "Save");
                    save_button.set("disabled", false);
                    return;
                }
                else if (resp.results[0].verified == 1){
                    mac_limit_verified = true;
                    save();
                }
                else{
                    alert( "Problem adding mac addresses: "+resp.results[0].explanation );
                    save_button.set("label", "Save");
                    save_button.set("disabled", false);
                }
            },
            failure: function(reqp, resp){
                save_button.set("label", "Save");
                save_button.set("disabled", false);

                alert("Error validating endpoint.");
            }});

        } 
    }//--- end verify_and_add_endpoint

    // select all the current values if it is an edit
    if(options.is_edit){
        var vlan_input = YAHOO.util.Dom.get('new_vlan_tag');
        vlan_input.value = options.current_values.tag;
       
        //only set the mac address steff if the mac address flag was set 
        if(session.data.static_mac_routing){ 
            var mac_addrs = options.current_values.mac_addresses;
            for(var i=0; i< mac_addrs.length; i++){
                var mac_addr = mac_addrs[i];
                table.addRow({
                    mac_address: mac_addr.mac_address
                });
            }
        }
    }

    save_button.on("click", verify_and_add_endpoint);
    if(options.remove_action){
        remove_button.on("click", function(){
            options.remove_action();
            panel.hide();
        });
    }else {
        remove_button.setStyle('display', 'none');
    }
 
    return obj; 
}

function makeHelpPanel(elements, text){

    if (typeof elements != "object"){
	elements = [elements];
    }

    var panel = new YAHOO.widget.Panel("help_" + elements[0],
				       {visible: false,
					close: false,
					underlay: "none",
					zindex: 999999,
					width: "300px",
					effect: {effect: YAHOO.widget.ContainerEffect.FADE, duration: 0.25},
				       });

    panel.setHeader("");
    panel.setBody("<div>"+text+"</div>");
    
    panel.render(YAHOO.util.Dom.get(elements[0]).parentNode);
    panel.header.style.display = "none";
    panel.body.style["border-radius"] = "6px";
    panel.body.parentNode.style["border-radius"] = "6px";

    var timeout;
    var x, y;

    for (var i = 0; i < elements.length; i++){

	var element = elements[i];

	var el = YAHOO.util.Dom.get(element);

	var yEl = new YAHOO.util.Element(el);
		
	yEl.on("mouseover", function(closureEl){
		return function(e){
		    x = e.clientX;
		    y = e.clientY;

		    var region = YAHOO.util.Dom.getRegion(closureEl);
		    
		    clearTimeout(timeout);
		    setTimeout(function(){
			    if (x == e.clientX && y == e.clientY){

				var moveX = region.right + 5;
				var moveY = region.top;

				// won't fit on the right side, move to the left side
				if (x + moveX > YAHOO.util.Dom.getClientWidth()){
				    moveX = region.left - 300 - 5; 
				}

				panel.moveTo(moveX, moveY);
				panel.show();
			    }
			}, 500);
		}
	    }(element));
	
	yEl.on("mouseout", function(e){
		x = e.clientX;
		y = e.clientY;
		
		clearTimeout(timeout);
		panel.hide();
	    });
    }

}


function makeBusyWindow(div){
  
  var panel = new YAHOO.widget.Panel("wait",
				     { width:"240px",
				       close:false,
				       draggable:false,
				       zindex:99999,
				       visible:false,
				       modal: true
				     }
				    );
  
  panel.setHeader("Loading...");
  panel.setBody('<img src="media/loading.gif" />');
  
  panel.render(YAHOO.util.Dom.get(div));
  
  return panel;
  
}

</script>
