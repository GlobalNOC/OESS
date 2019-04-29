document.addEventListener('DOMContentLoaded', function() {   
var url = "[% path %]services/data.cgi?method=get_maps_atlas";
GlobalNOC.Atlas.LeafletMap({            
      containerId: "map",
      zoom: 3,
      lat: 37,
      lng: -97,
      bing_api_key: "AplW162gFohrU9tZYti5XUCVeCG0ljiq5KgvLQREoqNBCl872zhHUs8PoVZ2j6Fw",
      map_tile_url: "https://api.tiles.mapbox.com/v4/mapbox.light/{z}/{x}/{y}.png?access_token=pk.eyJ1IjoiYXJhZ3VzYSIsImEiOiJjajNvamMxdjAwMDZ0MzJudTF3MnU2Z3JnIn0.pcs4pCcxoV2HMSjw3XXrRQ",
      "networkLayers": [{
      "name": "I2 AL2S",
      "lineWidth": 4,
      "mapSource": url,
      "lineColor": "#36278C",
      }]
      });

});

