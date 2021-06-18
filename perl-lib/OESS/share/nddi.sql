-- MySQL dump 10.14  Distrib 5.5.56-MariaDB, for Linux (x86_64)
--
-- Host: localhost    Database: oess
-- ------------------------------------------------------
-- Server version	5.5.56-MariaDB

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Current Database: `oess`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `oess` /*!40100 DEFAULT CHARACTER SET utf8 */;

USE `oess`;

--
-- Table structure for table `circuit`
--

DROP TABLE IF EXISTS `circuit`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `circuit` (
  `circuit_id` int(10) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `description` varchar(255) NOT NULL,
  `workgroup_id` int(10) NOT NULL,
  `external_identifier` varchar(255) DEFAULT NULL,
  `circuit_state` enum('scheduled','deploying','active','decom','reserved','provisioned') DEFAULT NULL,
  `restore_to_primary` int(10) DEFAULT '0',
  `static_mac` tinyint(1) DEFAULT '0',
  `remote_url` varchar(255) DEFAULT NULL,
  `remote_requester` varchar(255) DEFAULT NULL,
  `type` enum('openflow','mpls') DEFAULT 'openflow',
  PRIMARY KEY (`circuit_id`),
  UNIQUE KEY `circuit_idx` (`name`),
  KEY `workgroup_id` (`workgroup_id`),
  CONSTRAINT `circuit_ibfk_1` FOREIGN KEY (`workgroup_id`) REFERENCES `workgroup` (`workgroup_id`)
) ENGINE=InnoDB AUTO_INCREMENT=3000 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `circuit`
--

LOCK TABLES `circuit` WRITE;
/*!40000 ALTER TABLE `circuit` DISABLE KEYS */;
/*!40000 ALTER TABLE `circuit` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `circuit_edge_interface_membership`
--

DROP TABLE IF EXISTS `circuit_edge_interface_membership`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `circuit_edge_interface_membership` (
  `interface_id` int(10) NOT NULL,
  `circuit_id` int(10) NOT NULL,
  `end_epoch` int(10) NOT NULL,
  `start_epoch` int(10) NOT NULL,
  `extern_vlan_id` int(10) NOT NULL,
  `inner_tag` int(10) DEFAULT NULL,
  `bandwidth` int(10) DEFAULT NULL,
  `circuit_edge_id` int(10) NOT NULL AUTO_INCREMENT,
  `unit` int(11) NOT NULL,
  `mtu` int(11) NOT NULL DEFAULT 9000,
  PRIMARY KEY (`circuit_edge_id`),
  UNIQUE KEY `interface_id` (`interface_id`,`circuit_id`,`end_epoch`,`extern_vlan_id`),
  KEY `circuit_circuit_interface_membership_fk` (`circuit_id`),
  CONSTRAINT `circuit_edge_interface_membership_ibfk_1` FOREIGN KEY (`interface_id`) REFERENCES `interface` (`interface_id`),
  CONSTRAINT `circuit_edge_interface_membership_ibfk_2` FOREIGN KEY (`circuit_id`) REFERENCES `circuit` (`circuit_id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `circuit_edge_interface_membership`
--

LOCK TABLES `circuit_edge_interface_membership` WRITE;
/*!40000 ALTER TABLE `circuit_edge_interface_membership` DISABLE KEYS */;
/*!40000 ALTER TABLE `circuit_edge_interface_membership` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `circuit_edge_mac_address`
--

DROP TABLE IF EXISTS `circuit_edge_mac_address`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `circuit_edge_mac_address` (
  `circuit_edge_id` int(10) NOT NULL,
  `mac_address` bigint(20) NOT NULL,
  KEY `circuit_edge_id` (`circuit_edge_id`),
  CONSTRAINT `circuit_edge_mac_address_ibfk_1` FOREIGN KEY (`circuit_edge_id`) REFERENCES `circuit_edge_interface_membership` (`circuit_edge_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `circuit_edge_mac_address`
--

LOCK TABLES `circuit_edge_mac_address` WRITE;
/*!40000 ALTER TABLE `circuit_edge_mac_address` DISABLE KEYS */;
/*!40000 ALTER TABLE `circuit_edge_mac_address` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `circuit_instantiation`
--

DROP TABLE IF EXISTS `circuit_instantiation`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `circuit_instantiation` (
  `end_epoch` int(10) NOT NULL,
  `circuit_id` int(10) NOT NULL,
  `reserved_bandwidth_mbps` int(10) NOT NULL,
  `start_epoch` int(10) NOT NULL,
  `circuit_state` enum('scheduled','deploying','active','decom','looped','reserved','provisioned') NOT NULL DEFAULT 'scheduled',
  `modified_by_user_id` int(10) NOT NULL,
  `loop_node` int(11) DEFAULT NULL,
  `reason` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`end_epoch`,`circuit_id`),
  KEY `user_circuit_instantiaiton_fk` (`modified_by_user_id`),
  KEY `circuit_circuit_instantiaiton_fk` (`circuit_id`),
  CONSTRAINT `circuit_circuit_instantiaiton_fk` FOREIGN KEY (`circuit_id`) REFERENCES `circuit` (`circuit_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `user_circuit_instantiaiton_fk` FOREIGN KEY (`modified_by_user_id`) REFERENCES `user` (`user_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `circuit_instantiation`
--

LOCK TABLES `circuit_instantiation` WRITE;
/*!40000 ALTER TABLE `circuit_instantiation` DISABLE KEYS */;
/*!40000 ALTER TABLE `circuit_instantiation` ENABLE KEYS */;
UNLOCK TABLES;


