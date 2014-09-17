//takes in a string dpid, covnerts it to int, converts it to hex, splits it up into an of strings with 
//no more than two characters, and joins them together into a string separated by colons
var convert_dpid_to_hex = function(dpid){

    var formatted_dpid = parseInt(dpid).toString(16).match(/.{1,2}/g).join(":"); 
    return formatted_dpid;

}; 
