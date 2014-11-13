#--------------------------------------------------------------------
#----- D-Bus API for Ryu
#-----
#----- $HeadURL:
#----- $Id:
#-----
#----- provides API for interacting with Ryu using DBUS 
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

import logging
import struct
import time
import socket

from ryu import cfg
from ryu.base import app_manager
from ryu.controller import ofp_event
from ryu.controller.handler import MAIN_DISPATCHER, DEAD_DISPATCHER, CONFIG_DISPATCHER, HANDSHAKE_DISPATCHER
from ryu.controller.handler import set_ev_cls
from ryu.ofproto import ether
from ryu.ofproto import ofproto_v1_0
from ryu.controller import dpset
from ryu.lib import hub
from ryu.lib import dpid as dpid_lib
from ryu.app.wsgi import ControllerBase, WSGIApplication, route
from ryu.lib.packet import packet
from ryu.lib.packet import ethernet

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
last_flow_stats = {}

class dBusEventGenRo(dbus.service.Object):

    def __init__(self,bus,path,controller):
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

    def __init__(self, bus, path,controller):
       dbus.service.Object.__init__(self, bus_name=bus, object_path=path)
       self.controller = controller
       self.fv_pkt_rate = 1
       self.VLAN_ID = None
       self.packets = []

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
        logger.info("VLAN ID: " + str(self.VLAN_ID))
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
        print "Get Flow Stats!!!!!"
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
    def install_default_drop(self, dpid_uint):
        dpid = "%016x" % dpid_uint

        if not dpid in self.controller.datapaths.keys():
            return 0;

        my_attrs           = {}
        my_attrs[PRIORITY] = 1
        actions            = []
        
        xid = self.install_datapath_flow( dpid_uint,
                                          my_attrs,
                                          actions)
        
        return xid

    @dbus.service.method(dbus_interface=ifname,
                         in_signature='q',
                         out_signature='q')
    def register_for_fv_in(self, vlan):
        #ether type 88b6 is experimental
        #88b6 IEEE 802.1 IEEE Std 802 - Local Experimental
        
        
        return 1

    @dbus.service.method(dbus_interface=ifname,
                         in_signature='tq',
                         out_signature='t'
                         )
    def install_default_forward(self, dpid_uint, vlan):
        dpid = "%016x" % dpid_uint

        if not dpid in self.controller.datapaths.keys():
            return 0;

        datapath = self.controller.datapaths[dpid]
        ofp      = datapath.ofproto

        my_attrs          = {}
        my_attrs['DL_TYPE'] = 0x88cc       
        my_attrs['DL_VLAN'] = vlan
        actions = [[ofp.OFPAT_OUTPUT, [65535, ofp.OFPP_CONTROLLER]]]
        
        idle_timeout = 0
        hard_timeout = 0
        xid = self.install_datapath_flow(dpid_uint, my_attrs, actions)

        my_attrs = {}
        my_attrs['DL_VLAN'] = vlan
        my_attrs['DL_TYPE'] = 0x88b6 
        actions = [[ofp.OFPAT_OUTPUT, [65535, ofp.OFPP_CONTROLLER]]]
        
        idle_timeout = 0
        hard_timeout = 0
        xid = self.install_datapath_flow(dpid_uint, my_attrs,actions)
        
        return xid

    @dbus.service.method(dbus_interface=ifname,
                         in_signature='ta{sv}a(qv)',
                         out_signature='t'
                         )
    def install_datapath_flow(self,dpid_uint,attrs,actions):
        dpid = "%016x" % dpid_uint

        if not dpid in self.controller.datapaths.keys():
            return 0; 

        datapath = self.controller.datapaths[dpid]
        ofp      = datapath.ofproto
        parser   = datapath.ofproto_parser

        match = parser.OFPMatch( in_port = attrs.get('IN_PORT'),
                                 dl_type = attrs.get('DL_TYPE'),
                                 dl_vlan = attrs.get('DL_VLAN'),
                                 dl_dst  = attrs.get('DL_DST'))

        of_actions = []

        for action in actions:
            act_type = action[0]
            if(act_type == ofp.OFPAT_STRIP_VLAN):
                of_actions.append(parser.OFPActionStripVlan())
            elif(act_type == ofp.OFPAT_SET_VLAN_VID):
                of_actions.append(parser.OFPActionVlanVid(action[1]))
            elif(act_type == ofp.OFPAT_OUTPUT):
                of_actions.append(parser.OFPActionOutput(action[1][1],action[1][0]))
            else:
                logger.error("Unsupported Action Type")

        if(attrs.get('PRIORITY') == None):
            attrs['PRIORITY'] = 32768
            
        if(attrs.get('IDLE_TIMEOUT') == None):
            attrs['IDLE_TIMEOUT'] = 0

        if(attrs.get('HARD_TIMEOUT') ==None):
            attrs['HARD_TIMEOUT'] = 0

        mod = parser.OFPFlowMod( datapath = datapath,
                                 priority = attrs.get('PRIORITY'),
                                 match    = match,
                                 cookie   = 0,
                                 command  = ofp.OFPFC_ADD,
                                 actions  = of_actions,
                                 idle_timeout = attrs.get('IDLE_TIMEOUT'),
                                 hard_timeout = attrs.get('HARD_TIMEOUT'))

        datapath.set_xid(mod)
        xid = mod.xid
        datapath.send_msg(mod)
        
        logger.info("Added Flow Mod!")

        _do_install(dpid,xid,match,actions)

        return xid


    @dbus.service.method(dbus_interface=ifname,
                         in_signature='ta{sv}a(qv)',
                         out_signature='t'
                         )
    def delete_datapath_flow(self,dpid_uint, attrs, actions ):
        dpid = "%016x" % dpid_uint

        if not dpid in self.controller.datapaths.keys():
            return 0;

        datapath = self.controller.datapaths[dpid]
        ofp      = datapath.ofproto
        parser   = datapath.ofproto_parser

        match = parser.OFPMatch( in_port = attrs.get('IN_PORT'),
                                 dl_type = attrs.get('DL_TYPE'),
                                 dl_vlan = attrs.get('DL_VLAN'),
                                 dl_dst  = attrs.get('DL_DST'))

        logger.info("removing flow")

        if(attrs.get('PRIORITY') == None):
            attrs['PRIORITY'] = 32768

        mod = parser.OFPFlowMod( datapath = datapath,
                                 priority = attrs.get('PRIORITY'),
                                 match    = match,
                                 cookie   = 0,
                                 command  = ofp.OFPFC_DELETE_STRICT,
                                 actions  = [],
                                 idle_timeout = attrs.get('IDLE_TIMEOUT'),
                                 hard_timeout = attrs.get('HARD_TIMEOUT'))
        datapath.set_xid(mod)
        xid = mod.xid
        datapath.send_msg(mod)

        logger.info("Removed Flow Mod")

        _do_install(dpid,xid,match,[])

        return xid

    @dbus.service.method(dbus_interface=ifname,
                         in_signature='t',
                         out_signature='t'
                         )
    def send_barrier(self, dpid_uint):

        dpid = "%016x" % dpid_uint
        logger.info("Sending barrier for %s" % dpid)
        
        if(dpid in self.controller.datapaths.keys()):
            datapath = self.controller.datapaths[dpid]
            ofproto  = datapath.ofproto
            parser   = datapath.ofproto_parser
            barrier  = parser.OFPBarrierRequest(datapath)
            datapath.set_xid(barrier)
            xid      = barrier.xid
            datapath.send_msg(barrier)
            if not flowmod_callbacks.has_key(dpid):
                flowmod_callbacks[dpid] = {}
            flowmod_callbacks[dpid][xid] = {"result": FWDCTL_WAITING}
            return xid
        else:
            logger.error("No node with dpid: %s" % dpid)
            return -1

