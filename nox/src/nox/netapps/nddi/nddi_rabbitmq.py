#--------------------------------------------------------------------
#----- D-Bus API for NOX 
#-----
#----- $HeadURL:
#----- $Id:
#-----
#----- provides API for interacting with NOX using DBUS 
#---------------------------------------------------------------------
#
# Copyright 2011 Trustees of Indiana University 
# 
#   Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

from nox.lib.core import *

from nox.lib.packet.ethernet     import NDP_MULTICAST
from nox.lib.packet.ethernet     import ethernet
from nox.lib.packet.packet_utils import mac_to_str, mac_to_int, array_to_octstr
from nox.lib.packet.vlan              import vlan
from nox.netapps.discovery.pylinkevent   import Link_event
from nox.lib.netinet.netinet import c_ntohl

import nox.lib.openflow as openflow
import nox.lib.pyopenflow as of

import logging

import pprint
import struct
import time

# hacktastic import of our local lib, should figure out how to 
# expose this through nox.lib or something similar at some point
import os
import sys
sys.path.append("{0}/lib/grnoc".format(os.getcwd()))
sys.path.append("/usr/bin/nox/netapps/nddi/lib")
from grnoc.rabbitmq.rmqi import RMQI

FWDCTL_WAITING = 2
FWDCTL_SUCCESS = 1
FWDCTL_FAILURE = 0
FWDCTL_UNKNOWN = 3

TRACEROUTE_MAC= '\x06\xa2\x90\x26\x50\x09' 

PENDING  = 0
ANSWERED = 1

logger = logging.getLogger('org.nddi.openflow')

ifname = 'org.nddi.openflow'

flowmod_callbacks = {}
switches = []
last_flow_stats = {}
fv_pkt_rate_interval = 1
packets = []
VLAN_ID = None

#--- series of callbacks to glue the reception of NoX events to the generation of rabbit events
def port_status_callback(nddi, dp_id, ofp_port_reason, attrs):
    attr_dict = attrs
    
    #--- convert mac 
    attr_dict['hw_addr'] = mac_to_int(attrs['hw_addr'])
    #--- generate signal   
    nddi.rmqi_event.emit_signal('port_status',
        dpid=dp_id,
        ofp_port_reason=ofp_port_reason,
        attrs=attr_dict
    )

def fv_packet_in_callback(nddi, dp, inport, reason, len, bid, packet):
    if(packet.type == ethernet.VLAN_TYPE):
        packet = packet.next

    string = packet.next
    logger.info(string.encode('hex'))
    (src_dpid,src_port,dst_dpid,dst_port,timestamp) = struct.unpack('QHQHq',string[:40])
    
    #verify the packet came in from expected node/port
    if(dst_dpid != dp):
        logger.warn("Packet was sent to dpid: " + str(dst_dpid) + " but came from: " + str(dp))
        return
    if(dst_port != inport):
        logger.warn("Packet was sent to port: " + str(dst_port) + " but came from: " + str(inport))
        return

    nddi.rmqi_event.emit_signal('fv_packet_in',
        src_dpid=src_dpid,
        src_port=src_port,
        dst_dpid=dst_dpid,
        dst_port=dst_port,
        timestamp=timestamp
    )

def traceroute_packet_in_callback(nddi, dp, inport, reason, len, bid, packet):
    if(packet.type == ethernet.VLAN_TYPE):
        packet = packet.next

    string = packet.next
    logger.info(string.encode('hex'))

    #get circuit_id
    (circuit_id) = struct.unpack('I',string[:4])

    nddi.rmqi_event.emit_signal('traceroute_packet_in',
        dpid=dp,
        in_port=inport,
        circuit_id=circuit_id[0]
    )


    
                        

def link_event_callback(nddi, info):
    sdp    = info.dpsrc
    ddp    = info.dpdst
    sport  = info.sport
    dport  = info.dport
    action = info.action

    nddi.rmqi_event.emit_signal('link_event',
        dpsrc=sdp,
        dpdst=ddp,
        sport=sport,
        dport=dport,
        action=action
    )
    
    return CONTINUE