--
-- Table structure for table `cloud_connection_vrf_ep`
--

DROP TABLE IF EXISTS `cloud_connection_vrf_ep`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `cloud_connection_vrf_ep` (
  `cloud_connection_vrf_ep_id` int(11) NOT NULL AUTO_INCREMENT,
  `vrf_ep_id` int(11) DEFAULT NULL,
  `circuit_ep_id` int(11) DEFAULT NULL,
  `cloud_account_id` varchar(255) NOT NULL,
  `cloud_connection_id` varchar(255) NOT NULL,
  PRIMARY KEY (`cloud_connection_vrf_ep_id`),
  KEY `vrf_ep_id` (`vrf_ep_id`),
  KEY `cloud_connection_circuit_ep_ibfk_1` (`circuit_ep_id`),
  CONSTRAINT `cloud_connection_vrf_ep_ibfk_1` FOREIGN KEY (`vrf_ep_id`) REFERENCES `vrf_ep` (`vrf_ep_id`) ON DELETE CASCADE,
  CONSTRAINT `cloud_connection_circuit_ep_ibfk_1` FOREIGN KEY (`circuit_ep_id`) REFERENCES `circuit_edge_interface_membership` (`circuit_edge_id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `command`
--

DROP TABLE IF EXISTS `command`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `command` (
  `command_id` int(10) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `template` varchar(255) NOT NULL,
  `type` varchar(255) NOT NULL,
  PRIMARY KEY (`command_id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `edge_interface_move_maintenance`
--

DROP TABLE IF EXISTS `edge_interface_move_maintenance`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `edge_interface_move_maintenance` (
  `maintenance_id` int(10) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `orig_interface_id` int(10) NOT NULL,
  `temp_interface_id` int(10) NOT NULL,
  `start_epoch` int(10) NOT NULL,
  `end_epoch` int(10) DEFAULT '-1',
  PRIMARY KEY (`maintenance_id`),
  KEY `orig_interface_id` (`orig_interface_id`),
  KEY `temp_interface_id` (`temp_interface_id`),
  CONSTRAINT `edge_interface_move_maintenance_ibfk_1` FOREIGN KEY (`orig_interface_id`) REFERENCES `interface` (`interface_id`),
  CONSTRAINT `edge_interface_move_maintenance_ibfk_2` FOREIGN KEY (`temp_interface_id`) REFERENCES `interface` (`interface_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `edge_interface_move_maintenance`
--

LOCK TABLES `edge_interface_move_maintenance` WRITE;
/*!40000 ALTER TABLE `edge_interface_move_maintenance` DISABLE KEYS */;
/*!40000 ALTER TABLE `edge_interface_move_maintenance` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `entity`
--

DROP TABLE IF EXISTS `entity`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `entity` (
  `entity_id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) UNIQUE,
  `description` text,
  `logo_url` varchar(255) DEFAULT NULL,
  `url` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`entity_id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;
INSERT INTO `entity` (`name`,`description`) VALUES ('Root','Default Root Entity');
--
-- Table structure for table `entity_hierarchy`
--

DROP TABLE IF EXISTS `entity_hierarchy`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `entity_hierarchy` (
  `entity_parent_id` int(11) NOT NULL,
  `entity_child_id` int(11) NOT NULL,
  KEY `entity_parent` (`entity_parent_id`),
  KEY `entity_child` (`entity_child_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `edge_interface_move_maintenance_circuit_membership`
--

DROP TABLE IF EXISTS `edge_interface_move_maintenance_circuit_membership`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `edge_interface_move_maintenance_circuit_membership` (
  `maintenance_id` int(10) NOT NULL,
  `circuit_id` int(10) NOT NULL,
  KEY `maintenance_id` (`maintenance_id`),
  KEY `circuit_id` (`circuit_id`),
  CONSTRAINT `edge_interface_move_maintenance_circuit_membership_ibfk_1` FOREIGN KEY (`maintenance_id`) REFERENCES `edge_interface_move_maintenance` (`maintenance_id`) ON DELETE CASCADE,
  CONSTRAINT `edge_interface_move_maintenance_circuit_membership_ibfk_2` FOREIGN KEY (`circuit_id`) REFERENCES `circuit` (`circuit_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `edge_interface_move_maintenance_circuit_membership`
--

LOCK TABLES `edge_interface_move_maintenance_circuit_membership` WRITE;
/*!40000 ALTER TABLE `edge_interface_move_maintenance_circuit_membership` DISABLE KEYS */;
/*!40000 ALTER TABLE `edge_interface_move_maintenance_circuit_membership` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `interface`
--

DROP TABLE IF EXISTS `interface`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `interface` (
  `interface_id` int(10) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `port_number` int(10) DEFAULT NULL,
  `description` varchar(255) NOT NULL,
  `cloud_interconnect_type` varchar(255) DEFAULT NULL,
  `cloud_interconnect_id` varchar(255) DEFAULT NULL,
  `operational_state` enum('unknown','up','down') NOT NULL DEFAULT 'unknown',
  `role` enum('unknown','trunk','customer') NOT NULL DEFAULT 'unknown',
  `node_id` int(10) NOT NULL,
  `vlan_tag_range` varchar(255) DEFAULT '-1,1-4095',
  `mpls_vlan_tag_range` varchar(255) DEFAULT NULL,
  `workgroup_id` int(10) DEFAULT NULL,
  PRIMARY KEY (`interface_id`),
  UNIQUE KEY `node_id_name_idx` (`node_id`,`name`),
  UNIQUE KEY `node_port_idx` (`node_id`,`port_number`),
  KEY `node_interface_fk` (`node_id`),
  KEY `interface_ibfk_1` (`workgroup_id`),
  CONSTRAINT `interface_ibfk_1` FOREIGN KEY (`workgroup_id`) REFERENCES `workgroup` (`workgroup_id`),
  CONSTRAINT `node_interface_fk` FOREIGN KEY (`node_id`) REFERENCES `node` (`node_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `interface`
--

LOCK TABLES `interface` WRITE;
/*!40000 ALTER TABLE `interface` DISABLE KEYS */;
/*!40000 ALTER TABLE `interface` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `interface_acl`
--

DROP TABLE IF EXISTS `interface_acl`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `interface_acl` (
  `interface_acl_id` int(10) NOT NULL AUTO_INCREMENT,
  `workgroup_id` int(10) DEFAULT NULL,
  `interface_id` int(10) NOT NULL,
  `allow_deny` enum('allow','deny') NOT NULL,
  `eval_position` int(10) NOT NULL,
  `vlan_start` int(10) NOT NULL,
  `vlan_end` int(10) DEFAULT NULL,
  `notes` text,
  `entity_id` int(11) DEFAULT NULL,
  PRIMARY KEY (`interface_acl_id`),
  KEY `workgroup_id` (`workgroup_id`),
  KEY `interface_id` (`interface_id`),
  KEY `entity_fk` (`entity_id`),
  CONSTRAINT `entity_fk` FOREIGN KEY (`entity_id`) REFERENCES `entity` (`entity_id`),
  CONSTRAINT `interface_acl_ibfk_1` FOREIGN KEY (`interface_id`) REFERENCES `interface` (`interface_id`),
  CONSTRAINT `interface_acl_ibfk_2` FOREIGN KEY (`workgroup_id`) REFERENCES `workgroup` (`workgroup_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `interface_acl`
--

LOCK TABLES `interface_acl` WRITE;
/*!40000 ALTER TABLE `interface_acl` DISABLE KEYS */;
/*!40000 ALTER TABLE `interface_acl` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `interface_instantiation`
--

DROP TABLE IF EXISTS `interface_instantiation`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `interface_instantiation` (
  `interface_id` int(10) NOT NULL,
  `end_epoch` int(10) NOT NULL,
  `admin_state` enum('unknown','up','down') NOT NULL DEFAULT 'unknown',
  `start_epoch` int(10) NOT NULL,
  `capacity_mbps` int(10) NOT NULL,
  `mtu_bytes` int(10) NOT NULL,
  PRIMARY KEY (`interface_id`,`end_epoch`),
  CONSTRAINT `interface_interface_instantiaiton_fk` FOREIGN KEY (`interface_id`) REFERENCES `interface` (`interface_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `interface_instantiation`
--

LOCK TABLES `interface_instantiation` WRITE;
/*!40000 ALTER TABLE `interface_instantiation` DISABLE KEYS */;
/*!40000 ALTER TABLE `interface_instantiation` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `link`
--

DROP TABLE IF EXISTS `link`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `link` (
  `link_id` int(10) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `remote_urn` varchar(256) DEFAULT NULL,
  `status` enum('up','down','unknown') NOT NULL DEFAULT 'unknown',
  `metric` int(11) DEFAULT '1',
  `fv_status` enum('up','down','unknown') NOT NULL DEFAULT 'unknown',
  `vlan_tag_range` varchar(255) DEFAULT NULL,
  `in_maint` enum('yes','no') NOT NULL DEFAULT 'no',
  PRIMARY KEY (`link_id`),
  UNIQUE KEY `links_idx` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `link`
--

LOCK TABLES `link` WRITE;
/*!40000 ALTER TABLE `link` DISABLE KEYS */;
/*!40000 ALTER TABLE `link` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `link_instantiation`
--

DROP TABLE IF EXISTS `link_instantiation`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `link_instantiation` (
  `link_id` int(10) NOT NULL,
  `end_epoch` int(10) NOT NULL,
  `link_state` enum('planned','available','active','maintenance','decom') NOT NULL DEFAULT 'planned',
  `start_epoch` int(10) NOT NULL,
  `interface_a_id` int(10) NOT NULL,
  `interface_z_id` int(10) NOT NULL,
  `openflow` int(1) NOT NULL DEFAULT '0',
  `mpls` int(1) NOT NULL DEFAULT '0',
  `ip_a` varchar(255) DEFAULT NULL,
  `ip_z` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`link_id`,`end_epoch`),
  KEY `interface_link_instantiation_fk` (`interface_a_id`),
  KEY `interface_link_instantiation_fk_1` (`interface_z_id`),
  CONSTRAINT `interface_link_instantiation_fk` FOREIGN KEY (`interface_a_id`) REFERENCES `interface` (`interface_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `interface_link_instantiation_fk_1` FOREIGN KEY (`interface_z_id`) REFERENCES `interface` (`interface_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `links_link_instantiation_fk` FOREIGN KEY (`link_id`) REFERENCES `link` (`link_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `link_instantiation`
--

LOCK TABLES `link_instantiation` WRITE;
/*!40000 ALTER TABLE `link_instantiation` DISABLE KEYS */;
/*!40000 ALTER TABLE `link_instantiation` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `link_maintenance`
--

DROP TABLE IF EXISTS `link_maintenance`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `link_maintenance` (
  `link_maintenance_id` int(11) NOT NULL AUTO_INCREMENT,
  `link_id` int(11) NOT NULL,
  `maintenance_id` int(11) NOT NULL,
  PRIMARY KEY (`link_maintenance_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `link_maintenance`
--

LOCK TABLES `link_maintenance` WRITE;
/*!40000 ALTER TABLE `link_maintenance` DISABLE KEYS */;
/*!40000 ALTER TABLE `link_maintenance` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `link_path_membership`
--

DROP TABLE IF EXISTS `link_path_membership`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `link_path_membership` (
  `link_id` int(10) NOT NULL,
  `end_epoch` int(10) NOT NULL,
  `path_id` int(10) NOT NULL,
  `start_epoch` int(10) NOT NULL,
  `interface_a_vlan_id` int(11) NOT NULL,
  `interface_z_vlan_id` int(11) NOT NULL,
  PRIMARY KEY (`link_id`,`end_epoch`,`path_id`,`interface_a_vlan_id`,`interface_z_vlan_id`),
  UNIQUE KEY `unique_vlan_a` (`link_id`,`end_epoch`,`interface_a_vlan_id`),
  UNIQUE KEY `unique_vlan_z` (`link_id`,`end_epoch`,`interface_z_vlan_id`),
  KEY `path_link_path_membership_fk` (`path_id`),
  CONSTRAINT `links_link_path_membership_fk` FOREIGN KEY (`link_id`) REFERENCES `link` (`link_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `path_link_path_membership_fk` FOREIGN KEY (`path_id`) REFERENCES `path` (`path_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `link_path_membership`
--

LOCK TABLES `link_path_membership` WRITE;
/*!40000 ALTER TABLE `link_path_membership` DISABLE KEYS */;
/*!40000 ALTER TABLE `link_path_membership` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `maintenance`
--

DROP TABLE IF EXISTS `maintenance`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `maintenance` (
  `maintenance_id` int(11) NOT NULL AUTO_INCREMENT,
  `description` varchar(255) DEFAULT NULL,
  `start_epoch` int(11) DEFAULT NULL,
  `end_epoch` int(11) DEFAULT '-1',
  PRIMARY KEY (`maintenance_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `maintenance`
--

LOCK TABLES `maintenance` WRITE;
/*!40000 ALTER TABLE `maintenance` DISABLE KEYS */;
/*!40000 ALTER TABLE `maintenance` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `network`
--

DROP TABLE IF EXISTS `network`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `network` (
  `network_id` int(10) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `longitude` double NOT NULL,
  `latitude` double NOT NULL,
  `is_local` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`network_id`),
  UNIQUE KEY `network_idx` (`name`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;
INSERT INTO `network` (`network_id`,`name`,`longitude`,`latitude`,`is_local`) VALUES (1,'oess',0,0,1);

--
-- Table structure for table `node`
--
INSERT INTO `network` (`network_id`,`name`,`longitude`,`latitude`,`is_local`) VALUES (1,'oess',0,0,1);

DROP TABLE IF EXISTS `node`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `node` (
  `node_id` int(10) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `longitude` double NOT NULL,
  `latitude` double NOT NULL,
  `operational_state` enum('unknown','up','down') NOT NULL DEFAULT 'unknown',
  `operational_state_mpls` enum('unknown','up','down') NOT NULL DEFAULT 'unknown',
  `network_id` int(10) NOT NULL,
  `vlan_tag_range` varchar(255) NOT NULL DEFAULT '1-4095',
  `default_forward` varchar(255) DEFAULT '1',
  `default_drop` varchar(255) DEFAULT '1',
  `max_flows` int(11) DEFAULT '4000',
  `tx_delay_ms` int(11) DEFAULT '0',
  `send_barrier_bulk` tinyint(1) DEFAULT '1',
  `max_static_mac_flows` int(10) DEFAULT '0',
  `in_maint` enum('yes','no') NOT NULL DEFAULT 'no',
  `pending_diff` int(1) DEFAULT '0',
  `short_name` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`node_id`),
  UNIQUE KEY `node_idx` (`name`),
  KEY `network_node_fk` (`network_id`),
  CONSTRAINT `network_node_fk` FOREIGN KEY (`network_id`) REFERENCES `network` (`network_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `node`
--

LOCK TABLES `node` WRITE;
/*!40000 ALTER TABLE `node` DISABLE KEYS */;
/*!40000 ALTER TABLE `node` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `node_instantiation`
--

DROP TABLE IF EXISTS `node_instantiation`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `node_instantiation` (
  `node_id` int(10) NOT NULL,
  `end_epoch` int(10) NOT NULL,
  `start_epoch` int(10) NOT NULL,
  `admin_state` enum('planned','available','active','maintenance','decom') NOT NULL DEFAULT 'planned',
  `dpid` varchar(40) NOT NULL,
  `openflow` int(1) DEFAULT '1',
  `mpls` int(1) DEFAULT '0',
  `vendor` varchar(255) DEFAULT NULL,
  `model` varchar(255) DEFAULT NULL,
  `sw_version` varchar(255) DEFAULT NULL,
  `mgmt_addr` varchar(255) DEFAULT NULL,
  `loopback_address` varchar(255) DEFAULT NULL,
  `tcp_port` int(6) DEFAULT '830',
  `controller` enum('openflow','netconf','nso') NOT NULL DEFAULT 'nso',
  PRIMARY KEY (`node_id`,`end_epoch`),
  UNIQUE KEY `node_instantiation_idx` (`end_epoch`,`dpid`),
  CONSTRAINT `node_node_instantiation_fk` FOREIGN KEY (`node_id`) REFERENCES `node` (`node_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `node_instantiation`
--

LOCK TABLES `node_instantiation` WRITE;
/*!40000 ALTER TABLE `node_instantiation` DISABLE KEYS */;
/*!40000 ALTER TABLE `node_instantiation` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `node_maintenance`
--

DROP TABLE IF EXISTS `node_maintenance`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `node_maintenance` (
  `node_maintenance_id` int(11) NOT NULL AUTO_INCREMENT,
  `node_id` int(11) NOT NULL,
  `maintenance_id` int(11) NOT NULL,
  PRIMARY KEY (`node_maintenance_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `node_maintenance`
--

LOCK TABLES `node_maintenance` WRITE;
/*!40000 ALTER TABLE `node_maintenance` DISABLE KEYS */;
/*!40000 ALTER TABLE `node_maintenance` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `oess_version`
--

DROP TABLE IF EXISTS `oess_version`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `oess_version` (
  `version` varchar(32) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `oess_version`
--

LOCK TABLES `oess_version` WRITE;
/*!40000 ALTER TABLE `oess_version` DISABLE KEYS */;
INSERT INTO `oess_version` VALUES ('2.0.11');
/*!40000 ALTER TABLE `oess_version` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `path`
--

DROP TABLE IF EXISTS `path`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `path` (
  `path_id` int(10) NOT NULL AUTO_INCREMENT,
  `path_type` enum('primary','backup','tertiary') NOT NULL DEFAULT 'primary',
  `circuit_id` int(10) NOT NULL,
  `path_state` enum('active','available','deploying','decom') NOT NULL DEFAULT 'active',
  `mpls_path_type` enum('strict','loose','none') NOT NULL DEFAULT 'none',
  PRIMARY KEY (`path_id`),
  UNIQUE KEY `path_idx` (`path_type`,`circuit_id`),
  KEY `circuit_path_fk` (`circuit_id`),
  CONSTRAINT `circuit_path_fk` FOREIGN KEY (`circuit_id`) REFERENCES `circuit` (`circuit_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `path`
--

LOCK TABLES `path` WRITE;
/*!40000 ALTER TABLE `path` DISABLE KEYS */;
/*!40000 ALTER TABLE `path` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `path_instantiation`
--

DROP TABLE IF EXISTS `path_instantiation`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `path_instantiation` (
  `path_instantiation_id` int(11) NOT NULL AUTO_INCREMENT,
  `path_id` int(10) NOT NULL,
  `end_epoch` int(10) NOT NULL,
  `path_state` enum('active','available','deploying','decom') NOT NULL DEFAULT 'active',
  `start_epoch` int(10) NOT NULL,
  PRIMARY KEY (`path_instantiation_id`),
  KEY `end_epoch_path` (`path_id`,`end_epoch`),
  CONSTRAINT `path_path_instantiaiton_fk` FOREIGN KEY (`path_id`) REFERENCES `path` (`path_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `path_instantiation`
--

LOCK TABLES `path_instantiation` WRITE;
/*!40000 ALTER TABLE `path_instantiation` DISABLE KEYS */;
/*!40000 ALTER TABLE `path_instantiation` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `path_instantiation_vlan_ids`
--

DROP TABLE IF EXISTS `path_instantiation_vlan_ids`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `path_instantiation_vlan_ids` (
  `path_instantiation_id` int(11) NOT NULL,
  `node_id` int(11) NOT NULL,
  `internal_vlan_id` int(11) NOT NULL,
  KEY `path_instantiation_id` (`path_instantiation_id`),
  KEY `node_id` (`node_id`),
  CONSTRAINT `path_instantiation_vlan_ids_ibfk_1` FOREIGN KEY (`path_instantiation_id`) REFERENCES `path_instantiation` (`path_instantiation_id`),
  CONSTRAINT `path_instantiation_vlan_ids_ibfk_2` FOREIGN KEY (`node_id`) REFERENCES `node` (`node_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `path_instantiation_vlan_ids`
--

LOCK TABLES `path_instantiation_vlan_ids` WRITE;
/*!40000 ALTER TABLE `path_instantiation_vlan_ids` DISABLE KEYS */;
/*!40000 ALTER TABLE `path_instantiation_vlan_ids` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `remote_auth`
--

DROP TABLE IF EXISTS `remote_auth`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `remote_auth` (
  `auth_id` int(10) NOT NULL AUTO_INCREMENT,
  `auth_name` varchar(255) NOT NULL,
  `user_id` int(10) NOT NULL,
  PRIMARY KEY (`auth_id`),
  UNIQUE KEY `remote_auth_idx` (`auth_name`),
  KEY `user_auth_values_fk` (`user_id`),
  CONSTRAINT `user_auth_values_fk` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;
INSERT INTO `remote_auth` (`auth_name`,`user_id`) VALUES ('admin',1);
--
-- Dumping data for table `remote_auth`
--

LOCK TABLES `remote_auth` WRITE;
/*!40000 ALTER TABLE `remote_auth` DISABLE KEYS */;
/*!40000 ALTER TABLE `remote_auth` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `scheduled_action`
--

DROP TABLE IF EXISTS `scheduled_action`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `scheduled_action` (
  `scheduled_action_id` int(10) NOT NULL AUTO_INCREMENT,
  `user_id` int(10) NOT NULL,
  `workgroup_id` int(10) NOT NULL,
  `circuit_id` int(10) NOT NULL,
  `registration_epoch` int(10) NOT NULL,
  `activation_epoch` int(10) NOT NULL,
  `completion_epoch` int(10) NOT NULL,
  `circuit_layout` longblob NOT NULL,
  PRIMARY KEY (`scheduled_action_id`),
  KEY `user_scheduled_actions_fk` (`user_id`),
  KEY `workgroups_scheduled_actions_fk` (`workgroup_id`),
  KEY `circuit_scheduled_actions_fk` (`circuit_id`),
  CONSTRAINT `circuit_scheduled_actions_fk` FOREIGN KEY (`circuit_id`) REFERENCES `circuit` (`circuit_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `user_scheduled_actions_fk` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `workgroups_scheduled_actions_fk` FOREIGN KEY (`workgroup_id`) REFERENCES `workgroup` (`workgroup_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `scheduled_action`
--

LOCK TABLES `scheduled_action` WRITE;
/*!40000 ALTER TABLE `scheduled_action` DISABLE KEYS */;
/*!40000 ALTER TABLE `scheduled_action` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `schema_version`
--

DROP TABLE IF EXISTS `schema_version`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `schema_version` (
  `version` varchar(100) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `schema_version`
--

LOCK TABLES `schema_version` WRITE;
/*!40000 ALTER TABLE `schema_version` DISABLE KEYS */;
/*!40000 ALTER TABLE `schema_version` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `urn`
--

DROP TABLE IF EXISTS `urn`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `urn` (
  `urn_id` int(10) NOT NULL AUTO_INCREMENT,
  `urn` varchar(255) NOT NULL,
  `interface_id` int(10) DEFAULT NULL,
  `last_update` int(10) NOT NULL,
  `vlan_tag_range` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`urn_id`),
  UNIQUE KEY `urn_idx` (`urn`),
  KEY `urn_interface_fk` (`interface_id`),
  CONSTRAINT `urn_interface_fk` FOREIGN KEY (`interface_id`) REFERENCES `interface` (`interface_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `urn`
--

LOCK TABLES `urn` WRITE;
/*!40000 ALTER TABLE `urn` DISABLE KEYS */;
/*!40000 ALTER TABLE `urn` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user`
--

DROP TABLE IF EXISTS `user`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user` (
  `user_id` int(10) NOT NULL AUTO_INCREMENT,
  `email` varchar(128) NOT NULL,
  `given_names` varchar(60) NOT NULL,
  `family_name` varchar(60) NOT NULL,
  `is_admin` int(10) NOT NULL DEFAULT '0',
  `status` enum('active','decom') NOT NULL DEFAULT 'active',
  PRIMARY KEY (`user_id`),
  KEY `user_idx` (`email`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;
INSERT INTO `user` (`user_id`,`email`,`given_names`,`family_name`,`is_admin`,`status`) VALUES (1,'admin@localhost','admin','admin',1,'active');

--
-- Table structure for table `user_entity_membership`
--

DROP TABLE IF EXISTS `user_entity_membership`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_entity_membership` (
  `user_id` int(11) NOT NULL,
  `entity_id` int(11) NOT NULL,
  KEY `entity` (`entity_id`),
  KEY `user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;
INSERT INTO `user_entity_membership` (`user_id`,`entity_id`) VALUES (1,1);

--
-- Table structure for table `user_workgroup_membership`
--

DROP TABLE IF EXISTS `user_workgroup_membership`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_workgroup_membership` (
  `workgroup_id` int(10) NOT NULL,
  `user_id` int(10) NOT NULL,
  `role` enum('admin','normal','read-only') NOT NULL DEFAULT 'read-only',
  PRIMARY KEY (`workgroup_id`,`user_id`),
  KEY `user_user_workgroup_membership_fk` (`user_id`),
  CONSTRAINT `user_user_workgroup_membership_fk` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `workgroups_user_workgroup_membership_fk` FOREIGN KEY (`workgroup_id`) REFERENCES `workgroup` (`workgroup_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;
INSERT INTO `user_workgroup_membership` (`workgroup_id`,`user_id`,`role`) VALUES (1,1,'admin');

--
-- Table structure for table `vrf`
--

DROP TABLE IF EXISTS `vrf`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `vrf` (
  `vrf_id` int(10) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `description` varchar(255) NOT NULL,
  `workgroup_id` int(10) NOT NULL,
  `state` enum('active','decom') DEFAULT NULL,
  `created` int(10) NOT NULL,
  `created_by` int(10) NOT NULL,
  `last_modified` int(10) NOT NULL,
  `last_modified_by` int(10) NOT NULL,
  `local_asn` int(10) NOT NULL,
  PRIMARY KEY (`vrf_id`),
  KEY `workgroup_id` (`workgroup_id`),
  KEY `created_by` (`created_by`),
  KEY `last_modified_by` (`last_modified_by`),
  CONSTRAINT `vrf_ibfk_3` FOREIGN KEY (`last_modified_by`) REFERENCES `user` (`user_id`),
  CONSTRAINT `vrf_ibfk_1` FOREIGN KEY (`workgroup_id`) REFERENCES `workgroup` (`workgroup_id`),
  CONSTRAINT `vrf_ibfk_2` FOREIGN KEY (`created_by`) REFERENCES `user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `vrf`
--

LOCK TABLES `vrf` WRITE;
/*!40000 ALTER TABLE `vrf` DISABLE KEYS */;
/*!40000 ALTER TABLE `vrf` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `vrf_ep`
--

DROP TABLE IF EXISTS `vrf_ep`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `vrf_ep` (
  `vrf_ep_id` int(11) NOT NULL AUTO_INCREMENT,
  `inner_tag` int(10) DEFAULT NULL,
  `tag` int(10) DEFAULT NULL,
  `bandwidth` int(10) DEFAULT NULL,
  `vrf_id` int(10) DEFAULT NULL,
  `interface_id` int(10) NOT NULL,
  `state` enum('active','decom') DEFAULT NULL,
  `unit` int(11) NOT NULL,
  `mtu` int(11) NOT NULL DEFAULT 9000,
  PRIMARY KEY (`vrf_ep_id`),
  KEY `vrf_id` (`vrf_id`),
  KEY `interface_id` (`interface_id`),
  CONSTRAINT `vrf_ep_ibfk_2` FOREIGN KEY (`interface_id`) REFERENCES `interface` (`interface_id`),
  CONSTRAINT `vrf_ep_ibfk_1` FOREIGN KEY (`vrf_id`) REFERENCES `vrf` (`vrf_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `vrf_ep`
--

LOCK TABLES `vrf_ep` WRITE;
/*!40000 ALTER TABLE `vrf_ep` DISABLE KEYS */;
/*!40000 ALTER TABLE `vrf_ep` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `vrf_ep_peer`
--

DROP TABLE IF EXISTS `vrf_ep_peer`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `vrf_ep_peer` (
  `vrf_ep_peer_id` int(10) NOT NULL AUTO_INCREMENT,
  `peer_ip` varchar(255) NOT NULL,
  `peer_asn` int(10) unsigned DEFAULT NULL,
  `vrf_ep_id` int(11) DEFAULT NULL,
  `operational_state` int(1) DEFAULT NULL,
  `state` enum('active','decom') DEFAULT NULL,
  `local_ip` varchar(255) DEFAULT NULL,
  `ip_version` ENUM('ipv4','ipv6') DEFAULT NULL,
  `md5_key` varchar(255) DEFAULT NULL,
  `circuit_ep_id` int(11) DEFAULT NULL,
  `bfd` int(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`vrf_ep_peer_id`),
  KEY `vrf_ep_id` (`vrf_ep_id`),
  KEY `vrf_ep_peer_ibfk_2` (`circuit_ep_id`),
  CONSTRAINT `vrf_ep_peer_ibfk_1` FOREIGN KEY (`vrf_ep_id`) REFERENCES `vrf_ep` (`vrf_ep_id`),
  CONSTRAINT `vrf_ep_peer_ibfk_2` FOREIGN KEY (`circuit_ep_id`) REFERENCES `circuit_edge_interface_membership` (`circuit_edge_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `vrf_ep_peer`
--

LOCK TABLES `vrf_ep_peer` WRITE;
/*!40000 ALTER TABLE `vrf_ep_peer` DISABLE KEYS */;
/*!40000 ALTER TABLE `vrf_ep_peer` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `workgroup`
--

DROP TABLE IF EXISTS `workgroup`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `workgroup` (
  `workgroup_id` int(10) NOT NULL AUTO_INCREMENT,
  `description` varchar(255) NOT NULL,
  `name` varchar(255) NOT NULL,
  `external_id` varchar(255) DEFAULT NULL,
  `type` enum('demo','normal','admin') NOT NULL DEFAULT 'normal',
  `max_mac_address_per_end` int(10) DEFAULT '10',
  `max_circuits` int(10) DEFAULT '20',
  `max_circuit_endpoints` int(10) DEFAULT '10',
  `status` enum('active','decom') NOT NULL DEFAULT 'active',
  PRIMARY KEY (`workgroup_id`),
  UNIQUE KEY `workgroups_idx` (`name`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;
INSERT INTO `workgroup` (`workgroup_id`,`description`,`name`,`type`) VALUES (1,'admin','admin','admin');

--
-- Dumping data for table `workgroup`
--

LOCK TABLES `workgroup` WRITE;
/*!40000 ALTER TABLE `workgroup` DISABLE KEYS */;
/*!40000 ALTER TABLE `workgroup` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `workgroup_node_membership`
--

DROP TABLE IF EXISTS `workgroup_node_membership`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `workgroup_node_membership` (
  `workgroup_id` int(10) NOT NULL,
  `node_id` int(10) NOT NULL,
  PRIMARY KEY (`workgroup_id`,`node_id`),
  KEY `node_workgroup_host_membership_fk` (`node_id`),
  CONSTRAINT `node_workgroup_host_membership_fk` FOREIGN KEY (`node_id`) REFERENCES `node` (`node_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `workgroups_workgroup_host_membership_fk` FOREIGN KEY (`workgroup_id`) REFERENCES `workgroup` (`workgroup_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `workgroup_node_membership`
--

/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2018-05-17 16:55:19
