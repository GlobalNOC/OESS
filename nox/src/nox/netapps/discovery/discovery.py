# Copyright 2008 (C) Nicira, Inc.
# 
# This file is part of NOX.
# 
# NOX is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# NOX is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with NOX.  If not, see <http://www.gnu.org/licenses/>.



from nox.lib.core import *

import logging

from nox.netapps.discovery.pylinkevent   import Link_event
from nox.netapps.bindings_storage.pybindings_storage import pybindings_storage
from nox.netapps.user_event_log.pyuser_event_log import pyuser_event_log,LogLevel
from nox.lib.packet.packet_utils      import array_to_octstr
from nox.lib.packet.packet_utils      import longlong_to_octstr
from nox.lib.packet.ethernet          import LLDP_MULTICAST, NDP_MULTICAST
from nox.lib.packet.ethernet          import ethernet  
from nox.lib.packet.lldp              import lldp, chassis_id, port_id, end_tlv
from nox.lib.packet.lldp              import ttl 
from nox.lib.packet.vlan              import vlan
from nox.lib.netinet.netinet          import create_datapathid_from_host
from nox.lib.openflow                 import OFPP_LOCAL


import struct
import array
import socket
import time
import copy

LLDP_TTL             = 120 # currently ignored
LLDP_SEND_PERIOD     = .10 
TIMEOUT_CHECK_PERIOD = 5.
LINK_TIMEOUT         = 30.
VLAN_ID              = None

lg = logging.getLogger('discovery')

# ---------------------------------------------------------------------- 
#  Utility function to create an lldp packet given a chassid
# 
#  Create lldp packet using the least significant 48 bits of dpid for
#  chassis ID 
# 
# ---------------------------------------------------------------------- 
  
def create_discovery_packet(dpid, portno, vlan_id, ttl_):    

    # Create lldp packet
    discovery_packet = lldp()
    cid = chassis_id()

    # nbo 
    cid.fill(chassis_id.SUB_LOCAL, array.array('B', 'dpid:' + hex(long(dpid))[2:-1]))
    discovery_packet.add_tlv(cid)

    pid = port_id()
    pid.fill(2,array.array('B',struct.pack('!H', portno)))
    discovery_packet.add_tlv(pid)

    ttlv = ttl()
    ttlv.fill(ttl_)
    discovery_packet.add_tlv(ttlv)

    discovery_packet.add_tlv(end_tlv())

    eth = ethernet()
    eth.src = '\x00' + struct.pack('!Q',dpid)[3:8]
    eth.dst = NDP_MULTICAST
    
    if(vlan_id != None):
        
        vlan_packet = vlan()
        vlan_packet.id = vlan_id
        vlan_packet.pcp = 0
        vlan_packet.c = 0
        vlan_packet.eth_type = ethernet.LLDP_TYPE
        vlan_packet.set_payload(discovery_packet)

        eth.set_payload(vlan_packet)
        eth.type = ethernet.VLAN_TYPE
        eth.eth_type = ethernet.LLDP_TYPE
    
    else:
        eth.set_payload(discovery_packet)
        eth.type = ethernet.LLDP_TYPE
        

    return eth

## \ingroup noxcomponents
# LLDP discovery application for topology inference
#
# This application handles generation and parsing/interpreting LLDP
# packets for all switches on the network. The bulk of the functionality
# is performed in the following handlers:
# <ul>
# <li>send_lldp() : this is a generator function which is called in a timer
# every timeout period.  It iterates over all ports on the network and
# sends an LLDP packet on each invocation (note: that is exactly *one*
# packet per timeout period).  The LLDP packets contain the chassis ID,
# and the port number of the outgoing switch/port
#
# <li>lldp_input_handler() : packet_in handler called on receipt of an LLDP
# packet. This infers the link-level connectivity by querying the LLDP
# packets.  The network links are stored in the instance variable
# adjacency_list
#
# <li>timeout_links() : periodically iterates over the discovered links on
# the network and detects timeouts.  Timeouts update the global view and
# generate a node changed event
# </ul>
#
# <b>Inferring links:</b><br>
# <br>
# Each LLDP packet contains the sending port and datapath ID.  The
# datapath is currently encoded as a 48bit MAC in the chassis ID TLV,
# hence the lower 16bits are always 0. 
#
# <b>Shortcomings:</b>
#
# The fundamental problem with a centralized approach to topology
# discovery is that all ports must be scanned linearly which greatly
# reduces response time. 
#
# This should really be implemented on the switch

