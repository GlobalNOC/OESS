//takes in a string dpid, covnerts it to int, converts it to hex, splits it up into an of strings with 
//no more than two characters, and joins them together into a string separated by colons
var convert_dpid_to_hex = function(dpid){
    var formatted_dpid;
    //if we're not a base16 string, parse out the integer
    if(typeof dpid == "string" && !dpid.match(/[a-fA-F0-9]+/)){
        formatted_dpid = parseInt(dpid)
    } else {
        formatted_dpid = dpid;
    }
    //convert to a base 16 string and add a ':' every two char
    formatted_dpid = formatted_dpid.toString(16).match(/.{1,2}/g).join(":"); 
        
    return formatted_dpid;
}; 
