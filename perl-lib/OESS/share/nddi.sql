-- MySQL dump 10.13  Distrib 5.1.52, for redhat-linux-gnu (x86_64)
--
-- Host: localhost    Database: oess
-- ------------------------------------------------------
-- Server version	5.1.52

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
  `circuit_state` enum('reserved','scheduled','deploying','active','decom') NOT NULL DEFAULT 'scheduled',    
  `restore_to_primary` int(10) DEFAULT '0',
  `static_mac` tinyint(1) DEFAULT '0',
  PRIMARY KEY (`circuit_id`),
  UNIQUE KEY `circuit_idx` (`name`),
  KEY `workgroup_id` (`workgroup_id`),
  CONSTRAINT `circuit_ibfk_1` FOREIGN KEY (`workgroup_id`) REFERENCES `workgroup` (`workgroup_id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = utf8 */;

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
  `circuit_edge_id` int(10) NOT NULL AUTO_INCREMENT,
  PRIMARY KEY (`circuit_edge_id`),
  UNIQUE KEY `interface_id` (`interface_id`,`circuit_id`,`end_epoch`,`extern_vlan_id`),
  KEY `circuit_circuit_interface_membership_fk` (`circuit_id`),
  CONSTRAINT `circuit_edge_interface_membership_ibfk_1` FOREIGN KEY (`interface_id`) REFERENCES `interface` (`interface_id`),
  CONSTRAINT `circuit_edge_interface_membership_ibfk_2` FOREIGN KEY (`circuit_id`) REFERENCES `circuit` (`circuit_id`)
) ENGINE=InnoDB AUTO_INCREMENT=81 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

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
  `circuit_state` enum('reserved','scheduled','deploying','active','decom') NOT NULL DEFAULT 'scheduled',
  `modified_by_user_id` int(10) NOT NULL,
  `loop_node` int(11) DEFAULT NULL,
  PRIMARY KEY (`end_epoch`,`circuit_id`),
  KEY `user_circuit_instantiaiton_fk` (`modified_by_user_id`),
  KEY `circuit_circuit_instantiaiton_fk` (`circuit_id`),
  CONSTRAINT `circuit_circuit_instantiaiton_fk` FOREIGN KEY (`circuit_id`) REFERENCES `circuit` (`circuit_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `user_circuit_instantiaiton_fk` FOREIGN KEY (`modified_by_user_id`) REFERENCES `user` (`user_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = utf8 */;

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
  `operational_state` enum('unknown','up','down') NOT NULL DEFAULT 'unknown',
  `role` enum('unknown','trunk','customer') NOT NULL DEFAULT 'unknown',
  `node_id` int(10) NOT NULL,
  `vlan_tag_range` varchar(255) DEFAULT '-1,1-4095',
  `workgroup_id` int(10) DEFAULT NULL,
  PRIMARY KEY (`interface_id`),
  UNIQUE KEY `node_id_name_idx` (`node_id`,`name`),
  UNIQUE KEY `node_port_idx` (`node_id`,`port_number`),
  KEY `node_interface_fk` (`node_id`),
  CONSTRAINT `interface_ibfk_1` FOREIGN KEY (`workgroup_id`) REFERENCES `workgroup` (`workgroup_id`),
  CONSTRAINT `node_interface_fk` FOREIGN KEY (`node_id`) REFERENCES `node` (`node_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

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
  PRIMARY KEY (`interface_acl_id`),
  KEY `workgroup_id` (`workgroup_id`),
  KEY `interface_id` (`interface_id`),
  CONSTRAINT `interface_acl_ibfk_1` FOREIGN KEY (`interface_id`) REFERENCES `interface` (`interface_id`),
  CONSTRAINT `interface_acl_ibfk_2` FOREIGN KEY (`workgroup_id`) REFERENCES `workgroup` (`workgroup_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

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
-- Table structure for table `link`
--

DROP TABLE IF EXISTS `link`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `link` (
  `link_id` int(10) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `remote_urn` varchar(256) DEFAULT NULL,
  `status` enum('up','down','unknown') DEFAULT 'up',
  `metric` int(11) DEFAULT '1',
  `fv_status` enum('up','down','unknown') NOT NULL DEFAULT 'unknown',
  `vlan_tag_range` varchar(255) DEFAULT NULL,
  `in_maint` enum('yes','no') NOT NULL DEFAULT 'no',
  PRIMARY KEY (`link_id`),
  UNIQUE KEY `links_idx` (`name`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

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
  PRIMARY KEY (`link_id`,`end_epoch`),
  KEY `interface_link_instantiation_fk` (`interface_a_id`),
  KEY `interface_link_instantiation_fk_1` (`interface_z_id`),
  CONSTRAINT `interface_link_instantiation_fk` FOREIGN KEY (`interface_a_id`) REFERENCES `interface` (`interface_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `interface_link_instantiation_fk_1` FOREIGN KEY (`interface_z_id`) REFERENCES `interface` (`interface_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `links_link_instantiation_fk` FOREIGN KEY (`link_id`) REFERENCES `link` (`link_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

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

--
-- Table structure for table `node`
--

DROP TABLE IF EXISTS `node`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `node` (
  `node_id` int(10) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `longitude` double NOT NULL,
  `latitude` double NOT NULL,
  `operational_state` enum('unknown','up','down') NOT NULL DEFAULT 'unknown',
  `network_id` int(10) NOT NULL,
  `vlan_tag_range` varchar(255) NOT NULL DEFAULT '1-4095',
  `default_forward` varchar(255) DEFAULT '1',
  `default_drop` varchar(255) DEFAULT '1',
  `max_flows` int(11) DEFAULT '4000',
  `tx_delay_ms` int(11) DEFAULT '0',
  `send_barrier_bulk` tinyint(1) DEFAULT '1',
  `max_static_mac_flows` int(10) DEFAULT '0',
  `in_maint` enum('yes','no') NOT NULL DEFAULT 'no', 
  PRIMARY KEY (`node_id`),
  UNIQUE KEY `node_idx` (`name`),
  KEY `network_node_fk` (`network_id`),
  CONSTRAINT `network_node_fk` FOREIGN KEY (`network_id`) REFERENCES `network` (`network_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

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
  `management_addr_ipv4` int(10) unsigned NOT NULL,
  `admin_state` enum('planned','available','active','maintenance','decom') NOT NULL DEFAULT 'planned',
  `dpid` varchar(40) NOT NULL,
  PRIMARY KEY (`node_id`,`end_epoch`),
  UNIQUE KEY `node_instantiation_idx` (`end_epoch`,`dpid`),
  KEY `node_instantiation_idx1` (`end_epoch`,`management_addr_ipv4`),
  CONSTRAINT `node_node_instantiation_fk` FOREIGN KEY (`node_id`) REFERENCES `node` (`node_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `path`
--

DROP TABLE IF EXISTS `path`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `path` (
  `path_id` int(10) NOT NULL AUTO_INCREMENT,
  `path_type` enum('primary','backup') NOT NULL DEFAULT 'primary',
  `circuit_id` int(10) NOT NULL,
  `path_state` enum('active','available','deploying') NOT NULL DEFAULT 'active',      
  PRIMARY KEY (`path_id`),
  UNIQUE KEY `path_idx` (`path_type`,`circuit_id`),
  KEY `circuit_path_fk` (`circuit_id`),
  CONSTRAINT `circuit_path_fk` FOREIGN KEY (`circuit_id`) REFERENCES `circuit` (`circuit_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

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
  `path_state` enum('active','available','deploying') NOT NULL DEFAULT 'active',
  `start_epoch` int(10) NOT NULL,
  PRIMARY KEY (`path_instantiation_id`),
  KEY `end_epoch_path` (`path_id`,`end_epoch`),
  CONSTRAINT `path_path_instantiaiton_fk` FOREIGN KEY (`path_id`) REFERENCES `path` (`path_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB AUTO_INCREMENT=13 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

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
-- Table structure for table `schema_version`
--

DROP TABLE IF EXISTS `schema_version`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `schema_version` (
  `version` varchar(100) NOT NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

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
  `type` enum('normal','read-only') NOT NULL DEFAULT 'normal',
  `status` enum('active','decom') NOT NULL DEFAULT 'active',
  PRIMARY KEY (`user_id`),
  KEY `user_idx` (`email`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user`
--

LOCK TABLES `user` WRITE;
/*!40000 ALTER TABLE `user` DISABLE KEYS */;
INSERT INTO `user` VALUES (1,'system@localhost','system','system',0,'normal','active');
/*!40000 ALTER TABLE `user` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user_workgroup_membership`
--

DROP TABLE IF EXISTS `user_workgroup_membership`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_workgroup_membership` (
  `workgroup_id` int(10) NOT NULL,
  `user_id` int(10) NOT NULL,
  PRIMARY KEY (`workgroup_id`,`user_id`),
  KEY `user_user_workgroup_membership_fk` (`user_id`),
  CONSTRAINT `user_user_workgroup_membership_fk` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `workgroups_user_workgroup_membership_fk` FOREIGN KEY (`workgroup_id`) REFERENCES `workgroup` (`workgroup_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

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
  `type` varchar(20) DEFAULT 'normal',
  `max_mac_address_per_end` int(10) DEFAULT '10',
  `max_circuits` int(10) DEFAULT '20',
  `max_circuit_endpoints` int(10) DEFAULT '10',
  `status` enum('active','decom') NOT NULL DEFAULT 'active',
  PRIMARY KEY (`workgroup_id`),
  UNIQUE KEY `workgroups_idx` (`name`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

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
-- Table structure for table `edge_interface_move_maintenance_circuit_membership`
--

DROP TABLE IF EXISTS `edge_interface_move_maintenance_circuit_membership`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `edge_interface_move_maintenance_circuit_membership` (
  `maintenance_id` int(10) NOT NULL,
  `circuit_id` int(10) NOT NULL,
  KEY `maintenance_id` (`maintenance_id`),
  KEY `circuit_id` (`circuit_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `maintenance`
--

DROP TABLE IF EXISTS `maintenance`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `maintenance` (
  `maintenance_id` int(10) NOT NULL AUTO_INCREMENT,
  `description` varchar(255),
  `start_epoch` int(10),
  `end_epoch` int(10) DEFAULT -1,
  PRIMARY KEY (`maintenance_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `node_maintenance`
--

DROP TABLE IF EXISTS `node_maintenance`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `node_maintenance` (
  `node_maintenance_id` int(10) NOT NULL AUTO_INCREMENT,
  `node_id` int(10) NOT NULL,
  `maintenance_id` int(10) NOT NULL,
  PRIMARY KEY (`node_maintenance_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `node_maintenance`
--

DROP TABLE IF EXISTS `link_maintenance`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `link_maintenance` (
  `link_maintenance_id` int(10) NOT NULL AUTO_INCREMENT,
  `link_id` int(10) NOT NULL,
  `maintenance_id` int(10) NOT NULL,
  PRIMARY KEY (`link_maintenance_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

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
INSERT INTO `oess_version` VALUES ('1.1.7');
/*!40000 ALTER TABLE `oess_version` ENABLE KEYS */;
UNLOCK TABLES;

/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;



/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2011-12-06 20:37:21
