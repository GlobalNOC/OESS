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
import dbus
import dbus.service
import gobject
import pprint
import struct
from time import time

from dbus.mainloop.glib import DBusGMainLoop

FWDCTL_WAITING = 2
FWDCTL_SUCCESS = 1
FWDCTL_FAILURE = 0
FWDCTL_UNKNOWN = 3

PENDING  = 0
ANSWERED = 1

FORMAT = '%(asctime)-15s  %(message)s'
logging.basicConfig(format=FORMAT)
logger = logging.getLogger('org.nddi.openflow')

ifname = 'org.nddi.openflow'

flowmod_callbacks = {}
switches = []
last_flow_stats = {}
fv_pkt_rate = 1
packets = []
VLAN_ID = None


class dBusEventGenRo(dbus.service.Object):

    def __init__(self,bus,path):
        dbus.service.Object.__init__(self,bus_name=bus, object_path=path)
        self.collection_epoch = 0
    @dbus.service.method(dbus_interface=ifname,
                         in_signature='t',
                         out_signature='b'
                         )
    def get_node_connect_status(self, status_dpid):
        for dpid in switches:
            if dpid == status_dpid:
                return True
        return False

#--- this is a a wrapper class that defineds the dbus interface
class dBusEventGen(dbus.service.Object):

    def __init__(self, bus, path):
       dbus.service.Object.__init__(self, bus_name=bus, object_path=path)
       self.collection_epoch = 0
       self.packets_out = 0
       self.packets_in = 0
       self.registered_for_fv_in = 0
       self.fv_pkt_rate = 1
       self.packets = []
       self.VLAN_ID = None

    @dbus.service.signal(dbus_interface=ifname,
                         signature='tua{sv}')
    def port_status(self,dp_id,reason,attrs):
       string = "port status change: "+str(dp_id)+" attrs "+ str(dict(attrs))
       logger.info(string)
       
    @dbus.service.signal(dbus_interface=ifname,
                         signature='tqtqt')
    def fv_packet_in(self, src_dpid, src_port, dst_dpid, dst_port, timestamp):
        string = "fv packet in: " + str(self.packets_in)
        
    @dbus.service.signal(dbus_interface=ifname,
                         signature='tua{sv}')
    def topo_port_status(self,dp_id,reason,attrs):
        string = "Topo Port Status Change: " + str(dp_id)+" attr " + str(dict(attrs))
        logger.info(string)

    @dbus.service.signal(dbus_interface=ifname,
                         signature='tqtqs')
    def link_event(self,sdp,sport,ddp,dport,action):
       string = "link_event: "+str(sdp)+" port "+str(sport)+" -->  "+str(ddp)+" port "+str(dport)+" is "+str(action)
       logger.info(string)

    @dbus.service.signal(dbus_interface=ifname,
                         signature='tuaa{sv}') 
    def datapath_join(self,dp_id,ip_address,port_list):
       string = "datapath join: "+str(dp_id)+str(ip_address)+str(port_list)
       logger.info(string)

    @dbus.service.signal(dbus_interface=ifname,
                         signature='t')
    def datapath_leave(self,dp_id):
       string = "datapath leave: "+str(dp_id)
       logger.info(string)

    @dbus.service.signal(dbus_interface=ifname,
                         signature='tu')
    def barrier_reply(self,dp_id,xid):
       string = "barrier_reply: "+str(dp_id)
       logger.info(string)

    @dbus.service.method(dbus_interface=ifname,
                         in_signature='itaat',
                         out_signature='')
    def send_fv_packets(self, rate, vlan, pkts):
        logger.info("Setting FV packets")
        self.fv_pkt_rate = (rate / 1000.0)
        logger.info("Packet Our Rate: " + str(self.fv_pkt_rate))
        self.VLAN_ID = vlan
        logger.info("VLAN ID: " + str(VLAN_ID))
        self.packets = pkts
        return
        
    @dbus.service.signal(dbus_interface=ifname,signature='tuquuay')
    def packet_in(self,dpid,in_port, reason, length, buffer_id, data):
       string =  "packet_in: "+str(dpid)+" :  "+str(in_port)
       logger.info(string)

    @dbus.service.method(dbus_interface=ifname,
                         in_signature='t',
                         out_signature='iaa{sv}'
                         )
    def get_flow_stats(self, dpid):
        string = "get_flow_stats: " + str(dpid)
        logger.info(string)
        if last_flow_stats.has_key(dpid):
            #build an array of DBus Dicts
            flow_stats = []
            for item in last_flow_stats[dpid]["flows"]:
                match = dbus.Dictionary(item['match'], signature='sv', variant_level = 2)
                item['match'] = match
                dict = dbus.Dictionary(item, signature='sv' , variant_level=3)
                flow_stats.append(dict)

            return (last_flow_stats[dpid]["time"],flow_stats)
        else:
            logger.info("No Flow stats cached for dpid: " + str(dpid))
            return (-1, [{"flows": "not yet cached"}])
            

    @dbus.service.method(dbus_interface=ifname,
                         in_signature='t',
                         out_signature='iaa{sv}'
                         )
    def get_node_status(self, dpid):
        if flowmod_callbacks.has_key(dpid):
            xids = flowmod_callbacks[dpid].keys()
            
            if(len(xids) == 1):

                if(flowmod_callbacks[dpid][xids[0]]["result"] == FWDCTL_SUCCESS):
                    del flowmod_callbacks[dpid][xids[0]]
                    return ( FWDCTL_SUCCESS, [])

                elif(flowmod_callbacks[dpid][xids[0]]["result"] == FWDCTL_WAITING):
                    return (FWDCTL_WAITING, [])
                else:
                    del flowmod_callbacks[dpid][xids[0]]
                    return ( FWDCTL_FAILURE, [])
            else:
                return (FWDCTL_WAITING, [])
            
        return (FWDCTL_UNKNOWN,[])


    @dbus.service.method(dbus_interface=ifname,
                         in_signature='t',
                         out_signature='t'
                         )
    def install_default_drop(self, dpid):

        if not dpid in switches:
          return 0;

        my_attrs          = {}
        actions           = []
        
        idle_timeout = 0
        hard_timeout = 0

        xid = inst.install_datapath_flow( dp_id=dpid,
                                          attrs=my_attrs,
                                          idle_timeout=idle_timeout,
                                          hard_timeout=hard_timeout,
                                          actions=actions,
                                          priority=0x0001,
                                          inport=None)
        
        _do_install(dpid,xid,my_attrs,actions)

        return xid

    @dbus.service.method(dbus_interface=ifname,
                         in_signature='q',
                         out_signature='q')
    def register_for_fv_in(self, vlan):
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

        inst.register_for_packet_match(lambda dpid, inport, reason, len, bid,packet : fv_packet_in_callback(self,dpid,inport,reason,len,bid,packet), 0xffff, match)
        self.registered_for_fv_in = 1
        return 1

    @dbus.service.method(dbus_interface=ifname,
                         in_signature='tq',
                         out_signature='t'
                         )
    def install_default_forward(self, dpid, vlan):

        if not dpid in switches:
          return 0;

        my_attrs          = {}
        my_attrs[DL_TYPE] = 0x88cc       
        my_attrs[DL_VLAN] = vlan
        actions = [[openflow.OFPAT_OUTPUT, [65535, openflow.OFPP_CONTROLLER]]]
        
        idle_timeout = 0
        hard_timeout = 0
        xid = inst.install_datapath_flow(dp_id=dpid, attrs=my_attrs, idle_timeout=idle_timeout, hard_timeout=hard_timeout,actions=actions,inport=None)

        _do_install(dpid,xid,my_attrs,actions)

        my_attrs = {}
        my_attrs[DL_VLAN] = vlan
        my_attrs[DL_TYPE] = 0x88b6 
        actions = [[openflow.OFPAT_OUTPUT, [65535, openflow.OFPP_CONTROLLER]]]
        
        idle_timeout = 0
        hard_timeout = 0
        xid = inst.install_datapath_flow(dp_id=dpid, attrs=my_attrs, idle_timeout=idle_timeout, hard_timeout=hard_timeout,actions=actions,inport=None)
        
        _do_install(dpid,xid,my_attrs,actions)

        return xid

    @dbus.service.method(dbus_interface=ifname,
                         in_signature='ta{sv}a(qv)',
                         out_signature='t'
                         )
    def install_datapath_flow(self,dpid,attrs,actions):

        if not dpid in switches:
          return 0; 

        #--- here goes nothing
        my_attrs = {}
        priority = 32768
        idle_timeout = 0
        hard_timeout = 0
        if attrs.get("DL_VLAN"):
            my_attrs[DL_VLAN] = int(attrs['DL_VLAN'])        
        if attrs.get("IN_PORT"):
            my_attrs[IN_PORT] = int(attrs['IN_PORT'])
        if attrs.get("DL_TYPE"):
            my_attrs[DL_TYPE] = int(attrs["DL_TYPE"])
        if attrs.get("PRIORITY"):
            priority = int(attrs["PRIORITY"])
        if attrs.get("DL_DST"):
            my_attrs[DL_DST] = int(attrs["DL_DST"])
        if attrs.get("IDLE_TIMEOUT"):
            idle_timeout = int(attrs["IDLE_TIMEOUT"])
        if attrs.get("HARD_TIMEOUT"):
            hard_timeout = int(attrs["HARD_TIMEOUT"])
        #--- this is less than ideal. to make dbus happy we need to pass extra arguments in the
        #--- strip vlan case, but NOX won't be happy with them so we remove them here
        for i in range(len(actions)):
            action = actions[i];
            if action[0] == openflow.OFPAT_STRIP_VLAN and len(action) > 1:
                new_action = dbus.Struct((dbus.UInt16(openflow.OFPAT_STRIP_VLAN),))
                actions.remove(action)
                actions.insert(i, new_action)

        #--- first we check to make sure the switch is in a ready state to accept more flow mods.
        if (my_attrs.get("IN_PORT")):
            xid = inst.install_datapath_flow(dp_id=dpid, attrs=my_attrs, idle_timeout=idle_timeout, hard_timeout=hard_timeout,actions=actions,priority=priority,inport=my_attrs[IN_PORT])
        else:
            xid = inst.install_datapath_flow(dp_id=dpid, attrs=my_attrs, idle_timeout=idle_timeout, hard_timeout=hard_timeout,actions=actions,priority=priority,inport=None)
        logger.info("Flow XID: %d" % xid)
        _do_install(dpid,xid,my_attrs,actions)

        return xid


    @dbus.service.method(dbus_interface=ifname,
                         in_signature='ta{sv}a(qv)',
                         out_signature='t'
                         )
    def delete_datapath_flow(self,dpid, attrs, actions ):

        if not dpid in switches:
          return 0;

        logger.info("removing flow")

        my_attrs = {}
        if attrs.get("DL_VLAN"):
            my_attrs[DL_VLAN] = int(attrs['DL_VLAN'])
        if attrs.get("IN_PORT"):
            my_attrs[IN_PORT] = int(attrs['IN_PORT'])
        if attrs.get("DL_DST"):
            my_attrs[DL_DST]  = int(attrs['DL_DST'])
        if attrs.get("DL_TYPE"):
            my_attrs[DL_TYPE]  = int(attrs['DL_TYPE'])

        logger.info("removing flow")
        #--- first we check to make sure the switch is in a ready state to accept more flow mods
        xid = inst.delete_datapath_flow(dpid, my_attrs)
        logger.info("flow removed xid: %d" % xid)
        actions = []
        _do_install(dpid,xid,my_attrs,actions)

        return xid
    
    @dbus.service.method(dbus_interface=ifname,
                         in_signature='ta{sv}a(qv)',
                         out_signature='t'
                         )
    def send_datapath_flow(self,dpid,attrs,actions):
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

        logger.info("sending OFPFC: %d" % attrs.get("COMMAND", "No Command Set!"))

        if attrs.get("DL_VLAN"):
            my_attrs[DL_VLAN] = int(attrs['DL_VLAN'])
        if attrs.get("IN_PORT"):
            my_attrs[IN_PORT] = int(attrs['IN_PORT'])
        if attrs.get("DL_DST"):
            my_attrs[DL_DST]  = int(attrs['DL_DST'])
        if attrs.get("DL_TYPE"):
            my_attrs[DL_TYPE] = int(attrs['DL_TYPE'])
        if attrs.get("PRIORITY"):
            priority = int(attrs["PRIORITY"])
        if attrs.get("IDLE_TIMEOUT"):
            idle_timeout = int(attrs["IDLE_TIMEOUT"])
        if attrs.get("HARD_TIMEOUT"):
            hard_timeout = int(attrs["HARD_TIMEOUT"])
        if "COMMAND" in attrs:
            command = int(attrs["COMMAND"])
        if attrs.get("XID"):
            xid = int(attrs["XID"])
        if attrs.get("PACKET"):
            packet = int(attrs["PACKET"])
        if attrs.get("BUFFER_ID"):
            buffer_id = int(attrs["BUFFER_ID"])

        #--- this is less than ideal. to make dbus happy we need to pass extra arguments in the
        #--- strip vlan case, but NOX won't be happy with them so we remove them here
        for i in range(len(actions)):
            action = actions[i];
            if action[0] == openflow.OFPAT_STRIP_VLAN and len(action) > 1:
                new_action = dbus.Struct((dbus.UInt16(openflow.OFPAT_STRIP_VLAN),))
                actions.remove(action)
                actions.insert(i, new_action)

        #--- first we check to make sure the switch is in a ready state to accept more flow mods
        xid = inst.send_datapath_flow(
            dpid, 
            my_attrs,
            idle_timeout,
            hard_timeout,
            actions,
            buffer_id,
            priority,
            my_attrs.get("IN_PORT"),
            command,
            packet, 
            xid
        )


        logger.info("sent OFPFC: {0}, xid: {1}".format(command, xid))
        actions = [] if actions == None else actions
        _do_install(dpid,xid,my_attrs,actions)

        return xid


    @dbus.service.method(dbus_interface=ifname,
                         in_signature='t',
                         out_signature='t'
                         )
    def send_barrier(self, dpid):
        logger.info("Sending barrier for %s" % dpid)
        
        xid = inst.send_barrier(dpid)

        if not flowmod_callbacks.has_key(dpid):
            flowmod_callbacks[dpid] = {}
        flowmod_callbacks[dpid][xid] = {"result": FWDCTL_WAITING}
        return xid