#--- series of callbacks to glue the reception of NoX events to the generation of D-Bus events
def port_status_callback(sg, dp_id, ofp_port_reason, attrs):
    attr_dict = {}
#    if attrs:
#      attr_dict = dbus.Dictionary(attrs, signature='sv')
    
    #--- convert mac 
#    attr_dict['hw_addr'] = dbus.UInt64(int(attr_dict['hw_addr']))
    #--- generate signal   
    sg.port_status(dp_id,ofp_port_reason,attr_dict)

def fv_packet_in_callback(sg,dp,inport,reason,len,packet):
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

def datapath_join_callback(ref,sg,dpid,ip_address,ports):
    
    ip_address = struct.unpack("!I",socket.inet_aton(ip_address[0]))[0]

    #--- we know we are going to need to get the set of flows so lets just do that now
    dpid_str = "%016x" % dpid
    ref._request_stats(ref.datapaths[dpid_str])

    port_list = []

    for p in ports:
        p_info = ports[p]

        port = {}
        port['name']    = p_info.name
        port['port_no'] = dbus.UInt16(p_info.port_no)
        
        port['hw_addr'] = dbus.UInt64(int(p_info.hw_addr.replace(':',''),16))
        port['state']   = dbus.UInt32(p_info.state)
        port['curr']    = dbus.UInt32(p_info.curr)
        port['config']  = dbus.UInt32(p_info.config)
        port['supported'] = dbus.UInt32(p_info.supported)
        port['advertised'] = dbus.UInt32(p_info.advertised)
        port['peer']    = dbus.UInt32(p_info.peer)
        port_list.append(port)

    sg.datapath_join(dpid,ip_address,port_list)
    

