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

function makeTagSelectPanel(coordinates, interface){
    var panel = new YAHOO.widget.Panel("tag_selection", 
				       {
					   width: 280,
					   xy: coordinates
				       }
				       );
    
    
    panel.setHeader("VLAN Tag for Interface " + interface);
    panel.setBody("<label class='soft_title' for='new_vlan_tag'>VLAN Tag:</label>" +
		  "<input id='new_vlan_tag' type='text' value='' size='4'>" +
		  "<div id='add_new_vlan_tag_button'></div>" + 
		  "<br>" + 
		  "<label for='tagged' class='soft_title' style='padding-left: 16px;'>Tagged:</label>" + 
		  "<input id='tagged' type='checkbox' checked='checked'>"
		  );
    
    panel.render(document.body);


    var vlan_input = YAHOO.util.Dom.get('new_vlan_tag');
    
    vlan_input.focus();
    
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
    
    return {panel: panel, add_button: add_tag_button, tagged_input: tagged};
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