#--- series of callbacks to glue the reception of NoX events to the generation of D-Bus events
def port_status_callback(sg,dp_id, ofp_port_reason, attrs):
    attr_dict = {}
    if attrs:
      attr_dict = dbus.Dictionary(attrs, signature='sv')
    
    #--- convert mac 
    attr_dict['hw_addr'] = dbus.UInt64(mac_to_int(attr_dict['hw_addr']))
    #--- generate signal   
    sg.port_status(dp_id,ofp_port_reason,attr_dict)

def fv_packet_in_callback(sg,dp,inport,reason,len,bid,packet):
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

    sg.fv_packet_in(src_dpid,src_port,dst_dpid,dst_port,timestamp)
    
                        

def link_event_callback(sg,info):
    sdp    = info.dpsrc
    ddp    = info.dpdst
    sport  = info.sport
    dport  = info.dport
    action = info.action

    sg.link_event(sdp,sport,ddp,dport,str(action))

    return CONTINUE

def datapath_join_callback(ref,sg,dp_id,ip_address,stats):

    # NOX gives us the IP address in the native order, move it to network
    tmp = struct.pack("@I", ip_address)
    ip_address = struct.unpack("!I", tmp)[0]

    if not dp_id in switches:
        switches.append(dp_id)

    ports = stats['ports'];
    #print str(ports)

    #--- we know we are going to need to get the set of flows so lets just do that now
    sg.collection_epoch += 1
    flow = of.ofp_match()
    flow.wildcards = 0xffffffff
    ref.send_flow_stats_request(dp_id, flow,0xff)

    port_list = []
    for i in range(0, len(ports)):
      port = {}#ports[i]
      port['name']    = ports[i]['name']
      port['hw_addr'] = dbus.UInt64(mac_to_int(ports[i]['hw_addr']))
      port['port_no'] = dbus.UInt16(ports[i]['port_no'])

      #assert(ports[i]['state'] <= 4294967295)
      port['config']      = ports[i]['config'] #dbus.UInt32(ports[i]['config'])
      port['state']       = dbus.UInt32(ports[i]['state'])
      port['curr']        = dbus.UInt32(ports[i]['curr'])
      port['advertised']  = dbus.UInt32(ports[i]['advertised'])
      port['supported']   = dbus.UInt32(ports[i]['supported'])
      port['peer']        = dbus.UInt32(ports[i]['peer'])
      #print str(port['config']) +  " vs " + str(ports[i]['config'])
      port_dict = dbus.Dictionary(port, signature='sv') 
      port_list.append(port)

    #print str(port_list)
    sg.datapath_join(dp_id,ip_address,port_list)
    

