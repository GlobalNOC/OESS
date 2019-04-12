document.addEventListener('DOMContentLoaded', function() {   
MAP();
});

async function MAP(){

  this.create_map = async function(){
    var mymap = L.map('mapid').setView([  39.391508, -85.977427], 2);

    L.tileLayer('https://api.tiles.mapbox.com/v4/{id}/{z}/{x}/{y}.png?access_token=pk.eyJ1IjoibWFwYm94IiwiYSI6ImNpejY4NXVycTA2emYycXBndHRqcmZ3N3gifQ.rJcFIG214AriISLbB6B5aw', {
      maxZoom: 18,
      attribution: 'Map data &copy; <a href="https://www.openstreetmap.org/">OpenStreetMap</a> contributors, ' +
        '<a href="https://creativecommons.org/licenses/by-sa/2.0/">CC-BY-SA</a>, ' +
        'Imagery © <a href="https://www.mapbox.com/">Mapbox</a>',
      id: 'mapbox.streets'
    }).addTo(mymap);
    return mymap;
  }

  this.load_data = async function(){
    // Get map data
    var url = "[% path %]services/data.cgi?method=get_maps_short";
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    var op = await resp.json();
    console.log(op.results);
    this.cache = op.results;
    this.createNodeDict();
    //Get Node and link Features from the ata
    this.nodeFeatures = await this.getNodeFeatures();
    this.linkFeatures = await this.getLinkJson();

    //Define Node properties and functions
    var prevNodeClicked = null;
    var prevNodeColor = null;
    function onEachNode(feature, layer){
      layer.on(
        {'click':
          function(e){
            if (prevNodeClicked !== null){
              prevNodeClicked.setStyle({
                color: "#12A5D8",
                }
              )
            }
            var layer = e.target;
            var newColor = "#ff9900";
            if(prevNodeClicked == layer && prevNodeColor == "#ff9900"){
              newColor = "#12A5D8";
            }
            layer.setStyle({
              color: newColor,
            })
            prevNodeClicked = layer;
            prevNodeColor = layer.options.color ;
          },       

      'mouseover':
        function(e){
            var layer = e.target;
            prevNodeColor = layer.options.color ;
            layer.setStyle({
              color: "#bfbfbf",
            })
        },
    
      'mouseout':
        function(e){
          if(prevNodeColor !== null){
              var layer = e.target;
              layer.setStyle({
                color: prevNodeColor,
              })
          }
        }
     }) 
    }
    var node_style = {
      pointToLayer: function (feature, latlng) {
        return L.circleMarker(latlng, {
          radius: 8
        })
      },
      style: {
        color: "#12A5D8",
        weight: 1,
        opacity: 1,
        fillOpacity: 0.8
      },
      onEachFeature : onEachNode
    };

    var link_style = { 
      style:{
        "color": "#12A5D8",
        "weight": 5,
        "opacity": 0.65
      },
      onEachFeature : onEachNode
    };



    this.addGeoJson(this.linkFeatures, link_style);
    this.addGeoJson(this.nodeFeatures, node_style);
  }
  this.addGeoJson = function (features, attributes){
    var layer = L.geoJson(features, attributes).addTo(this.map);
    return layer;
  }

  this.createNodeDict = function(){
    this.nodes = {};
     for (i=0; i<this.cache.nodes.length; i++){
      var node_id = this.cache.nodes[i].node_id;
      this.nodes[node_id] = this.cache.nodes[i];
    }
  }
  this.getNodeFeatures = async function(){
    /** Fetches Nodes with non 0 lat lon
     * returns a GeoJson feature of points
     */
    var result = [];
    var i;
    for (i=0; i<this.cache.nodes.length; i++){
      var lat = this.cache.nodes[i].latitude;
      var lon = this.cache.nodes[i].longitude;
      if (typeof(lat) != 'undefined' && typeof(lon) !='undefined' && lat !=0 && lon != 0){
        result.push({
        'type' : 'Point',
        'coordinates': [lon, lat]
        })
      }
    }
    console.log(result);
    return result;
  }
  this.getLinkJson = async function(){
  /** Fetches Nodes with non 0 lat lon
  * returns a GeoJson feature of LineString 
  */
    var result = [];
    var i;
    for (i=0; i<this.cache.links.length; i++){
      //console.log(this.cache.links[i]);
      if (typeof (this.cache.links) != 'undefined'){
        for (i in this.cache.links){
          //console.log(this.cache.links[i].from_node);
          var from = this.nodes[this.cache.links[i].from_node];
          var to = this.nodes[this.cache.links[i].to_node];
          if (typeof(from) !='undefined' && typeof(to) != 'undefined'){
            result.push({
              'type':'LineString',
              'coordinates':[[from.longitude,from.latitude ],[to.longitude,to.latitude, ]]
            });
          }
        }
      }
    } 
    return result;
  }
  this.map = await this.create_map();
  await this.load_data();
}



