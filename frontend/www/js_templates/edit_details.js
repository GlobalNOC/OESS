<script>

function makeSlider(){
  var slider = YAHOO.widget.Slider.getHorizSlider("sliderbg", "sliderthumb", 0, 200);
  
  slider.getRealValue = function() {     
    return this.getValue() * 50000000;
  };
  
  slider.setRealValue = function(input) {             
    var v = parseFloat(input, 10) / 50000000;  
    return this.setValue(v);                   
  };
  
  slider.subscribe("change", function(){		     
                     var el        = YAHOO.util.Dom.get('slider-value');
		     var units     = YAHOO.util.Dom.get('slider-value-units');
		     var value     = this.getRealValue();

		     if (value >= 1000000000){
			 el.value        = this.getRealValue() / 1000000000;
			 units.innerHTML = "Gbps";
		     }
		     else{
			 el.value        = this.getRealValue() / 1000000;
			 units.innerHTML = " Mbps";
		     }

		   });		  
  
  return slider; 
}


function init(){
  
    var restore_to_primary = new YAHOO.widget.Button("restore_to_primary_button",{ 
        type: "button",
        label: "Off"
    });
    restore_to_primary.on('click', function(){
        if(document.getElementById("restore_to_primary_holder").style.display == "inline"){
            document.getElementById("restore_to_primary_holder").style.display = "none";
            document.getElementById('restore_to_primary').value = 0;
            this.set('label','Off');
        }
        else{
            document.getElementById("restore_to_primary_holder").style.display = "inline";
            this.set('label','On');
        }
        
	});
    var static_mac_routing = new YAHOO.widget.Button("static_mac_routing_button",{ 
        type: "button",
        label: "Off"
    });
    static_mac_routing.on('click', function(){
        if(this.get("label") == "On"){
            this.set('label','Off');
        }else{
            this.set('label','On');
        }
	});

  setPageSummary("Basic Details", "Add Information");

  setNextButton("Proceed to Step 2: Endpoints", "?action=endpoints", verify_inputs);  
  
  var slider = makeSlider();
  
  slider.setRealValue(session.data.bandwidth || 0.0);

  var slider_value = new YAHOO.util.Element(YAHOO.util.Dom.get('slider-value'));

  slider_value.on('change', function(){

	  var value = this.get('element').value;

	  if (value == "") value = "0";

	  var matches = value.match(/(\d+(\.\d+)?)\s*(M|G)?/i);

	  if (! matches){
	      return;
	  }

	  var number = matches[1];
	  var units  = matches[3];

	  // try to guess what units we're talking about
	  if (! units){
	      if (number <= 10){
		  units = "G";		 
	      }
	      else{ 
		  units = "M";
	      }
	  }

	  if (units.toUpperCase() == "G"){
	      slider.setRealValue(number * 1000000000);
	  }
	  else{
	      slider.setRealValue(number * 1000000);
	  }

      });

  YAHOO.util.Dom.get('description').value = session.data.description || "";
  YAHOO.util.Dom.get('restore_to_primary').value = session.data.restore_to_primary || 0;
  if(YAHOO.util.Dom.get('restore_to_primary').value > 0){
      restore_to_primary.set('label','On');
      document.getElementById("restore_to_primary_holder").style.display = "inline";
  }
  
  YAHOO.util.Dom.get('static_mac_routing_button').value = session.data.static_mac_routing || 0;
  if(YAHOO.util.Dom.get('static_mac_routing_button').value > 0){
      static_mac_routing.set('label','On');
  }


  var chosen_tagging = session.data.tagging || "ptp";
 
  hookupRadioButtons("tagging", chosen_tagging, function(){
	               if (document.getElementsByName('tagging')[1].checked){
			   document.getElementsByName('tagging')[0].checked = true;
			   alert("Q-in-Q is not supported at this time.");
		       }
                     });
  
  var bandwidth_holder = new YAHOO.util.Element(YAHOO.util.Dom.get("reserved_bandwidth_holder"));
  var chosen_domain    = session.data.interdomain || "0";
  
  if (chosen_domain == 0){
      bandwidth_holder.setStyle("display", "none");
  }else {
    static_mac_routing.set("checked", false);
    static_mac_routing.set("disabled", true);
  }

  hookupRadioButtons("interdomain", chosen_domain, function(){

		       if (document.getElementsByName('interdomain')[1].checked){
			   setNextButton("Proceed to Step 2: Endpoints", "?action=interdomain", verify_inputs);  
			   bandwidth_holder.setStyle("display", "table-row");
               static_mac_routing.set("checked", false);
               static_mac_routing.set("disabled", true);
		       }
		       else{
			   setNextButton("Proceed to Step 2: Endpoints", "?action=endpoints", verify_inputs);  			   
			   bandwidth_holder.setStyle("display", "none");
               static_mac_routing.set("disabled", false);
		       }
		     });


  if (document.getElementsByName('interdomain')[1].checked){
      setNextButton("Proceed to Step 2: Endpoints", "?action=interdomain", verify_inputs);  
  }
  else{
      setNextButton("Proceed to Step 2: Endpoints", "?action=endpoints", verify_inputs);  			   
  }


  // can't change domain style in a particular circuit
  if (session.data.circuit_id){
      YAHOO.util.Dom.get("interdomain_holder").style.display = "none";
  }

  
  function verify_inputs(){

    var description = YAHOO.util.Dom.get('description').value;
  
    if (! description){
      alert("You must enter a description.")
      return;
    }
    
    session.data.description  = description;
  
    var bandwidth = slider.getRealValue();
        
    var tagging_types = document.getElementsByName('tagging');
    
    var tagging = tagging_types[0].checked ? tagging_types[0].value : tagging_types[1].value;
  
    var domain_options  = document.getElementsByName('interdomain');
    
    var interdomain = domain_options[0].checked ? domain_options[0].value : domain_options[1].value;
  
    var restore_to_primary = document.getElementById('restore_to_primary').value;
   
    if(restore_to_primary == ''){
    	restore_to_primary = 0;
    }else{
    	restore_to_primary = parseInt(restore_to_primary);
    }
    session.data.restore_to_primary = restore_to_primary;

    var static_mac = 0;
    if(static_mac_routing.get("label") == 'On'){
    	static_mac = 1;
    }
    session.data.static_mac_routing = static_mac;

    // OSCARS will require you to do at least 50M bandwidth and will fail to find a path if you 
    // give it 0 bandwidth
    if (interdomain == 1 && bandwidth == 0){
	bandwidth = 50 * 1000 * 1000;
    }

    session.data.bandwidth    = bandwidth;
    session.data.tagging      = tagging;
    session.data.interdomain  = interdomain;

    session.save();
  
    return true;

  }
  

  // hookup some help stuff
  makeHelpPanel(["description", "edit_description_label"], "This is the human readable description for the circuit. Its only purpose is to be meaningful to you.");

  makeHelpPanel(["edit_reserved_bandwidth_label", "slider-value", "sliderbg"], "This is the amount of bandwidth this circuit will have allocated to it across the Openflow network.");

  makeHelpPanel(["tagging_label", "tagging-ptp", "tagging-qnq"], "This is the type of tagging you would like to use. Point to Point will let you individually assign VLAN tags to each endpoint. Q-in-Q tunnel will tell the system to forward all VLANs coming in one endpoint to the other(s).<br><br>Note at this time that Q-in-Q tunnels are not supported.");

  makeHelpPanel(["type_label", "interdomain-no", "interdomain-yes"], "This is used to indicate whether or not this circuit will be provisioned across multiple domains.");
  
}

YAHOO.util.Event.onDOMReady(init);

</script>