class discovery(Component):

    def __init__(self, ctxt):
        Component.__init__(self, ctxt)

        self._bindings       = self.resolve(pybindings_storage)
        self._user_event_log = self.resolve(pyuser_event_log)

        self.dps            = {}
        self.lldp_packets   = {}
        self.adjacency_list = {}

    def configure(self, configuration):

        arg_len = len(configuration['arguments'])


        self.lldp_send_period = LLDP_SEND_PERIOD
        self.vlan_id = VLAN_ID
        if arg_len == 1:
            try:
                val = float(configuration['arguments'][0])
                self.lldp_send_period = val;
                lg.debug("Setting LLDP send timer to " + str(val))
            except Exception, e:
                lg.error("unable to convert arg to float " + configuration['arguments'][0])

        elif arg_len == 2:
            try:
                val = float(configuration['arguments'][0])
                self.lldp_send_period = val;
                lg.debug("Setting LLDP send timer to " + str(val))

                val = int(configuration['arguments'][1])
                self.vlan_id = val;
                lg.debug("Setting LLDP VLAN to " + str(val))

            except Exception, e:
                lg.error("unable to convert arg to integer " + configuration['arguments'][0])
    

        self.register_event(Link_event.static_get_name())
        Link_event.register_event_converter(self.ctxt)

    def install(self):
        self.register_for_datapath_join ( lambda dp,stats : discovery.dp_join(self, dp, stats) )
        self.register_for_datapath_leave( lambda dp       : discovery.dp_leave(self, dp) )
        self.register_for_port_status( lambda dp, reason, port : discovery.port_status_change(self, dp, reason, port) )
        # register handler for all LLDP packets 
        if(self.vlan_id != None):
            match = {
                DL_DST : array_to_octstr(array.array('B',NDP_MULTICAST)),DL_TYPE: ethernet.LLDP_TYPE, DL_VLAN: self.vlan_id}
        else:
            match = {
                DL_DST: array_to_octstr(array.array('B',NDP_MULTICAST)),DL_TYPE: ethernet.LLDP_TYPE }
                
        self.register_for_packet_match(lambda
            dp,inport,reason,len,bid,packet :
            discovery.lldp_input_handler(self,dp,inport,reason,len,bid,packet),
            0xffff, match)

        self.start_lldp_timer_thread()

    def getInterface(self):
        return str(discovery)

    # --
    # On datapath join, create a new LLDP packet per port 
    # --

    def dp_join(self, dp, stats): 
        self.dps[dp] = stats
  
        self.lldp_packets[dp]  = {}
        for port in stats[PORTS]:
            if port[PORT_NO] == OFPP_LOCAL:
                continue

            self.lldp_packets[dp][port[PORT_NO]] = create_discovery_packet(dp, port[PORT_NO], self.vlan_id, LLDP_TTL);

    # --
    # On datapath leave, delete all associated links
    # --

    def dp_leave(self, dp): 
    
        if dp in self.dps:
            del self.dps[dp]  
        if dp in self.lldp_packets:
            del self.lldp_packets[dp]  
    
        deleteme = []
        for linktuple in self.adjacency_list:
            if linktuple[0] == dp or linktuple[2] == dp: 
                deleteme.append(linktuple)
    
        self.delete_links(deleteme)


    # --
    # Update the list of LLDP packets if ports are added/removed
    # --

    def port_status_change(self, dp, reason, port):
        '''Update LLDP packets on port status changes

        Add to the list of LLDP packets if a port is added.
        Delete from the list of LLDP packets if a port is removed.

        Keyword arguments:
        dp -- Datapath ID of port
        reason -- what event occured
        port -- port
        '''
        # Only process 'sane' ports
        if port[PORT_NO] <= openflow.OFPP_MAX:
            if reason == openflow.OFPPR_ADD:
                self.lldp_packets[dp][port[PORT_NO]] = create_discovery_packet(dp, port[PORT_NO], self.vlan_id, LLDP_TTL);
            elif reason == openflow.OFPPR_DELETE:
                del self.lldp_packets[dp][port[PORT_NO]]

        return CONTINUE


    def timeout_links(self):

      curtime = time.time()
      self.post_callback(TIMEOUT_CHECK_PERIOD, lambda : discovery.timeout_links(self))

      deleteme = []
      for linktuple in self.adjacency_list:
          if (curtime - self.adjacency_list[linktuple]) > LINK_TIMEOUT:
              deleteme.append(linktuple)
              lg.warn('link timeout ('+longlong_to_octstr(linktuple[0])+" p:"\
                         +str(linktuple[1]) +' -> '+\
                         longlong_to_octstr(linktuple[2])+\
                         'p:'+str(linktuple[3])+')')

      self.delete_links(deleteme)

    # ---------------------------------------------------------------------- 
    #  Handle incoming lldp packets.  Use to maintain link state
    # ---------------------------------------------------------------------- 

    def lldp_input_handler(self, dp_id, inport, ofp_reason, total_frame_len, buffer_id, packet):
        
        if(packet.type == ethernet.VLAN_TYPE):
            packet = packet.next
            assert (packet.eth_type == ethernet.LLDP_TYPE)
        elif(packet.type == ethernet.LLDP_TYPE):
            assert (packet.type == ethernet.LLDP_TYPE)
        else:
            #we should not get here!
            lg.error("lldp_input_handler did not get a proper packet")
            return

        if not packet.next:
            lg.error("lldp_input_handler lldp packet could not be parsed")
            return
    
        assert (isinstance(packet.next, lldp))
    
        lldph = packet.next
        if  (len(lldph.tlvs) < 4) or \
            (lldph.tlvs[0].type != lldp.CHASSIS_ID_TLV) or\
            (lldph.tlvs[1].type != lldp.PORT_ID_TLV) or\
            (lldph.tlvs[2].type != lldp.TTL_TLV):
            lg.error("lldp_input_handler invalid lldp packet")
            return

        # parse out chassis id 
        if lldph.tlvs[0].subtype != chassis_id.SUB_LOCAL:
            lg.error("lldp chassis ID subtype is not 'local', ignoring")
            return
        if not lldph.tlvs[0].id.tostring().startswith('dpid:'):
            lg.error("lldp chassis ID is not a dpid, ignoring")
            return
        try:
            chassid = int(lldph.tlvs[0].id.tostring()[5:], 16)
        except:
            lg.error("lldp chassis ID is not numeric', ignoring")
            return

        # if chassid is from a switch we're not connected to, ignore
        if chassid not in self.dps:
            lg.debug('Recieved LLDP packet from unconnected switch')
            return
    
        # grab 16bit port ID from port tlv
        if lldph.tlvs[1].subtype != port_id.SUB_PORT:
            return # not one of ours
        if len(lldph.tlvs[1].id) != 2:
            lg.error("invalid lldph port_id format")
            return
        (portid,)  =  struct.unpack("!H", lldph.tlvs[1].id)

        if (dp_id, inport) == (chassid, portid):
            lg.error('Loop detected, received our own LLDP event')
            return

        # print 'LLDP packet in from',longlong_to_octstr(chassid),' port',str(portid)
    
        linktuple = (dp_id, inport, chassid, portid)
    
        if linktuple not in self.adjacency_list:
            self.add_link(linktuple)
            lg.warn('new link detected ('+longlong_to_octstr(linktuple[0])+' p:'\
                       +str(linktuple[1]) +' -> '+\
                       longlong_to_octstr(linktuple[2])+\
                       ' p:'+str(linktuple[3])+')')
    
    
        # add to adjaceny list or update timestamp
        self.adjacency_list[(dp_id, inport, chassid, portid)] = time.time()

    # ---------------------------------------------------------------------- 
    # Start LLDP timer which sends an LLDP packet every
    # LLDP_SEND_PEROID.
    # ---------------------------------------------------------------------- 

    def start_lldp_timer_thread(self):

        #---------------------------------------------------------------------- 
        # Generator which iterates over a set of dp's and sends an LLDP packet
        # out of each port.  
        #---------------------------------------------------------------------- 
        
        def send_lldp (packets):
            for dp in packets:
                # if they've left, ignore
                if not dp in self.dps:
                    continue
                try:    
                    for port in packets[dp]:
                        #print 'Sending packet out of ',longlong_to_octstr(dp), ' port ',str(port)
                        self.send_openflow_packet(dp, packets[dp][port].tostring(), port)
                        yield dp 
                except Exception, e:
                    # catch exception while yielding
                    lg.error('Caught exception while yielding'+str(e))
        
        def build_lldp_generator():
            
            def g():
                try:
                    g.sendfunc.next()
                except StopIteration, e:    
                    g.sendfunc = send_lldp(copy.deepcopy(self.lldp_packets))
                except Exception, e:    
                    lg.error('Caught exception from generator '+str(e))
                    g.sendfunc = send_lldp(copy.deepcopy(self.lldp_packets))
                self.post_callback(self.lldp_send_period, g)
            g.sendfunc = send_lldp(copy.deepcopy(self.lldp_packets))
            return g

        self.post_callback(self.lldp_send_period, build_lldp_generator())
        self.post_callback(TIMEOUT_CHECK_PERIOD, lambda : discovery.timeout_links(self))

    def post_link_event(self, linktuple, action):
        e = Link_event(create_datapathid_from_host(linktuple[0]),
                      create_datapathid_from_host(linktuple[2]),
                      linktuple[1], linktuple[3], action)
        self.post(e)

    #---------------------------------------------------------------------- 
    #  Link addition/deletion
    #---------------------------------------------------------------------- 

    def add_link(self, linktuple):            
        self.post_link_event(linktuple, Link_event.ADD)
        src_dpid = create_datapathid_from_host(linktuple[0])
        src_port = linktuple[1]
        dst_dpid = create_datapathid_from_host(linktuple[2])
        dst_port = linktuple[3]
        self._bindings.add_link(src_dpid,src_port,dst_dpid,dst_port)
        self._user_event_log.log("discovery",LogLevel.ALERT, 
            "Added network link between {sl} and {dl}",
            set_src_loc = (src_dpid,src_port), 
            set_dst_loc = (dst_dpid,dst_port)) 

    def delete_links(self, deleteme):

        for linktuple in deleteme:                    
            del self.adjacency_list[linktuple]
            src_dpid = create_datapathid_from_host(linktuple[0])
            src_port = linktuple[1]
            dst_dpid = create_datapathid_from_host(linktuple[2])
            dst_port = linktuple[3]
            try:
                self._bindings.remove_link(src_dpid,src_port,dst_dpid,dst_port)
                self._user_event_log.log("discovery",LogLevel.ALERT, 
                  "Removed network link between {sl} and {dl}", 
                  set_src_loc = (src_dpid,src_port), 
                  set_dst_loc = (dst_dpid,dst_port)) 
            except Exception, e:        
              lg.error('Error removing links from binding storage')
                
            self.post_link_event(linktuple, Link_event.REMOVE)

    #---------------------------------------------------------------------- 
    #   Public API
    #---------------------------------------------------------------------- 

    def is_switch_only_port(self, dpid, port):
        """ Returns True if (dpid, port) designates a port that has any
        neighbor switches"""
        for dp1, port1, dp2, port2 in self.adjacency_list:
            if dp1 == dpid and port1 == port:
                return True
            if dp2 == dpid and port2 == port:
                return True
        return False


def getFactory():
    class Factory:
        def instance(self, ctxt):
            return discovery(ctxt)

    return Factory()