def datapath_leave_callback(sg,dp_id):
    sg.datapath_leave(dp_id)

def barrier_reply_callback(sg,dp_id,xid):
    
    if flowmod_callbacks.has_key(dp_id):
        flows = flowmod_callbacks[dp_id]
        if(flows.has_key(xid)):
            flows[xid]["status"] = ANSWERED
            flows[xid]["result"] = FWDCTL_SUCCESS
            if not flows[xid].has_key("failed_flows"):
                flows[xid]["failed_flows"] = []
            flows[xid]["failed_flows"] = []
            xids = flows.keys()
            for x in xids:
                if(x < xid):
                    if(flows[x]["result"] == FWDCTL_FAILURE):
                        flows[xid]["result"] = FWDCTL_FAILURE
                        flows[xid]["failed_flows"].append(flows[x])
                    del flows[x]
    sg.barrier_reply(dp_id,xid)


def error_callback(sg, dpid, error_type, code, data, xid):
    
    logger.error("handling error from %s, xid = %d" % (dpid, xid))
    if flowmod_callbacks.has_key(dpid):
        flows = flowmod_callbacks[dpid]
        if(flows.has_key(xid)):
            flows[xid]["result"] = FWDCTL_FAILURE
            flows[xid]["error"] = {}
            flows[xid]["error"]["type"] = error_type
            flows[xid]["error"]["code"] = code
            

def packet_in_callback(sg, dpid,in_port,reason, length,buffer_id, data) :
    sg.packet_in(dpid,in_port,reason, length,buffer_id, data.arr)

# send a barrier message with a reference to the actual function we want to run when the switch
# has responded and told us that it is ready
def _do_install(dpid,xid,match,actions):
    
    if not flowmod_callbacks.has_key(dpid):
        flowmod_callbacks[dpid] = {}
    
    flowmod_callbacks[dpid][xid] = {"result": FWDCTL_WAITING, "match": match, "actions": actions}
    
    return 1

