<script>
  
function legend_init(map_object, include_active, use_non_important, include_looped, include_maint){
  
    YAHOO.util.Dom.getElementsByClassName('legend_node_selected').map(function(elem) {
            elem.src = map_object.SELECTED_IMAGE;
        });

  if (use_non_important){
      YAHOO.util.Dom.getElementsByClassName('legend_node_unselected').map(function(elem) {
          elem.src = map_object.NON_IMPORTANT_IMAGE;
          });
      YAHOO.util.Dom.getElementsByClassName('legend_node_unselected_text').map(function(elem) {
          elem.innerHTML = "Unused Endpoint";
          });
  } else{
      YAHOO.util.Dom.getElementsByClassName('legend_node_unselected').map(function(elem) {
          elem.src = map_object.UNSELECTED_IMAGE;
          });
      YAHOO.util.Dom.getElementsByClassName('legend_node_unselected_text').map(function(elem) {
          elem.innerHTML = "Available Endpoint";
          });
  }

  if (include_active){
      YAHOO.util.Dom.getElementsByClassName('legend_node_active').map(function(elem) {
          elem.src = map_object.ACTIVE_IMAGE;
          });
  } else {
      YAHOO.util.Dom.getElementsByClassName('legend_node_active').map(function(elem) {
          elem.parentNode.style.display = "none";
          });
  }
  
  if (include_looped){
      YAHOO.util.Dom.getElementsByClassName('legend_node_looped').map(function(elem) {
          elem.src = map_object.LOOPED_IMAGE;
          });
  } else {
      YAHOO.util.Dom.getElementsByClassName('legend_node_looped').map(function(elem) {
          elem.parentNode.style.display = "none";
          });
  }

  if (include_maint) {
      YAHOO.util.Dom.getElementsByClassName('legend_node_maint').map(function(elem) {
          elem.src = map_object.MAINT_IMAGE;
          });
  } else {
      YAHOO.util.Dom.getElementsByClassName('legend_node_maint').map(function(elem) {
              elem.parentNode.style.display = "none";
          });
  }

  // YAHOO.util.Dom.get('legend_link_primary').style.backgroundColor = map_object.LINK_PRIMARY;
  YAHOO.util.Dom.getElementsByClassName('legend_link_primary').map(function(elem) {
          elem.style.backgroundColor = map_object.LINK_PRIMARY;
      });
  YAHOO.util.Dom.getElementsByClassName('legend_link_secondary').map(function(elem) {
          elem.style.backgroundColor = map_object.LINK_SECONDARY;
      });
  YAHOO.util.Dom.getElementsByClassName('legend_link_unselected').map(function(elem) {
          elem.style.backgroundColor = map_object.LINK_UP;
      });
  YAHOO.util.Dom.getElementsByClassName('legend_link_down').map(function(elem) {
          elem.style.backgroundColor = map_object.LINK_DOWN;
      });
  YAHOO.util.Dom.getElementsByClassName('legend_link_majority_up').map(function(elem) {
          elem.style.backgroundColor = map_object.MAJORITY_LINK_UP;
      });
  YAHOO.util.Dom.getElementsByClassName('legend_link_majority_down').map(function(elem) {
          elem.style.backgroundColor = map_object.MAJORITY_LINK_DOWN;
      });
  YAHOO.util.Dom.getElementsByClassName('legend_link_maint').map(function(elem) {
          elem.style.backgroundColor = map_object.LINK_MAINT;
      });
  
}

</script>
