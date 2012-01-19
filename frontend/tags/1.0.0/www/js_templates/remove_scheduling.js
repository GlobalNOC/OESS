<script>

function showDisplay(element, date){

    var el = YAHOO.util.Dom.get(element);

    el.style.display = "inline";

    el.innerHTML = date.toUTCString();

}

// closure function for the time selection callbacks
function timeSelectionHandler(radio_group_name, display_element_id){

    // keep a higher reference to these so we can destroy whenever we click on other things
    var calendar, calendar_panel, calendar_button;
  
    return function(e){

	if (calendar_panel){
	    calendar_panel.destroy();
	    calendar_panel = null;
	}
	
	var provision_time_display = YAHOO.util.Dom.get(display_element_id);

	var previous_selected_time = document.getElementsByName(radio_group_name)[1].value;

	// clicked on now, hide extra time info
	if (document.getElementsByName(radio_group_name)[0].checked){
	    provision_time_display.style.display = "none";
	}
	// clicked on later, show calendar
	else{
	    
	    var region = YAHOO.util.Dom.getRegion(e.target);

	    var elements = makeCalendarPopup([region.left, region.top + 15], previous_selected_time);

	    calendar_panel = elements.panel;
	    
	    calendar = elements.calendar;
	    
	    calendar_button = elements.button;
	    
	    calendar_button.on("click", function(){

		    var selected = calendar.getSelectedDates();

		    if (! selected || selected.length < 1){
			alert("You must specify a day.");
			return;
		    }
		    
		    var time = selected[0];
		    
		    var hour = YAHOO.util.Dom.get('hour');
		    
		    var hour_value = parseInt(hour.options[hour.selectedIndex].value);
		    
		    var minute = YAHOO.util.Dom.get('minute');
		    
		    var minute_value = parseInt(minute.options[minute.selectedIndex].value);
		    
		    time.setUTCHours(hour_value);
		    time.setUTCMinutes(minute_value);
		    
		    var now = new Date();
		    
		    if (time.valueOf() < now.valueOf()){
			alert("You must pick a time in the future.");
			return;
		    }

		    showDisplay(provision_time_display, time);
		    
		    // store the value in the radio button
		    e.target.value = time.valueOf();
		    
		    calendar_panel.hide();

		});
	    
	}
    };
}

function init(){  

  setPageSummary("Scheduling","Choose when this circuit should be created and removed.");
  
  setNextButton("Proceed to Step 2: Provisioning", "?action=remove_provisioning", verify_inputs);
  // defined in circuit_details_box.js
  var endpoint_table = summary_init();
   
  var nddi_map = new NDDIMap("map", session.data.interdomain == 1);

  var layout = makePageLayout(nddi_map, {map_width: Math.min(session.data.map_width, 600),
					 max_resize: 600});

  
  legend_init(nddi_map);
    
  nddi_map.showDefault();
  
  nddi_map.on("loaded", function(){
		this.updateMapFromSession(session);

		if (session.data.interdomain == 1){
		    this.connectSessionEndpoints(session);		    
		}

	      });

  if (session.data.remove_time){

      var radios = document.getElementsByName("remove_time");

      if (session.data.remove_time != -1){
	  radios[1].value = session.data.remove_time;
	  radios[1].checked = true;

	  showDisplay("remove_time_display", new Date(session.data.remove_time));
      }

  }
 
  hookupRadioButtons("remove_time", session.data.remove_time || -1, timeSelectionHandler("remove_time", "remove_time_display"));
  
  function verify_inputs(){      

       var remove_radios    = document.getElementsByName('remove_time');
      
      var remove_time;
            
      // now
      if (remove_radios[0].checked){
	  remove_time = -1;
      }
      // future
      else{
	  remove_time = parseInt(remove_radios[1].value);
      }
            
      if (! remove_time || isNaN(remove_time)){
	  alert("Invalid remove time. Please select one from the options provided.");
	  return;
      }  

      session.data.remove_time    = remove_time;
      
      session.save();
            
      return true;
  }
  
}

YAHOO.util.Event.onDOMReady(init);

  
</script>