<script>
  
function legend_init(map_object, include_active, use_non_important){
  
  YAHOO.util.Dom.get('legend_node_selected').src = map_object.SELECTED_IMAGE;

  if (use_non_important){
      YAHOO.util.Dom.get('legend_node_unselected').src = map_object.NON_IMPORTANT_IMAGE;
      YAHOO.util.Dom.get('legend_node_unselected_text').innerHTML = "Unused Endpoint";
  }
  else{
      YAHOO.util.Dom.get('legend_node_unselected').src = map_object.UNSELECTED_IMAGE;
      YAHOO.util.Dom.get('legend_node_unselected_text').innerHTML = "Available Endpoint";
  }

  if (include_active){
      YAHOO.util.Dom.get('legend_node_active').src = map_object.ACTIVE_IMAGE;
  }
  else{
      YAHOO.util.Dom.get('legend_node_active').parentNode.style.display = "none";
  }
  
  YAHOO.util.Dom.get('legend_link_primary').style.backgroundColor = map_object.LINK_PRIMARY;
  YAHOO.util.Dom.get('legend_link_secondary').style.backgroundColor = map_object.LINK_SECONDARY;
  YAHOO.util.Dom.get('legend_link_unselected').style.backgroundColor = map_object.LINK_UP;
  YAHOO.util.Dom.get('legend_link_down').style.backgroundColor = map_object.LINK_DOWN;
  
}

</script>