class oess_dbus(app_manager.RyuApp):

    def __init__(self, *args, **kwargs):
        super(oess_dbus,self).__init__(*args,**kwargs)

        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        bus               = dbus.SystemBus()
        name              = dbus.service.BusName(ifname, bus)
        self.sg           = dBusEventGen(name,"/controller1",self)
        self.sg_ro        = dBusEventGenRo(name,"/controller_ro",self)
        self.collection_epoch_duration = 10
        self.latest_flow_stats = {}
        self.datapaths    = {}
        self.flow_stats   = {}
        self.stats_thread = hub.spawn(self._flow_stat_request)
        self.dbus_thread  = hub.spawn(self._start_dbus_loop)
        self.fv_thread    = hub.spawn(self._start_fv_packets)

    def _start_dbus_loop(self):
        context = gobject.MainLoop().get_context()
        while True:
            while context.pending():
                context.iteration(False)
            #so we can process other events
            hub.sleep(.001)

    @set_ev_cls(ofp_event.EventOFPErrorMsg,
                    [HANDSHAKE_DISPATCHER, CONFIG_DISPATCHER, MAIN_DISPATCHER])
    def _error_handler(self, ev):
        msg = ev.msg
        pprint.pprint(msg)
        error_callback(self.sg, ev.msg.datapath.id, msg.type, msg.code, msg.data, ev.msg.xid)

    @set_ev_cls(ofp_event.EventOFPStateChange,
                 [MAIN_DISPATCHER, DEAD_DISPATCHER])
    def _state_change_handler(self, ev):
        datapath = ev.datapath

        if ev.state == MAIN_DISPATCHER:
            if not datapath.id in self.datapaths:
                print "Node Joined!!"
                self.logger.debug('register datapath: %016x', datapath.id)
                dpid = "%016x" % datapath.id
                self.datapaths[dpid] = datapath
                datapath_join_callback(self, self.sg,datapath.id, datapath.socket.getpeername(), datapath.ports )

        elif ev.state == DEAD_DISPATCHER:
            if datapath.id in self.datapaths:
                print "Node Left"
                self.logger.debug('unregister datapath: %016x', datapath.id)
                del self.datapaths[datapath.id]
                datapath_leave_callback(self, self.sg, datapath.id)


    @set_ev_cls(ofp_event.EventOFPBarrierReply, MAIN_DISPATCHER)
    def _barrier_reply(self, ev):
        barrier_reply_callback(self.sg, ev.msg.datapath.id, ev.msg.xid)

    @set_ev_cls(ofp_event.EventOFPPortStatus,
                MAIN_DISPATCHER)
    def _port_status_handler(self, ev):
        msg        = ev.msg
        reason     = msg.reason
        port_no    = msg.desc.port_no
        link_state = msg.desc.state

        ofproto = msg.datapath.ofproto
        if reason == ofproto.OFPPR_ADD:
            self.logger.info("port added %s", port_no)
        elif reason == ofproto.OFPPR_DELETE:
            self.logger.info("port deleted %s", port_no)
        elif reason == ofproto.OFPPR_MODIFY:
            self.logger.info("port modified %s state %s", port_no,link_state)
            #--- need to check the state to see if port is down
        else:
            self.logger.info("Illeagal port state %s %s", port_no, reason)
            return
        
        attr_dict = {}
        if attrs:
            attr_dict = dbus.Dictionary(attrs, signature='sv')

        self.sg.port_status(ev.datapath.id, reason, attr_dict)

    @set_ev_cls(ofp_event.EventOFPPacketIn, MAIN_DISPATCHER)
    def _packet_in_handler(self, ev):
        msg = ev.msg
        datapath = msg.datapath
        ofproto = datapath.ofproto
        parser = datapath.ofproto_parser
        in_port = msg.match['in_port']
        dl_type = msg.match['dl_type']
        dl_vlan = msg.match['dl_vlan']
        pkt = packet.Packet(msg.data)
        dpid = datapath.id
        self.logger.info("packet in %s %s %s %s", dpid, src, dst, in_port)
        if(dl_vlan == self.VLAN_ID and dl_type == 34998):
            fv_packet_in_callback(self.sg,dpid,in_port,len(pkt),pkt)

    def _flow_stat_request(self):
        while True:
            print "Requesting Flow Stats"
            for datapath in self.datapaths.keys():
                self._request_stats(self.datapaths[datapath])
            hub.sleep(30)

    def _start_fv_packets(self):
        while True:
            time_val = time() * 1000
            logger.info("Sending FV Packets rate: " + str(self.sg.fv_pkt_rate)
                        + " with vlan: " + str(self.sg.VLAN_ID) + 
                        " packets: " + str(len(self.sg.packets)))

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
                    
                    actions = [parser.OFPActionOutput(int(pkt[1]))]
                    out = parser.OFPPacketOut(datapath=datapath, actions=actions, data=packet)
                    datapath.send_msg(out)
            hub.sleep(self.sg.fv_pkt_rate)

    @set_ev_cls(ofp_event.EventOFPFlowStatsReply, MAIN_DISPATCHER)
    def flow_stats_in_handler(self, ev):
 
        dpid = "%016x" % ev.msg.datapath.id
        body = ev.msg.body
        ofproto = ev.msg.datapath.ofproto
        
        flows = []
        for stat in body:
            match = stat.match.__dict__
            wildcards = stat.match.wildcards
            
            flows.append({'match': match,
                          'wildcards': wildcards,
                          'packet_count': stat.packet_count
                          })
            
        if dpid in self.flow_stats:
            if self.flow_stats[dpid] == None:
                self.flow_stats[dpid] = {"time": int(time()) , "flows": flows}
            else:
                self.flow_stats[dpid]["flows"].extend(flows)
        else:
            self.flow_stats[dpid] = {"time": int(time()) , "flows": flows}

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

    def _request_stats(self,datapath):
        print "Requested Stats"
        ofp    = datapath.ofproto
        parser = datapath.ofproto_parser
        
        cookie = cookie_mask = 0
        match  = parser.OFPMatch()
        req    = parser.OFPFlowStatsRequest(datapath, 
                                            0,
                                            match,
                                            0xff,
                                            ofp.OFPP_NONE)
        datapath.send_msg(req)
        
        req = parser.OFPPortStatsRequest(datapath, 0, ofp.OFPP_NONE)
        datapath.send_msg(req)


