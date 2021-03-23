<script>

function NDDIMap(div_id, interdomain_mode, options){
  this.options = options || {};
  if(this.options.node_label_status === undefined) this.options.node_label_status = true;

  this.MAINT_IMAGE    = "[% path %]media/teal-circle.png";
  this.UNSELECTED_IMAGE    = "[% path %]media/blue-circle.png";
  this.SELECTED_IMAGE      = "[% path %]media/orange-circle.png";
  this.ACTIVE_IMAGE        = "[% path %]media/yellow-circle.png";
  this.NON_IMPORTANT_IMAGE = "[% path %]media/gray-circle.png";
  this.LINK_COUNT_IMAGE = "[% path %]media/gray-square.png";
  this.LOOPED_IMAGE = "[% path %]media/purple-circle.png";

  this.LINK_UP            = "#3158a7"; //blue
  this.LINK_DOWN          = "#b46253"; //red
  this.LINK_LOOPED        = "#9c1cb4"; //purple
  this.MAJORITY_LINK_UP   = "#CCD20F"; //yellow
  this.MAJORITY_LINK_DOWN = "#E59916"; //orange
  this.LINK_PRIMARY       = "#b7f33b";//"#DEA567";
  this.LINK_SECONDARY     = "#557416";//"#2b882c";
  this.LINK_TERTIARY      = "#00FF00";
  this.LINK_MAINT         = "#00ABA9";     //teal

  this.ACTIVE_HALO_COLOR   = "#f47e20";//"#FFFFCC";//"#DADADA";
  this.INACTIVE_HALO_COLOR = "#666666";
  this.UNKNOWN_HALO_COLOR  = "#A0A0A0";

  this.ACTIVE_LINK_WIDTH   = 5.5;
  this.INACTIVE_LINK_WIDTH = 3.0;

  this.ACTIVE_LINK_OPACITY   = 1.0;
  this.INACTIVE_LINK_OPACITY = 1.0;
  this._initialized = false;
  var name_of_loop; 
  // keep a reference to ourselves to use in various callbacks
  var self = this;

  this.events = {};

  this.events['clickNode'] = new YAHOO.util.CustomEvent("clickNode", this);
  this.events['clickLink'] = new YAHOO.util.CustomEvent("clickLink", this);
  this.events['hoverNode'] = new YAHOO.util.CustomEvent("hoverNode", this);
  this.events['hoverLink'] = new YAHOO.util.CustomEvent("hoverLink", this);
  this.events['loaded']    = new YAHOO.util.CustomEvent("loaded", this);

  this.on = function(event_name, callback){
    if (this.events[event_name]){
      this.events[event_name].subscribe(callback);
    }
  };

  this.destroy = function(){
      this.map.destroy();
      this.map = null;
  };

  this.calculateZoomLevel = function(width){
      var zoomLevel = Math.max(2, parseInt(width / 182, 10) + 1);

      return zoomLevel;
  };

  this.getInterDomainPath = function(circuit_id, element){

      if (element){
          element.innerHTML = "Querying interdomain path....";
      }

      var ds = new YAHOO.util.DataSource("services/remote.cgi?action=query_reservation&circuit_id="+circuit_id);
      ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
      ds.responseSchema = {
          resultsList: "results",
          fields: [{key: "status"},
                   {key: "message"},
                   {key: "path"}
                   ]
      }

      var self = this;

      ds.sendRequest("",
                     {
                       success: function(req, resp){

                           var endpoints = resp.results[0].path;

                           for (var i = 0; i < endpoints.length; i++){

                               var from_node = endpoints[i].from_node;
                               var from_lat  = parseFloat(endpoints[i].from_lat);
                               var from_lon  = parseFloat(endpoints[i].from_lon);

			       var to_node   = endpoints[i].to_node;
                               var to_lat    = parseFloat(endpoints[i].to_lat);
                               var to_lon    = parseFloat(endpoints[i].to_lon);

                               if (from_node == to_node){
                                   continue;
                               }

			       self.showNode(from_node, null, {"node_lat": from_lat, "node_long": from_lon});
                               self.showNode(to_node, null, {"node_lat": to_lat, "node_long": to_lon});

                               self.connectEndpoints([from_node, to_node]);
                           }

                           if (element){
                               element.innerHTML = "Total Interdomain Path";
			   }

                       },
                       failure: function(req, resp){
                             if (element){
			         element.innerHTML = "Unable to query interdomain path.";
                             }
                       }
                   }
                   );

  };

    this.showDefault = function(){

	var bounds = new OpenLayers.Bounds();
	
	for(var i=0;i< this.map.layers[1].features.length; i++){
	    var feature = this.map.layers[1].features[i];
	    
	    if(feature.geometry.y != null || feature.geometry.x != null){
		
		var lat = feature.geometry.y;
		var lon = feature.geometry.x;
		
		var latlon = new OpenLayers.LonLat(lon - 200000, lat - 200000);
		bounds.extend(latlon);
		
		latlon = new OpenLayers.LonLat(lon + 200000, lat + 200000);
		bounds.extend(latlon);
	    }
	    
	}
	
	this.map.zoomToExtent(bounds, false);
	
  };

  // connects all given nodes regardless of if they have an actual link
  this.connectEndpoints = function(nodes){

      for (var i = 0; i < nodes.length; i++){

	  var nodeA = nodes[i];

	  for (var j = 0; j < nodes.length; j++){

	      var nodeZ = nodes[j];

	      var name;

	      if (nodeA < nodeZ){
		  name = nodeA + " <=> " + nodeZ;
	      }
	      else {
		  name = nodeZ + " <=> " + nodeA;
	      }

	      this._drawLink(nodeA, nodeZ, name, "up", 0, -1, null, {"active": true});

	  }

      }


  };

  this._findNode = function(node_name){
      // first find the node we're talking about
      for (var i = 0; i < this.cache.length; i++){

	  var nodes   = this.cache[i].nodes;
	  var network = this.cache[i].meta;

	  for (var node in nodes){
	      if (node == node_name){
		  return {"node": nodes[node], "network": network};
	      }
	  }
      }

  };

  this.isFeatureDrawn = function(feature_name){

      for (var i = 0; i < this.map.layers[1].features.length; i++){
	  var feature = this.map.layers[1].features[i];

	  if (feature.geometry && feature.geometry.element_name == feature_name){
	      return 1;
	  }
      }

      return 0;

  };

  this.removeNode = function(node_name){

      if (! this.isFeatureDrawn(node_name)){
	  return 1;
      }

      for (var i = this.map.layers[1].features.length - 1; i > -1; i--){

	  var feature = this.map.layers[1].features[i];

	  if (! feature.geometry){
	      continue;
	  }

	  var el_name = feature.geometry.element_name;

	  if (el_name == node_name){
	      this.map.layers[1].removeFeatures([feature]);
	      this.removeNodeLinks(node_name);
	  }

	  // remove any manually drawn links to or from this node via
	  // the connectEndpoints calls
	  var re  = new RegExp(node_name + " <=>");
	  var re2 = new RegExp("<=> " + node_name);

	  if (re.test(el_name) || re2.test(el_name)){
	      this.map.layers[1].removeFeatures([feature]);
	  }

	  // we might be looking at one of the extra link features such as halo
	  else if (feature.primary_feature){
	      var primary_name = feature.primary_feature.geometry.element_name;

	      if (re.test(primary_name) || re2.test(primary_name)){
		  this.map.layers[1].removeFeatures([feature]);
	      }

	  }

      }

  }


  this.showNode = function(node_name, draw_other_data, node_info, keep_map_position, loop_node){

      if (this.isFeatureDrawn(node_name)){
	  return 1;
      }

      // if we weren't given node info, try to find it in our cache
      if (! node_info){
	  node_info = this._findNode(node_name);

	  if (node_info){
	      node_info = node_info["node"];
	  }
      }

      // still nothing, abort
      if (! node_info){
	  return;
      }
	  
      var node_lat   = parseFloat(node_info.node_lat);
      var node_long  = parseFloat(node_info.node_long);
      var node_id    = parseInt(node_info.node_id || -1);
      var vlan_range = node_info.vlan_range;
      var end_epoch  = node_info.end_epoch;
      var default_drop = node_info.default_drop;
      var default_forward = node_info.default_forward;
      var tx_delay_ms = node_info.tx_delay_ms;
      var max_flows = node_info.max_flows;
      var openflow = node_info.openflow;
      var mpls       = node_info.mpls;
      var mgmt_addr  = node_info.mgmt_addr;
      var tcp_port   = node_info.tcp_port;
      var vendor     = node_info.vendor;
      var model      = node_info.model;
      var sw_version = node_info.sw_version;
      var controller = node_info.controller;
      var short_name = node_info.short_name;
      var avail_endpoints = node_info.number_available_endpoints;
      var barrier_bulk = node_info.barrier_bulk;
      var max_static_mac_flows = node_info.max_static_mac_flows;
      var dpid = node_info.dpid;
      var in_maint = node_info.in_maint;
      var pointStyle = OpenLayers.Util.extend({}, OpenLayers.Feature.Vector.style['default']);
	  
      pointStyle.strokeColor      = "#00FF00";
      pointStyle.fillColor        = "#00FF00";
      pointStyle.fillOpacity      = 0.9;
      pointStyle.strokeWidth      = 2;
      pointStyle.pointRadius      = 6;
      pointStyle.strokeDashstyle  = "solid";
      pointStyle.cursor           = "hand";
      if (in_maint == 'no') {
        pointStyle.externalGraphic  = this.UNSELECTED_IMAGE;
      }
      else {
        pointStyle.externalGraphic = this.MAINT_IMAGE;
      }
      pointStyle.graphicZIndex    = 10;

	  if (avail_endpoints < 1 || avail_endpoints === undefined){
		  
		  pointStyle.strokeColor      = "#C0C0C0";
		  pointStyle.fillColor        = "#C0C0C0";
		  pointStyle.cursor = "";
		  pointStyle.externalGraphic = this.NON_IMPORTANT_IMAGE;
	  }
	  
      //if (loop_node != undefined && loop_node == node_id) {

      if (session.data.loop_node == node_id) {

            name_of_loop = node_name; 
        } 

      var lonlat = new OpenLayers.LonLat(node_long, node_lat).transform(this.map.displayProjection,
									this.map.projection);


      var point = new OpenLayers.Geometry.Point(lonlat.lon, lonlat.lat);
      point.element_name = node_name;
      point.element_lat  = node_lat;
      point.element_lon  = node_long;
      point.element_id   = node_id;
      point.vlan_range   = vlan_range;
      point.default_drop = default_drop;
      point.default_forward = default_forward;
      point.tx_delay_ms = tx_delay_ms;
      point.max_flows = max_flows;
      point.openflow = openflow;
      point.mpls       = mpls;
      point.mgmt_addr  = mgmt_addr;
      point.tcp_port   = tcp_port;
      point.vendor     = vendor;
      point.model      = model;
      point.short_name = short_name;
      point.sw_version = sw_version;
      point.controller = controller;
      point.barrier_bulk = barrier_bulk;
      point.max_static_mac_flows = max_static_mac_flows;
      point.dpid = dpid;
	  point.available_endpoints = avail_endpoints;
      point.oess_point_type = "node";
      point.end_epoch = end_epoch;
      var pointFeature  = new OpenLayers.Feature.Vector(point,
							null,
							pointStyle
							);

      this.map.layers[1].addFeatures([pointFeature]);

      this.showNodeLinks(node_name, draw_other_data);

      // now that we've drawn it, see if it's outside the current viewport. if so, readjust to show it
      var current_extent = this.map.getExtent();

      var bounds = new OpenLayers.Bounds();

      // iterate through every node drawn and build up a big bounds representing their accumulated
      // extent in the map
      for (var i = 0; i < this.map.layers[1].features.length; i++){

	  var feature = this.map.layers[1].features[i];

	  // nodes only, not links
	  //if (feature.geometry.id.indexOf('Point') != -1){
	  if (feature.geometry.oess_point_type == "node"){

	      var lat = feature.geometry.element_lat;
	      var lon = feature.geometry.element_lon;

	      var node_lonlat = new OpenLayers.LonLat(lon, lat).transform(this.map.displayProjection,
									  this.map.projection);

	      bounds.extend(node_lonlat);

	  }

      }
        
      // if we're not showing everything, try to show it, unless keep_map_position is set to true
      if (!keep_map_position){
        if (current_extent && ! current_extent.containsBounds(bounds)){
	        this.map.zoomToExtent(bounds);
        }
      }



      return 1;
  };

  // return an array of link information for all the links that the given node
  // is a part of
  this._getNodeLinks = function(node_name){
      var links = [];

      for (var i = 0; i < this.cache.length; i++){

	  var possible_links = this.cache[i].links;

	  for (var from_node in possible_links){

	      var node_links = possible_links[from_node];

	      for (var j = 0; j < node_links.length; j++){

		  var link_data = node_links[j];

		  if (from_node == node_name || link_data['to'] == node_name){
		      links.push(link_data);
		  }
	      }

	  }
      }


      return links;
  }

  this.removeNodeLinks = function(node_name){

      var links = this._getNodeLinks(node_name);

      for (var i = 0; i < links.length; i++){

	  var link_name = links[i]['link_name'];

	  for (var j = this.map.layers[1].features.length - 1; j > -1; j--){

	      var feature = this.map.layers[1].features[j];

	      if (feature.geometry && feature.geometry.element_name == link_name){
		  this.map.layers[1].removeFeatures([feature]);
	      }

	      // we might be looking at one of the extra link features such as halo
	      else if (feature.primary_feature && feature.primary_feature.geometry.element_name == link_name){
		  this.map.layers[1].removeFeatures([feature]);
	      }

	  }
      }

  }

  this.showNodeLinks = function(node_name, draw_other_data){

      // can't show links if the node isn't drawn
      if (! this.isFeatureDrawn(node_name)){
	  return 0;
      }

      var links = this._getNodeLinks(node_name);

      for (var j = 0; j < links.length; j++){

	  var link_data = links[j];

	  var from_node     = node_name;
	  var to_node       = link_data['to'];
	  var state         = link_data['link_state'];
	  var capacity      = link_data['capacity'];
	  var link_name     = link_data['link_name'];
	  var link_id       = link_data['link_id'];
      var maint_epoch   = link_data['maint_epoch']; 

	  if (node_name == to_node){
	      continue;
	  }

	  this._drawLink(from_node, to_node, link_name, state, capacity, link_id, maint_epoch, draw_other_data);

      }
      //need to do this so the initial link count label doesn't appear, if you don't it will get cached and that's what's used
      this.map.layers[1].redraw(true);
  };

  this._drawLink = function(from_node, to_node, link_name, state, capacity, link_id, maint_epoch, options){

          options = options || {};

	  // already drawn, don't redraw
	  if (this.isFeatureDrawn(link_name)){
	      return;
	  }

	  var node_info       = this._findNode(from_node);
	  var other_node_info = this._findNode(to_node);

	  if (! node_info || ! other_node_info){
	      return;
	  }

	  // the other side isn't drawn, figure out what to do
	  if (! this.isFeatureDrawn(to_node)){

	      if (options){

		  if (options.network == other_node_info.network.network_name){
		      this.showNode(to_node);
		  }
		  else {
		      return;
		  }
	      }
	      else {
		  return;
	      }

	  }

      // already have a link in between the two nodes
      // need to modify the link to have a generic name and an option list of links when clicked
      var link_data = {
          from_node: from_node, 
          to_node:   to_node, 
          link_name: link_name, 
          state: state, 
          capacity: capacity, 
          link_id: link_id,
          maint_epoch: maint_epoch, 
          options: options
      };

      if( this.linkOverlaps( link_data ) ){ return };

	  node_info       = node_info["node"];
	  other_node_info = other_node_info["node"];

	  var from_long = parseFloat(node_info.node_long);
	  var from_lat  = parseFloat(node_info.node_lat);
	  var to_long   = parseFloat(other_node_info.node_long);
	  var to_lat    = parseFloat(other_node_info.node_lat);

	  // transform to projection
	  var lonlat    = new OpenLayers.LonLat(from_long, from_lat).transform(this.map.displayProjection,
									       this.map.projection);

	  from_long = lonlat.lon;
	  from_lat  = lonlat.lat;

	  lonlat  = new OpenLayers.LonLat(to_long, to_lat).transform(this.map.displayProjection,
								     this.map.projection);

	  to_long = lonlat.lon;
	  to_lat  = lonlat.lat;

	  var dy     = to_lat - from_lat;
	  var dx     = to_long - from_long;
	  var length = Math.sqrt(dx * dx + dy * dy);

	  if (length > 0){
	      dx /= length;
	      dy /= length;
	  }

	  var from_ll = new OpenLayers.Geometry.Point(from_long + dx,
						      from_lat + dy
						      );

	  var to_ll = new OpenLayers.Geometry.Point(to_long - dx,
						    to_lat - dy
						    );


	  // create the base line representing this link
	  //
	  var line = new OpenLayers.Geometry.LineString([from_ll, to_ll]);

	  line.element_name    = link_name;
	  line.link_capacity   = capacity;
	  line.link_state      = state;
	  line.element_id      = link_id;
      line.maint_epoch     = maint_epoch;
      line.links           = [];

      var stroke_Color;

      if (state == "down") {
            stroke_Color = this.LINK_DOWN;
        }

      else if( state =="looped") {
        stroke_Color = this.LINK_LOOPED;
      }
      else {
        if (maint_epoch == -1) {
            stroke_Color =this.LINK_MAINT;
        }
        else {
            stroke_Color =this.LINK_UP;
        }
      }

	  var style = {
          strokeColor: stroke_Color,
	      //strokeColor: (state == "down" ? this.LINK_DOWN : this.LINK_UP),
	      strokeOpacity: 1.0,
              strokeDashstyle: "solid",
	      strokeWidth: 3.5,
	      cursor: "hand",
	      graphicZIndex: 5
	  };


	  var feature = new OpenLayers.Feature.Vector(line, null, style);

	  // now make the "halo" line below each line
	  //
	  var halo = new OpenLayers.Geometry.LineString([from_ll, to_ll]);
	  halo.element_name  = "halo_line";
	  halo.link_capacity = 0;
	  halo.link_state    = 'na';

	  var halo_style = {
	      strokeWidth: 4.5,
	      strokeOpacity: 0.0,
	      strokeColor: this.INACTIVE_HALO_COLOR,
	      graphicZIndex: 5
	  };


	  var halo_feature = new OpenLayers.Feature.Vector(halo, null, halo_style);


	  // now make the "secondary path" feature above each line
	  //
	  var secondary_path = new OpenLayers.Geometry.LineString([from_ll, to_ll]);
	  secondary_path.element_name  = link_name;
	  secondary_path.link_capacity = capacity;
	  secondary_path.link_state    = state;

	  var secondary_style = {
	      strokeWidth: style.strokeWidth,
	      strokeOpacity: 0.0,
	      strokeDashstyle: "dash",
	      strokeColor: this.LINK_SECONDARY,
	      graphicZIndex: 6
	  };

	  var secondary_path_feature = new OpenLayers.Feature.Vector(secondary_path, null, secondary_style);
	  secondary_path_feature.type = "secondary";

          // now make the "tertiary path" feature above each line
          //
          var tertiary_path = new OpenLayers.Geometry.LineString([from_ll, to_ll]);
          tertiary_path.element_name  = link_name;
          tertiary_path.link_capacity = capacity;
          tertiary_path.link_state    = state;

          var tertiary_style = {
              strokeWidth: style.strokeWidth,
              strokeOpacity: 0.0,
              strokeDashstyle: "dash",
              strokeColor: this.LINK_TERTIARY,
              graphicZIndex: 6
          };

          var tertiary_path_feature = new OpenLayers.Feature.Vector(tertiary_path, null, tertiary_style);
          tertiary_path_feature.type = "secondary";

	  // lastly make the "fat path" feature that sits on top of everything and is fully transparent to provide a
	  // tolerance zone for clicking and hovering
	  var fat_path = new OpenLayers.Geometry.LineString([from_ll, to_ll]);
	  fat_path.element_name  = "fat_line";
	  fat_path.link_capacity = 0;
	  fat_path.link_state    = "na";

	  var fat_style = {
	      strokeWidth: style.strokeWidth + 10,
	      strokeOpacity: 0.0,
	      graphicZIndex: 5
	  };

	  var fat_feature = new OpenLayers.Feature.Vector(fat_path, null, fat_style);

	  // keep some references to these guys for later
	  feature.halo_feature                = halo_feature;
	  feature.secondary_path_feature      = secondary_path_feature;
          feature.tertiary_path_feature       = tertiary_path_feature;

	  secondary_path_feature.halo_feature    = halo_feature;
	  secondary_path_feature.primary_feature = feature;
          
          tertiary_path_feature.halo_feature = halo_feature;
          tertiary_path_feature.primary_feature = feature;
          
	  halo_feature.primary_feature = feature;

	  fat_feature.primary_feature = feature;

	  // order is important! must make the feature sandwich
          var features = [feature, halo_feature, secondary_path_feature, tertiary_path_feature, fat_feature];
	  this.map.layers[1].addFeatures(features);

	  if (options.active){
	      this.changeLinkColor(feature, this.LINK_PRIMARY);
	      this.showHalo(feature, this.ACTIVE_HALO_COLOR);
	      this.changeLinkOpacity(feature, this.ACTIVE_LINK_OPACITY);
	      this.changeLinkWidth(feature, this.ACTIVE_LINK_WIDTH);
	  }


      // add link to our link overlap list
      var nodes = [from_node, to_node];
      nodes.sort();
      if(this.linkOverlapList[nodes[0]] === undefined) this.linkOverlapList[nodes[0]] = {};
      this.linkOverlapList[nodes[0]][nodes[1]] = {
        features: features,
        links:    [link_data]
      };
      
  };

  this.linkOverlaps = function ( link_data ){
      //sort the nodes for a unique distinct hash
      var nodes = [link_data.from_node, link_data.to_node];
      nodes.sort();

      //return false if there isn't a link defined for these ordered endpoints
      if ( this.linkOverlapList[nodes[0]] === undefined ||
           this.linkOverlapList[nodes[0]][nodes[1]] === undefined ) {
          return false;
      }
      var data = this.linkOverlapList[nodes[0]][nodes[1]];

      // push link_data onto link list
      data.links.push(link_data);

      // for each my
      var html = "";
      for(var i = 0; i < data.links.length; i++){
          var link = data.links[i];
          html += "<div>"+link.link_name+"</div>"
      }
      //overwrite the name on the main line feature so it includes all
      //links colored according to their state
      data.features[0].geometry.links = data.links;
      link_name = "<div class='oess-multilink-map-label'>";
      link_up_count = 0;
      for(var i=0; i<data.links.length; i++){
          //link_name += "<div style='text-shadow: 1px 1px 1px #FFF;color: ";
          if(this.options.node_label_status == true) {
              if(data.links[i].state == "up"){
                  link_up_count++;
                  link_name += "<div style='text-shadow: 1px 1px 1px #FFF;color: "+this.LINK_UP+";'>";
              }
              else if(data.links[i].state == "looped") {
                link_name += "<div style='text-shadow: 1px 1px 1px #FFF;color: "+this.LINK_LOOPED+";'>";
            }
              else {
                  link_name += "<div style='text-shadow: 1px 1px 1px #FFF;color: "+this.LINK_DOWN+";'>";
              }
          }else {
              link_name += "<div>";
          }
          link_name += data.links[i].link_name+"</div>"
      }
      link_name += "</div>";
      //data.features[0].geometry.element_name = "Multiple Links";
      if(data.features[4] === undefined) {
          var link_count_style = OpenLayers.Util.extend({}, OpenLayers.Feature.Vector.style['default']);

          link_count_style.strokeColor      = "#00FF00";
          link_count_style.fontColor        = "#FFFFFF";
          link_count_style.fontSize         = 8;
          link_count_style.fillOpacity      = 1;
          link_count_style.strokeWidth      = 2;
          link_count_style.pointRadius      = 5;
          link_count_style.strokeDashstyle  = "solid";
          link_count_style.cursor           = "hand";
          link_count_style.externalGraphic  = this.LINK_COUNT_IMAGE;
          link_count_style.graphicName      = "square";
          link_count_style.graphicZIndex    = 10;
          link_count_style.label            = 2;

          var lol_lonlat = data.features[0].geometry.getBounds().getCenterLonLat();
          var link_count_point = new OpenLayers.Geometry.Point(lol_lonlat.lon, lol_lonlat.lat);
          link_count_point.oess_point_type == "link_count";
          var link_count  = new OpenLayers.Feature.Vector(link_count_point, null, link_count_style);
          data.features[4] = link_count;
          this.map.layers[1].addFeatures([link_count])
      }else {
        data.features[4].style.label = (parseInt(data.features[4].style.label) +  1);
      }
      data.features[0].geometry.element_name = link_name;
      data.features[0].data.popupContentHTML = html;

      //determine the link status color based on majority of status
      percent_up = (link_up_count / data.links.length) * 100;
      var link_color;
      if( percent_up == 100 ){ //blue if all up
          data.features[0].geometry.link_state = "up";
      }else if( percent_up >= 50 ){ //yellow for majority up
          data.features[0].geometry.link_state = "majority_up";
      }else if( percent_up == 0 ){ //red if all down
          data.features[0].geometry.link_state = "down";
      }else { //orange if majority down
          data.features[0].geometry.link_state = "majority_down";
      }
      data.features[0].style.strokeColor     = link_color; 
      data.features[0].style.strokeDashstyle = "solid";

      return true;
  };

  this.changeLinkWidth = function(link, width){

      if (link.geometry.link_state == "down"){
	  width = this.INACTIVE_LINK_WIDTH;
      }

      this.updateFeature(link, "strokeWidth", width);

      if (link.halo_feature){
	  this.changeLinkWidth(link.halo_feature, Math.max(1, width - 3));
      }
  };

  this.changeLinkOpacity = function(link, opacity){
      this.updateFeature(link, "strokeOpacity", opacity);
  };

  this.changeLinkColor = function(link, color){
      this.updateFeature(link, "strokeColor", color);
  };

  this.changeNodeImage = function(node, image){
    this.updateFeature(node, "externalGraphic", image);
  };

  this.changeLinkDash = function(node, style){
      this.updateFeature(node, "strokeDashstyle", style);
  }

  this.showHalo = function(link, color){
      if (link.geometry.link_state == "down"){
	  return;
      }

      this.changeLinkColor(link.halo_feature, color);
      this.changeLinkOpacity(link.halo_feature, 1.0);
  };

  this.hideHalo = function(link){
      this.changeLinkOpacity(link.halo_feature, 0.0);
  };

  this.updateFeature = function(feature, key, value){
    feature.style[key] = value;
    this.map.layers[1].drawFeature(feature);
  };


  this.clearAllSelected = function(){
	  
      for (var j = 0; j < this.map.layers[1].features.length; j++){
	  var feature = this.map.layers[1].features[j];

	  if (feature.geometry.element_name == "halo_line"){
	      continue;
	  }
	  if (feature.type == "secondary"){
	      continue;
	  }

          if (feature.type == "tertiary"){
              continue;
          }

	  // if this feature is a node, ie a point on the map
	  //if (feature.geometry.id.indexOf('Point') != -1){
	  if (feature.geometry.oess_point_type == "node"){
          if (feature.geometry.end_epoch == -1) { 
	        this.changeNodeImage(feature, this.MAINT_IMAGE);
          }
          else {
	        this.changeNodeImage(feature, this.UNSELECTED_IMAGE);
            }
	  }
	  // otherwise this feature must be a link
	  else{
          if (feature.geometry.maint_epoch == -1) {
            this.changeLinkColor(feature, this.LINK_MAINT);
          }
          else {
	        this.changeLinkColor(feature, this.LINK_UP);
          }
	      this.changeLinkDash(feature, "solid");
	  }
      }

  };

  this.connectSessionEndpoints = function(session){

      var endpoints = [];
      for (var i = 0; i < session.data.endpoints.length; i++){
      endpoints.push(session.data.endpoints[i].node);
      }

      this.connectEndpoints(endpoints);

  };

  this.compare_link_names = function(feature_link, other_link) {
      if(feature_link.indexOf("oess-multilink-map-label") === -1){
        return (feature_link == other_link);
      }
      //handle the case when there are multiple names
      var e = $(feature_link);
      for(var i=0; i < e.children().length; i++){
          var link_name = e.children()[i].innerHTML;
          if(link_name == other_link) return true;
      };
      return false;
  };

    this.setActiveLinks = function(links) {
        for (var i = 0; i < this.map.layers[1].features.length; i++  ) {
            var feature = this.map.layers[1].features[i];

            // All non-point geometries are links
            if (feature.geometry.id.indexOf("Point") == -1) {
                if (feature.geometry.element_name == "fat_line") {
                    continue;
                }
                if (feature.geometry.element_name == "halo_line") {
                    continue;
                }

                for (var j = 0; j < links.length; j++  ) {
                    var link = links[j];

                    if (this.compare_link_names(feature.geometry.element_name, link)) {
                        this.showHalo(feature, this.ACTIVE_HALO_COLOR);
                        this.updateFeature(feature.halo_feature, "strokeOpacity", 1.0);
                        this.updateFeature(feature.halo_feature, "strokeColor", this.ACTIVE_HALO_COLOR);
                        break;
                    } else {
                        this.hideHalo(feature);
                        this.updateFeature(feature.halo_feature, "strokeOpacity", 0.0);
                    }
                }
            }
        }
    };

  // convenience function to update the map based on what we've selected and have
  // stored in our session cookie
  this.updateMapFromSession = function(session, discolor_nodes, keep_map_position){
     
    this.linkOverlapList = {};
    var endpoints   = session.data.endpoints || [];
    var links       = session.data.links || [];
    var backups     = session.data.backup_links || [];
    var tertiarys    = session.data.tertiary_links || [];
    var active_path = session.data.active_path || "none";
    var loop_node   = session.data.loop_node || null;

    // show the nodes
    for (var i = 0; i < endpoints.length; i++){
	    this.showNode(endpoints[i].node,0, 0,  keep_map_position, loop_node);
    }


    for (var j = 0; j < this.map.layers[1].features.length; j++){

      	var feature = this.map.layers[1].features[j];

	if (feature.geometry.element_name == "halo_line"){
	    continue;
	}

        if (feature.geometry.element_name == "fat_line") {
            continue;
        }

	if (feature.type == "secondary"){
	    continue;
	}

        if (feature.type == "tertiary"){
            continue;
        }

	var was_selected = false, dual = false;

	// if this feature is a node, ie a point on the map
	if (feature.geometry.oess_point_type == "node"){

	  for (var i = 0; i < endpoints.length; i++){

	    var node = endpoints[i].node;

	    if (feature.geometry.element_name == node){
	      this.changeNodeImage(feature, this.SELECTED_IMAGE);
	      was_selected = true;
	      break;
	    }

	  }
        if (name_of_loop) {

            if (feature.geometry.element_name == name_of_loop){
              this.changeNodeImage(feature, this.LOOPED_IMAGE);
              was_selected = true;
            }

        }

	  if (! was_selected){
	      if (discolor_nodes){
		  this.changeNodeImage(feature, this.NON_IMPORTANT_IMAGE);
	      }
	      else{
			  if (feature.geometry.available_endpoints < 1)
			  {
				  this.changeNodeImage(feature, this.NON_IMPORTANT_IMAGE);
			  }
			  else {
                  if (feature.geometry.end_epoch == -1) { 
                    this.changeNodeImage(feature, this.MAINT_IMAGE);
                  }
                  else {
				    this.changeNodeImage(feature, this.UNSELECTED_IMAGE);
	              }
			  }
		  }
	  }

	}
	// otherwise this feature must be a link
	else if( feature.geometry.id.indexOf('Point') == -1 ){


	  for (var i = 0; i < links.length; i++){
	    var link = links[i];

	    if (this.compare_link_names(feature.geometry.element_name, link)){
		this.changeLinkColor(feature, this.LINK_PRIMARY);

		if (active_path == "primary"){
		    this.showHalo(feature, this.ACTIVE_HALO_COLOR);
		    this.changeLinkOpacity(feature, this.ACTIVE_LINK_OPACITY);
		    this.changeLinkWidth(feature, this.ACTIVE_LINK_WIDTH);
		}
		else if (active_path == "none"){
		    this.changeLinkOpacity(feature, this.ACTIVE_LINK_OPACITY);
		    this.changeLinkWidth(feature, this.INACTIVE_LINK_WIDTH);
		}
		else{
		    this.hideHalo(feature);
		    this.changeLinkOpacity(feature, this.INACTIVE_LINK_OPACITY);
		    this.changeLinkWidth(feature, this.INACTIVE_LINK_WIDTH);
		}

		was_selected = true;
		break;
	    }

	  }

	  for (var i = 0; i < backups.length; i++){

	    var link = backups[i];

        if (this.compare_link_names(feature.geometry.element_name, link)){
	      // if this was previously selected, we have a doubly used link and should color
	      if (was_selected){
                  if (feature.secondary_path_feature){
                      this.changeLinkOpacity(feature.secondary_path_feature, this.ACTIVE_LINK_OPACITY);
                      this.changeLinkWidth(feature, this.ACTIVE_LINK_WIDTH);
                  }
		  dual = true;
	      }

	      // otherwise this is just a standalone backup link, color it as such
	      else{
		this.changeLinkColor(feature, this.LINK_SECONDARY);

		if (active_path == "backup"){
		    this.showHalo(feature, this.ACTIVE_HALO_COLOR);
		    this.changeLinkOpacity(feature, this.ACTIVE_LINK_OPACITY);
		    this.changeLinkWidth(feature, this.ACTIVE_LINK_WIDTH);
		}
		else if (active_path == "none"){
		    this.changeLinkOpacity(feature, this.ACTIVE_LINK_OPACITY);
		    this.changeLinkWidth(feature, this.INACTIVE_LINK_WIDTH);
		}
		else{
		    this.hideHalo(feature);
		    this.changeLinkOpacity(feature, this.INACTIVE_LINK_OPACITY);
		    this.changeLinkWidth(feature, this.INACTIVE_LINK_WIDTH);
		}

	      }
	      was_selected = true;
	    }

	  }

	  // we have a primary and NOT a secondary, hide the secondary path
	  if (was_selected && ! dual){
	      if (feature.secondary_path_feature){
		  this.changeLinkOpacity(feature.secondary_path_feature, 0.0);
	      }
	  }

	  // wasn't a primary or backup link
	  if (! was_selected){
	      if (feature.geometry.link_state == "down"){
		  this.changeLinkColor(feature, this.LINK_DOWN);
	      }else if(feature.geometry.link_state == "majority_down"){
		  this.changeLinkColor(feature, this.MAJORITY_LINK_DOWN);
          }else if(feature.geometry.link_state == "majority_up"){
		  this.changeLinkColor(feature, this.MAJORITY_LINK_UP);
          }else{
              if (feature.geometry.maint_epoch == -1) {
                this.changeLinkColor(feature, this.LINK_MAINT);
              }
              else {
                this.changeLinkColor(feature, this.LINK_UP);
              }
	      }

	      if (feature.tertiary_path_feature){
		  this.changeLinkOpacity(feature.tertiary_path_feature, 0.0);
	      }

	  }

	}
    }

  };


  this._createMap = function(div_id){
                     OpenLayers.ImgPath = "[% path %]openlayers/theme/dark/";

		     var map = new OpenLayers.Map(div_id,
						  {
						      maxExtent: new OpenLayers.Bounds(-20037508.34,-20037508.34,20037508.34,20037508.34),
						      restrictedExtent: new OpenLayers.Bounds(-20037508.34,-20037508.34,20037508.34,20037508.34),
						      numZoomLevels:8,
						      maxResolution:156543.0339,
						      units:'m',
						      projection: new OpenLayers.Projection("EPSG:900913"),
						      displayProjection: new OpenLayers.Projection("EPSG:4326")

						  });


		     var world_layer = new OpenLayers.Layer.TMS("World", "",
							  {
							      url: "[% path %]tiles/1.0.0/OESS_background/",
							      serviceVersion: ".",
							      layername: ".",
							      alpha: true,
							      type: "png",
							      getURL: function(bounds){

								      var res = this.map.getResolution();
								      var x = Math.round((bounds.left - this.maxExtent.left) / (res * this.tileSize.w));
								      var y = Math.round((bounds.bottom - this.maxExtent.bottom) / (res * this.tileSize.h));

								      var z = this.map.getZoom();

                                      
								      if (x >= 0 && y >= 0) {
                                        
                                        if (z <=2 && (y >= 4)) {
                                            y = y -1;
                                        }

                                        if (z <=2 && (x >= 4)) {
                                            x = x - 1;
                                        }
                                    

                                        return "[% path %]tiles/1.0.0/OESS_background/" + z + "/" + x + "/" + y + "." + this.type;
								      } else {
									    return "[% path %]media/none.png";
								      }
								  }
							  },
                                                          {isBaseLayer: true,
							   rendererOptions: {zIndexing: true}
							  }
							 );


		     map.addLayer(world_layer);

		     // add a bit of logic to prevent us from zooming all the way out and seeing a tiny world with
		     // lots of whitespace. Keep the zoom level at 2+
		     map.events.register("zoomend", map, function(){
			     var z = this.getZoom();
			     if (z <= 1){
				 this.zoomTo(2);
			     }
			 });

		     return map;
  };



  this._getMapData = function(){
    //reset our linkOverlapList
    this.linkOverlapList = {};

    var url = "[% path %]services/data.cgi?method=get_maps";

    if (session.data.workgroup_id){
	url += "&workgroup_id="+session.data.workgroup_id;
    }

    // options.circuit_type overrides the session data value. If it's
    // passed in and null, all links are returned; Otherwise only the
    // requested link type is requested.
    if (this.options.circuit_type === undefined && session.data.circuit_type) {
	url += "&link_type=" + session.data.circuit_type;
    } else if (this.options.circuit_type !== undefined && this.options.circuit_type !== null) {
        url += "&link_type=" + this.options.circuit_type;
    }

    var ds = new YAHOO.util.DataSource(url);

    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
      resultsList: "results",
      fields: [{key: "nodes"},
	       {key: "links"},
	       {key: "meta"}
	      ],
      Metafields: {
	error: "error"
      }
    };

    ds.sendRequest("", {success: function(req, resp){
			  if (resp.meta.error){
			    alert("Error - " + resp.meta.error);
			    return;
			  }

			  var results = resp.results;

			  // hang on to all these things so we can add / remove things quickly later
			  this.cache = results;


			  var layer = new OpenLayers.Layer.Vector("network_layer",
								  {
								      rendererOptions: {zIndexing: true}
								  }
								  );
			  this.map.addLayer(layer);

			  var clickControl = new OpenLayers.Control.SelectFeature(layer, {clickout: true, toggle: true});

			  var hoverControl = new OpenLayers.Control.SelectFeature(layer, {hover: true,
											  highlightOnly: true,
											  renderIntent: 'temporary',
											  eventListeners: {
				                              featurehighlighted: function(e){

					                                                        for (var i = self.map.popups.length - 1; i > -1; i--){
												    self.map.removePopup(self.map.popups[i]);
												}

												var feature = e.feature;

												if (feature.primary_feature){
												    feature = feature.primary_feature;
												}

												var element = feature.geometry;


												// figure out how wide this popup needs to be.
												// Since there's no way to actually measure text in Javascript,
												// we'll create a node, stick the text into it, and measure the node
												var measure = document.createElement('div');
												measure.style.visibility = 'hidden';
												measure.style.width = "auto";
												measure.style.height = "auto";
												measure.style.position = "absolute";
												measure.style['font-weight'] = 'bold';
												measure.innerHTML = element.element_name;

												document.body.appendChild(measure);
												var width  = measure.clientWidth;
												var height = measure.clientHeight;
												document.body.removeChild(measure);

												var offset = new OpenLayers.LonLat(1, 1).transform(this.map.displayProjection,
																		   this.map.projection);

												var lonlat = e.feature.geometry.getBounds().getCenterLonLat().add(offset.lon, offset.lat);
                                                if(element.element_name) {
                                                    var popup = new OpenLayers.Popup(e.feature.id,
                                                                     lonlat,
                                                                     new OpenLayers.Size(width + 10, height + 2),
                                                                     "<div style='text-align: center;white-space:nowrap;'><b>"+element.element_name+"</b></div>"
                                                                     );

                                                    popup.setBackgroundColor("#EEEEEE");

                                                    self.map.addPopup(popup);
                                                }
					                                                     },
												featureunhighlighted: function(e){
					                                                          // remove any popups on the map when we un-highlight
					                                                          for (var i = self.map.popups.length - 1; i > -1; i--){
												      self.map.removePopup(self.map.popups[i]);
												  }
					                                                        }
				                                                            }
				                                                       }
										 );
			  this.map.addControl(hoverControl);
			  this.map.addControl(clickControl);

			  hoverControl.activate();
			  clickControl.activate();

			  layer.events.on({
				  featureselected: function(e){
				      try{


					  // turn off any popups still up
					  for (var i = self.map.popups.length - 1; i > -1; i--){
					      self.map.removePopup(self.map.popups[i]);
					  }

					  var feature = e.feature;

					  // this basically redirects all clicks on things like halo lines
					  if (e.feature.primary_feature){
					      feature = e.feature.primary_feature;
					  }

					  var geo = feature.geometry;

					  // we're clicking on a Point, ie a node
					  //if (geo.id.indexOf("Point") != -1){
					  if (geo.oess_point_type == "node"){
					      var node    = geo.element_name;
					      var lat     = geo.element_lat;
					      var lon     = geo.element_lon;
					      var node_id = geo.element_id;
					      var range   = geo.vlan_range;
					      var default_forward = geo.default_forward;
					      var default_drop = geo.default_drop;
					      var max_flows = geo.max_flows;
					      var openflow = geo.openflow;
					      var mpls       = geo.mpls;
                            var mgmt_addr  = geo.mgmt_addr;
                            var tcp_port   = geo.tcp_port;
                            var vendor     = geo.vendor;
                            var model      = geo.model;
                            var sw_version = geo.sw_version;
                            var controller = geo.controller;
                            var tx_delay_ms = geo.tx_delay_ms;
                            var short_name = geo.short_name;
					      var barrier_bulk = geo.barrier_bulk;
					      var max_static_mac_flows = geo.max_static_mac_flows;
					      var dpid = geo.dpid;
					      self.events['clickNode'].fire({name: node, lat: lat, lon: lon, node_id: node_id, vlan_range: range,default_forward: default_forward, default_drop: default_drop,max_flows: max_flows, tx_delay_ms: tx_delay_ms,  feature: e.feature, barrier_bulk: barrier_bulk, max_static_mac_flows: max_static_mac_flows, dpid: dpid, openflow: openflow, mpls: mpls, mgmt_addr: mgmt_addr, tcp_port: tcp_port, vendor: vendor, model: model,short_name: short_name, sw_version: sw_version, controller: controller});
					  }
					  // otherwise we're clicking on a link
					  else{
					      var link     = geo.element_name;
					      var state    = geo.link_state;
					      var capacity = geo.link_capacity;
					      var link_id  = geo.element_id;
                          var links    = geo.links;
                          
                          //map.getControlsByClass("OpenLayers.Control.MousePosition‌​")[0]).lastXy    
                          //var xy = map.getControlsByClass("OpenLayers.Control.MousePosition")[0].lastXy    
					      self.events['clickLink'].fire({
                              name: link, 
                              state: state, 
                              capacity: capacity, 
                              link_id: link_id, 
                              feature: feature,
                              links: links 
                          });
					  }
				      }
				      catch(e){alert(e);}
				  }
				  }
				  );

	                  // in interdomain mode, don't show anything by default. Something calling this
	                  // will need to use "showNode" to put things on the map
			  if (! interdomain_mode){

			      // we're in intradomain mode otherwise, go ahead and show the local domain.
			      // add all the network goodies
			      for (var i = 0; i < results.length; i++){

				  var network = results[i].meta.network_name;

				  // don't drawn the foreign networks
				  if (results[i].meta.local == 0){
				      continue;
				  }

				  // now draw all the nodes
				  for (var node_name in results[i].nodes){
				      this.showNode(node_name);
				  }
			      }
			  }

			  self.events['loaded'].fire();
			  if(this._initialized != true){
			      this.showDefault();
			  }
			  this._initialized = true;
			},
			failure: function(req, resp){

			},
			scope: this
		       });

  }

  this.render = function( container ){
      this.map.render( container );
      this.showDefault();
  }

  // remove all features, requery server for data, redraw
  this.reinitialize = function(){
      this.map.layers[1].removeAllFeatures();
      this.map.removeLayer(this.map.layers[1]);
      this._getMapData();
  };

  this.map = this._createMap(div_id);
  this._getMapData();
  

  return this;
}

</script>