def datapath_leave_callback(sg,dp_id):
    if dp_id in switches:
        switches.remove(dp_id)
    if dp_id in last_flow_stats:
        del last_flow_stats[dp_id]
    if dp_id in flowmod_callbacks:
        del flowmod_callbacks[dp_id]

    sg.datapath_leave(dp_id)

def barrier_reply_callback(sg,dp_id,xid):

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
    sg.barrier_reply(dp_id,xid)


def error_callback(sg, dpid, error_type, code, data, xid):
    
    logger.error("handling error from %s, xid = %d" % (dpid, xid))
    intxid = c_ntohl(xid)
    if flowmod_callbacks.has_key(dpid):
        flows = flowmod_callbacks[dpid]
        if(flows.has_key(intxid)):
            flows[intxid]["result"] = FWDCTL_FAILURE
            flows[intxid]["error"] = {}
            flows[intxid]["error"]["type"] = error_type
            flows[intxid]["error"]["code"] = code
            

def packet_in_callback(sg, dpid,in_port,reason, length,buffer_id, data) :
    sg.packet_in(dpid,in_port,reason, length,buffer_id, data.arr)


inst = None

# send a barrier message with a reference to the actual function we want to run when the switch
# has responded and told us that it is ready
def _do_install(dpid,xid,match,actions):
    
    if not flowmod_callbacks.has_key(dpid):
        flowmod_callbacks[dpid] = {}
    
    flowmod_callbacks[dpid][xid] = {"result": FWDCTL_WAITING, "match": match, "actions": actions}
    
    return 1