def datapath_join_callback(nddi, dp_id, ip_address, stats):

    # NOX gives us the IP address in the native order, move it to network
    tmp = struct.pack("@I", ip_address)
    ip_address = struct.unpack("!I", tmp)[0]

    if not dp_id in switches:
        switches.append(dp_id)

    ports = stats['ports'];
    #print str(ports)

    #--- we know we are going to need to get the set of flows so lets just do that now
    nddi.collection_epoch += 1
    flow = of.ofp_match()
    flow.wildcards = 0xffffffff
    nddi.send_flow_stats_request(dp_id, flow,0xff)
    
    port_list = []
    for p in ports:
        port = p
        port['hw_addr'] = mac_to_int(p['hw_addr'])
        port_list.append(port)
    #print str(port_list)
    nddi.rmqi_event.emit_signal('datapath_join',
        dpid=dp_id,
        ip=ip_address,
        ports=ports
    )

def datapath_leave_callback(nddi, dp_id):
    if dp_id in switches:
        switches.remove(dp_id)
    if dp_id in last_flow_stats:
        del last_flow_stats[dp_id]
    if dp_id in flowmod_callbacks:
        del flowmod_callbacks[dp_id]

    nddi.rmqi_event.emit_signal('datapath_leave',
        dpid=dp_id
    )

def barrier_reply_callback(nddi, dp_id, xid):

    intxid = c_ntohl(xid)

    if flowmod_callbacks.has_key(dp_id):
        flows = flowmod_callbacks[dp_id]
        if(flows.has_key(intxid)):
            flows[intxid]["status"] = ANSWERED
            flows[intxid]["result"] = FWDCTL_SUCCESS
            if not flows[intxid].has_key("failed_flows"):
                flows[intxid]["failed_flows"] = []
            flows[intxid]["failed_flows"] = []
            xids = flows.keys()
            for x in xids:
                if(x < intxid):
                    if(flows[x]["result"] == FWDCTL_FAILURE):
                        flows[intxid]["result"] = FWDCTL_FAILURE
                        flows[intxid]["failed_flows"].append(flows[x])
                    del flows[x]

    nddi.rmqi_event.emit_signal('barrier_reply',
        dpid=dp_id
    )

def error_callback(nddi, dpid, error_type, code, data, xid):
    
    logger.error("handling error from %s, xid = %d" % (dpid, xid))
    intxid = c_ntohl(xid)
    if flowmod_callbacks.has_key(dpid):
        flows = flowmod_callbacks[dpid]
        if(flows.has_key(intxid)):
            flows[intxid]["result"] = FWDCTL_FAILURE
            flows[intxid]["error"] = {}
            flows[intxid]["error"]["type"] = error_type
            flows[intxid]["error"]["code"] = code
            

def packet_in_callback(nddi, dpid,in_port,reason, length,buffer_id, data) :
    nddi.rmqi_event.emit_signal('packet_in',
        dpid=dpid,
        in_port=in_port,
        reason=reason,
        length=length,
        buffer_id=buffer_id,
        data=data.arr
    )


inst = None

# send a barrier message with a reference to the actual function we want to run when the switch
# has responded and told us that it is ready
def _do_install(dpid,xid,match,actions):
    
    if not flowmod_callbacks.has_key(dpid):
        flowmod_callbacks[dpid] = {}
    
    flowmod_callbacks[dpid][xid] = {"result": FWDCTL_WAITING, "match": match, "actions": actions}
    
    return 1

