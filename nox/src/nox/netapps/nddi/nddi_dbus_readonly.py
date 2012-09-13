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
logger = logging.getLogger('org.nddi.openflow_readonly')

ifname = 'org.nddi.openflow_readonly'

barrier_callbacks = {}
xid_callbacks = {}

#--- this is a a wrapper class that defineds the dbus interface
class dBusEventGenReadonly(dbus.service.Object):

    def __init__(self, bus, path):
       dbus.service.Object.__init__(self, bus_name=bus, object_path=path)
       self.switches = set([])

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

    @dbus.service.method(dbus_interface=ifname,
                         in_signature='t',
                         out_signature='b'
                         )
    def get_node_connect_status(self, status_dpid):
        for dpid in self.switches:
            if dpid == status_dpid:
                return True
        return False

    @dbus.service.method(dbus_interface=ifname,
                         in_signature='t',
                         out_signature=''
                         )
    def send_flow_stats_request(self, dpid):
        """Send a flow stats request to a switch (dpid).
        @param dpid - datapath/switch to contact
        """
        self.collection_epoch += 1
        flow = of.ofp_match()
        flow.wildcards = 0xffffffff
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
        logger.info("flowmod sent at: " + time.time() + "for " + dpid)


#def get_xid_result(self, xid):
#        logger.info("Checking xid %s" % str(xid))
#        if xid_callback.has_key(xid):    
#            data = xid_callback[xid]
#            del xid_callbacks[xid]
#            return data
#        return

inst = None

def datapath_join_callback(sg,dp_id,ip_address,stats):

    # NOX gives us the IP address in the native order, move it to network                                                                                                                      
    tmp = struct.pack("@I", ip_address)
    ip_address = struct.unpack("!I", tmp)[0]

    if not dp_id in sg.switches:
        sg.switches.add(dp_id)

def datapath_leave_callback(sg,dp_id):
    if dp_id in sg.switches:
        sg.switches.remove(dp_id)

    sg.datapath_leave(dp_id)

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

    mainloop() # Kick it off



class nddi_dbus_readonly(Component):

    def __init__(self, ctxt):
	global inst
        Component.__init__(self, ctxt)
        self.st = {}
        inst = self
        self.ctxt = ctxt
        self.collection_epoch = 0
        self.collection_epoch_duration = 10
        self.flow_stats = {}

    def install(self):
	#--- setup the dbus foo
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        bus = dbus.SystemBus()
        gobject.threads_init()
        run_glib()
        name = dbus.service.BusName("org.nddi.openflow_readonly", bus)
        

        self.sg = dBusEventGenReadonly(name,"/controller2")
        
	#--- register for nox events 
	self.register_for_datapath_join (lambda dp, stats : 
                                         datapath_join_callback(self.sg,dp, self.ctxt.get_switch_ip(dp), stats) 
                                         )

        self.register_for_datapath_leave(lambda dp : 
                                          datapath_leave_callback(self.sg,dp) )

        self.register_for_flow_stats_in(self.flow_stats_in_handler)
        self.fire_flow_stats_timer()


    def fire_flow_stats_timer(self):
        for dpid in self.sg.switches:
            self.collection_epoch += 1
            flow = of.ofp_match()
            flow.wildcards = 0xffffffff
            self.send_flow_stats_request(dpid, flow,0xff)

        self.post_callback(60, self.fire_flow_stats_timer)


    def getInterface(self):
        return str(nddi_dbus_readonly)

    def flow_stats_in_handler(self, dpid, flows, done, xid):
        logger.info("flowmod received at: " + time.time() + " from dpid: " + dpid)

def getFactory():
    class Factory:
        def instance(self, ctxt):
            return nddi_dbus_readonly(ctxt)

    return Factory()