def run_glib ():
    """ Process glib events within NOX """
    context = gobject.MainLoop().get_context()
    def mainloop ():
      # Loop as long as events are being dispatched
        while context.pending():
            context.iteration(False)
            #--- hack where by we poll the dbus reactor to see if there are events to work 
            #--- the rate of incoming requests we can process to something like 500/sec
            #--- this should have no effect on the rate that we send events out over the dbus
        inst.post_callback(0.001, mainloop) # Check again later
            
    def print_highwater():
        logger.info(string)
        counter = 0

    mainloop() # Kick it off


    


class nddi_dbus(Component):

    def __init__(self, ctxt):
	global inst
        Component.__init__(self, ctxt)
        self.st = {}
        inst = self
        self.ctxt = ctxt
        self.collection_epoch_duration = 10
        self.latest_flow_stats = {}
        
        
        
    def install(self):
	#--- setup the dbus foo
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        bus = dbus.SystemBus()
        gobject.threads_init()
        run_glib()
        name = dbus.service.BusName(ifname, bus)

        self.sg = dBusEventGen(name,"/controller1")
        self.sg_ro = dBusEventGenRo(name,"/controller_ro")
        self.flow_stats = {}
	#--- register for nox events 
	self.register_for_datapath_join (lambda dpid, stats : 
                                         datapath_join_callback(self,self.sg,dpid, self.ctxt.get_switch_ip(dpid), stats) 
                                         )

        self.register_for_error(lambda dpid, error_type, code, data, xid: error_callback(self.sg, dpid, error_type, code, data, xid))

        self.register_for_datapath_leave(lambda dpid : 
                                          datapath_leave_callback(self.sg,dpid) )

        self.register_for_barrier_reply(lambda dpid, xid: barrier_reply_callback(self.sg,dpid,xid) )

	self.register_for_port_status(lambda dpid, reason, port : 
                                       port_status_callback(self.sg,dpid, reason, port) )
        
	#--- this is a a special event generated by the discovery service, 
	#---   which is why there isnt the handy register_for_* method
	self.register_handler (Link_event.static_get_name(),
                               lambda  info : link_event_callback(self.sg, info ))

        self.register_for_flow_stats_in(self.flow_stats_in_handler)

        self.fire_send_fv_packets()
        self.fire_flow_stats_timer()

    def fire_flow_stats_timer(self):
        for dpid in switches:
            self.sg.collection_epoch += 1
            flow = of.ofp_match()
            flow.wildcards = 0xffffffff
            self.send_flow_stats_request(dpid, flow,0xff)

        self.post_callback(30, self.fire_flow_stats_timer)

    def fire_send_fv_packets(self):

        time_val = time() * 1000
        logger.info("Sending FV Packets rate: " + str(self.sg.fv_pkt_rate) + " with vlan: " + str(self.sg.VLAN_ID) + " packets: " + str(len(self.sg.packets)))

        for pkt in self.sg.packets:
            logger.info("Packet:")
            packet = ethernet()
            packet.src = '\x00' + struct.pack('!Q',pkt[0])[3:8]
            packet.dst = NDP_MULTICAST

            payload = struct.pack('QHQHq',pkt[0],pkt[1],pkt[2],pkt[3],time_val)

            if(self.sg.VLAN_ID != None and self.sg.VLAN_ID != 65535):
                vlan_packet = vlan()
                vlan_packet.id = self.sg.VLAN_ID
                vlan_packet.c = 0
                vlan_packet.pcp = 0
                vlan_packet.eth_type = 0x88b6
                vlan_packet.set_payload(payload)

                packet.set_payload(vlan_packet)
                packet.type = ethernet.VLAN_TYPE

            else:
                packet.set_payload(payload)
                packet.type = 0x88b6

            inst.send_openflow_packet(pkt[0], packet.tostring(), int(pkt[1]))

        self.post_callback(fv_pkt_rate, self.fire_send_fv_packets)

    def getInterface(self):
        return str(nddi_dbus)

    def flow_stats_in_handler(self, dpid, flows, done, xid):

        if dpid in self.flow_stats:
            if self.flow_stats[dpid] == None:
                self.flow_stats[dpid] = {"time": int(time()) , "flows": flows}
            else:
                self.flow_stats[dpid]["flows"].extend(flows)
        else:
            self.flow_stats[dpid] = {"time": int(time()) , "flows": flows}

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
            request.header.xid = c_htonl(long(self.sg.collection_epoch))
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



def getFactory():
    class Factory:
        def instance(self, ctxt):
            return nddi_dbus(ctxt)

    return Factory()