class nddi_rabbitmq(Component):

    def __init__(self, ctxt):
	global inst
        Component.__init__(self, ctxt)
        inst                           = self
        self.st                        = {}
        self.ctxt                      = ctxt
        self.packets                   = []
        self.FV_VLAN_ID                = None
        self.fv_pkt_rate               = 1
        self.collection_epoch          = 0
        self.latest_flow_stats         = {}
        self.collection_epoch_duration = 10
        self.registered_for_fv_in      = 0
        
        # instantiate rabbitmq rpc interface
        self.rmqi_rpc = RMQI(
            exchange='OESS',
            queue='OF.NOX.RPC'
        )

        # instatiate rabbitmq event interface
        self.rmqi_event = RMQI(
            exchange='OESS',
            queue='OF.NOX.event'
        )

    def install(self):

        print "in install"
        #gobject.threads_init()
        #run_glib()
        self.flow_stats = {}

        #--- register for nox events 
        self.register_for_datapath_join (lambda dpid, stats : 
            datapath_join_callback(self, dpid, self.ctxt.get_switch_ip(dpid), stats) 
        )

        self.register_for_error(lambda dpid, error_type, code, data, xid: 
            error_callback(self.sg, dpid, error_type, code, data, xid)
        )

        self.register_for_datapath_leave(lambda dpid : 
            datapath_leave_callback(self, dpid)
        )

        self.register_for_barrier_reply(lambda dpid, xid:
            barrier_reply_callback(self, dpid, xid)
        )

        self.register_for_port_status(lambda dpid, reason, port : 
            port_status_callback(self, dpid, reason, port)
        )
        
        #--- this is a a special event generated by the discovery service, 
        #---   which is why there isnt the handy register_for_* method
        self.register_handler(Link_event.static_get_name(), lambda  info : 
            link_event_callback(self, info )
        )

        self.register_for_flow_stats_in(self.flow_stats_in_handler)

        #TODO come back to this method
        self.fire_send_fv_packets()
        self.fire_flow_stats_timer()
    
        # register rabbitmq rpc callbacks
        print "subscribing callbacks"
        self.rmqi_rpc.subscribe_to_signal(method=self.send_fv_packets)
        self.rmqi_rpc.subscribe_to_signal(method=self.send_traceroute_packet)
        self.rmqi_rpc.subscribe_to_signal(method=self.echo)
        self.rmqi_rpc.subscribe_to_signal(method=self.get_flow_stats)
        self.rmqi_rpc.subscribe_to_signal(method=self.get_node_status)
        self.rmqi_rpc.subscribe_to_signal(method=self.install_default_drop)
        self.rmqi_rpc.subscribe_to_signal(method=self.register_for_fv_in)
        self.rmqi_rpc.subscribe_to_signal(method=self.register_for_traceroute_in)
        self.rmqi_rpc.subscribe_to_signal(method=self.install_default_forward)
        self.rmqi_rpc.subscribe_to_signal(method=self.send_datapath_flow)
        self.rmqi_rpc.subscribe_to_signal(method=self.send_barrier)
        self.rmqi_rpc.subscribe_to_signal(method=self.get_node_connect_status)
        
        # the event emitter doesn't actually need to be a thread
        # we should revisit this and make it its own class that doesn't extend the threading module
        self.rmqi_event.start()
        while self.rmqi_event.connected is False:
            logger.warn("rmqi_event connecting...")
            time.sleep(1)
        
        print "starting rpc listener thread"
        self.rmqi_rpc.start()
        while self.rmqi_rpc.queue_declared is False:
            logger.warn("rmqi_queue connecting...")
            time.sleep(1)
        
    def fire_flow_stats_timer(self):
        for dpid in switches:
            self.collection_epoch += 1
            flow = of.ofp_match()
            flow.wildcards = 0xffffffff
            self.send_flow_stats_request(dpid, flow, 0xff)

        self.post_callback(30, self.fire_flow_stats_timer)

    def fire_send_fv_packets(self):

        time_val = time.time() * 1000
        logger.info("Sending FV Packets rate: " + str(self.fv_pkt_rate) + " with vlan: " + str(self.FV_VLAN_ID) + " packets: " + str(len(self.packets)))

        for pkt in self.packets:
            logger.info("Packet:")
            packet = ethernet()
            packet.src = '\x00' + struct.pack('!Q',pkt[0])[3:8]
            packet.dst = NDP_MULTICAST

            payload = struct.pack('QHQHq',pkt[0],pkt[1],pkt[2],pkt[3],time_val)

            if(self.FV_VLAN_ID != None and self.FV_VLAN_ID != 65535):
                vlan_packet = vlan()
                vlan_packet.id = self.FV_VLAN_ID
                vlan_packet.c = 0
                vlan_packet.pcp = 0
                vlan_packet.eth_type = 0x88b6
                vlan_packet.set_payload(payload)

                packet.set_payload(vlan_packet)
                packet.type = ethernet.VLAN_TYPE

            else:
                packet.set_payload(payload)
                packet.type = 0x88b6

            Component.send_openflow_packet(pkt[0], packet.tostring(), int(pkt[1]))

        self.post_callback(fv_pkt_rate_interval, self.fire_send_fv_packets)

    def getInterface(self):
        return str(nddi_rabbitmq)

    def flow_stats_in_handler(self, dpid, flows, done, xid):

        if dpid in self.flow_stats:
            if self.flow_stats[dpid] == None:
                self.flow_stats[dpid] = {"time": int(time.time()) , "flows": flows}
            else:
                self.flow_stats[dpid]["flows"].extend(flows)
        else:
            self.flow_stats[dpid] = {"time": int(time.time()) , "flows": flows}

        if done == False:
            if self.flow_stats[dpid]:     

                # get rid of rules that don't have matches on them because we can't key off
                # port / vlan to get info that we need
                for row in reversed(self.flow_stats[dpid]["flows"]):                    

                    if row.has_key("cookie"):
                        del row["cookie"]

                    if row.has_key("actions"):
                        if len(row["actions"]) == 0:
                            self.flow_stats[dpid]["flows"].remove(row)
                            continue

                    if row.has_key("match"):
                        if not row["match"]:
                            self.flow_stats[dpid]["flows"].remove(row)
                            continue

                # update our cache with the latest flow stats
                if self.flow_stats[dpid]:
                    last_flow_stats[dpid] = self.flow_stats[dpid]

            self.flow_stats[dpid] = None
 
    def send_flow_stats_request(self, dpid, match, table_id, xid=-1):
        """Send a flow stats request to a switch (dpid).
        @param dpid - datapath/switch to contact
        @param match - ofp_match structure
        @param table_id - table to query
        """
        # Create the stats request header
        request = of.ofp_stats_request()
        if xid == -1:
            request.header.xid = c_htonl(long(self.collection_epoch))
        else:
            request.header.xid = c_htonl(xid)
            
        request.header.type = openflow.OFPT_STATS_REQUEST
        request.type = openflow.OFPST_FLOW
        request.flags = 0
        # Create the stats request body
        body = of.ofp_flow_stats_request()
        body.match = match
        body.table_id = table_id
        body.out_port = openflow.OFPP_NONE
        request.header.length = len(request.pack()) + len(body.pack())
        self.send_openflow_command(dpid, request.pack() + body.pack())


    #--
    #-- Define RabbitMQ RPC methods 
    #--

    # rmqi rpc method send_fv_packets
    def send_fv_packets(self, **kwargs):
        rate = kwargs.get('interval')
        vlan = kwargs.get('vlan')
        pkts = kwargs.get('packets')

        logger.info("Setting FV packets")
        self.fv_pkt_rate = (rate / 1000.0)
        logger.info("Packet Our Rate: " + str(self.fv_pkt_rate))
        self.FV_VLAN_ID = vlan
        logger.info("FV VLAN ID: " + str(self.FV_VLAN_ID))
        self.packets = pkts
        return

    # rmqi rpc method send_traceroute_packet
    def send_traceroute_packet(self, **kwargs):
        dpid     = kwargs.get('dpid')
        my_vlan  = kwargs.get('my_vlan')
        out_port = kwargs.get('out_port')
        data     = kwargs.get('data')

        #build ethernet packet
        packet = ethernet()
        packet.src = '\x00' + struct.pack('!Q',dpid)[3:8]
        packet.dst = TRACEROUTE_MAC
        #pack circuit_id into payload
        payload = struct.pack('I',data)
        
        if(my_vlan != None and my_vlan != 65535):
            vlan_packet = vlan()
            vlan_packet.id = my_vlan
            vlan_packet.c = 0
            vlan_packet.pcp = 0
            vlan_packet.eth_type = 0x88b5
            vlan_packet.set_payload(payload)

            packet.set_payload(vlan_packet)
            packet.type = ethernet.VLAN_TYPE
            
        else:
            packet.set_payload(payload)
            packet.type = 0x88b5
        
        Component.send_openflow_packet(self, int(dpid), packet.tostring(),int(out_port))

        return
        
    # rmqi rpc method echo
    def echo(self, **kwargs):
        rate = kwargs.get('rate')
        vlan = kwargs.get('vlan')
        pkts = kwargs.get('pkts')

        return 1

    # rmqi rpc method get_flow_stats
    def get_flow_stats(self, **kwargs):

        #sys.exit(1)
        logger.warn("in get_flow_stats")
        dpid = kwargs.get('dpid')

        logger.warn("get_flow_stats: ".format(dpid))

        if last_flow_stats.has_key(dpid):
            #build an array of DBus Dicts
            logger.warn('getting flow stats for dpid: {0}'.format(dpid))
            flow_stats = []
            for item in last_flow_stats[dpid]["flows"]:
                match = item['match']
                item['match'] = match
                flow_stats.append(item)

            return {
                'timestamp': last_flow_stats[dpid]["time"],
                'flow_stats': flow_stats
            }
        else:
            logger.warn("No Flow stats cached for dpid: " + str(dpid))
            return {
                'timestamp': -1,
                'flow_stats': [] 
            }

    # rmqi rpc method get_node_status
    def get_node_status(self, **kwargs):
        dpid = kwargs.get('dpid')

        result = {'status': FWDCTL_FAILURE, 'flows': []}
        if flowmod_callbacks.has_key(dpid):
            xids = flowmod_callbacks[dpid].keys()
            
            if(len(xids) == 1):
                if(flowmod_callbacks[dpid][xids[0]]["result"] == FWDCTL_SUCCESS):
                    del flowmod_callbacks[dpid][xids[0]]
                    result["status"] = FWDCTL_SUCCESS
                    return result
                elif(flowmod_callbacks[dpid][xids[0]]["result"] == FWDCTL_WAITING):
                    result["status"] = FWDCTL_WAITING
                    return result
                else:
                    del flowmod_callbacks[dpid][xids[0]]
                    return result
            else:
                result["status"] = FWDCTL_WAITING
                return result

        result["status"] = FWDCTL_UNKNOWN
        return result

    # rmqi rpc method install_default_drop
    def install_default_drop(self, **kwargs):
        dpid = kwargs.get('dpid')

        if not dpid in switches:
          return 0;

        my_attrs          = {}
        actions           = []
        
        idle_timeout = 0
        hard_timeout = 0

        xid = Component.send_datapath_flow(
            self,
            dp_id=dpid,
            attrs=my_attrs,
            idle_timeout=idle_timeout,
            hard_timeout=hard_timeout,
            actions=actions,
            priority=0x0001,
            inport=None
        )
        
        _do_install(dpid,xid,my_attrs,actions)

        return xid

    # rmqi rpc method register_for_fv_in
    def register_for_fv_in(self, **kwargs):
        vlan = kwargs.get('vlan')

        #ether type 88b6 is experimental
        #88b6 IEEE 802.1 IEEE Std 802 - Local Experimental
        if(self.registered_for_fv_in == 1):
            return 1
        logger.info("Registered for packet in events for FV")

        if(vlan == None):
            match = {
                DL_TYPE: 0x88b6,
                DL_DST: array_to_octstr(array.array('B', NDP_MULTICAST))
                }
        else:
            match = {
                DL_TYPE: 0x88b6,
                DL_DST: array_to_octstr(array.array('B',NDP_MULTICAST)),
                DL_VLAN: vlan
                }

        inst.register_for_packet_match(lambda dpid, inport, reason, len, bid,packet :
            fv_packet_in_callback(self, dpid, inport, reason, len, bid, packet), 
        0xffff, match)

        self.registered_for_fv_in = 1
        return 1

    # rmqi rpc method register_for_traceroute_in
    def register_for_traceroute_in(self):
        #ether type 88b6 is experimental
        #88b6 IEEE 802.1 IEEE Std 802 - Local Experimental
        if(self.registered_for_traceroute_in == 1):
            return 1
        logger.info("Registered for packet in events for Traceroute")

        match = {
            DL_TYPE: 0x88b5,
            DL_DST: TRACEROUTE_MAC
        }
        
        inst.register_for_packet_match(lambda dpid, inport, reason, len, bid,packet : 
            traceroute_packet_in_callback(self, dpid, inport, reason, len, bid, packet),
        0xffff, match)

        self.registered_for_traceroute_in = 1
        return 1

    # rmqi rpc method install_default_foward
    def install_default_forward(self, **kwargs):
        dpid = kwargs.get('dpid')
        vlan = kwargs.get('discovery_vlan')

        if not dpid in switches:
          return 0;

        my_attrs          = {}
        my_attrs[DL_TYPE] = 0x88cc       
        my_attrs[DL_VLAN] = vlan
        actions = [[openflow.OFPAT_OUTPUT, [65535, openflow.OFPP_CONTROLLER]]]
        
        idle_timeout = 0
        hard_timeout = 0
        xid = Component.send_datapath_flow(
            self,
            dp_id=dpid,
            attrs=my_attrs,
            idle_timeout=idle_timeout,
            hard_timeout=hard_timeout,
            actions=actions,
            inport=None
        )

        _do_install(dpid,xid,my_attrs,actions)

        my_attrs = {}
        my_attrs[DL_VLAN] = vlan
        my_attrs[DL_TYPE] = 0x88b6 
        actions = [[openflow.OFPAT_OUTPUT, [65535, openflow.OFPP_CONTROLLER]]]
        
        idle_timeout = 0
        hard_timeout = 0
        xid = Component.send_datapath_flow(
            self,
            dp_id=dpid,
            attrs=my_attrs,
            idle_timeout=idle_timeout,
            hard_timeout=hard_timeout,
            actions=actions,
            inport=None
        )
        
        _do_install(dpid,xid,my_attrs,actions)

        return xid

    # rmqi rpc method send_datapath_flow
    def send_datapath_flow(self, **kwargs):
        flow    = kwargs.get('flow')
        dpid    = int(flow["dpid"])
        attrs   = flow["match"]
        actions = flow["actions"]
  
        if not dpid in switches:
          return 0;
        
        #--- here goes nothing
        my_attrs = {}
        priority = 32768
        idle_timeout = 0
        hard_timeout = 0
        command      = None
        packet       = None
        xid          = None
        buffer_id    = None

        logger.info("sending OFPFC: %d" % flow.get("command", "No Command Set!"))

        if attrs.get("dl_vlan"):
            my_attrs[DL_VLAN] = int(attrs['dl_vlan'])
        if attrs.get("in_port"):
            my_attrs[IN_PORT] = int(attrs['in_port'])
        if attrs.get("dl_dst"):
            my_attrs[DL_DST]  = int(attrs['dl_dst'])
        if attrs.get("dl_type"):
            my_attrs[DL_TYPE] = int(attrs['dl_type'])
        if flow.get("priority"):
            priority = int(flow["priority"])
        if flow.get("idle_timeout"):
            idle_timeout = int(flow["idle_timeout"])
        if flow.get("hard_timeout"):
            hard_timeout = int(flow["hard_timeout"])
        if "command" in flow:
            command = int(flow["command"])
        if flow.get("xid"):
            xid = int(flow["xid"])
        if flow.get("packet"):
            packet = int(flow["packet"])
        if attrs.get("buffer_id"):
            buffer_id = int(flow["buffer_id"])

        #--- this is less than ideal. to make dbus happy we need to pass extra arguments in the
        #--- strip vlan case, but NOX won't be happy with them so we remove them here
        for i in range(len(actions)):
            action = actions[i];
            if action[0] == openflow.OFPAT_STRIP_VLAN and len(action) > 1:
                #new_action = dbus.Struct((dbus.UInt16(openflow.OFPAT_STRIP_VLAN),))
                new_action = openflow.OFPAT_STRIP_VLAN
                actions.remove(action)
                actions.insert(i, new_action)

        #--- first we check to make sure the switch is in a ready state to accept more flow mods
        xid = Component.send_datapath_flow(
            self,
            dpid, 
            my_attrs,
            idle_timeout,
            hard_timeout,
            actions,
            buffer_id,
            priority,
            my_attrs.get(IN_PORT),
            command,
            packet, 
            xid
        )

        logger.info("sent OFPFC: {0}, xid: {1}".format(command, xid))
        actions = [] if actions == None else actions
        _do_install(dpid,xid,my_attrs,actions)

        return xid

    # rmqi rpc method send_barrier
    def send_barrier(self, **kwargs):
        dpid = kwargs.get('dpid')

        logger.info("Sending barrier for %s" % dpid)
        
        xid = Component.send_barrier(self, dpid)

        if not flowmod_callbacks.has_key(dpid):
            flowmod_callbacks[dpid] = {}
        flowmod_callbacks[dpid][xid] = {"result": FWDCTL_WAITING}
        return xid
    
    # rmqi rpc method get_node_connect_status 
    def get_node_connect_status(self, **kwargs):
        status_dpid = kwargs.get('dpid')
        for dpid in switches:
            if dpid == status_dpid:
                return True
        return False

def getFactory():
    class Factory:
        def instance(self, ctxt):
            return nddi_rabbitmq(ctxt)

    return Factory()
