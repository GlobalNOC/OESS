-- MySQL dump 10.14  Distrib 5.5.68-MariaDB, for Linux (x86_64)
--
-- Host: localhost    Database: oess
-- ------------------------------------------------------
-- Server version	5.5.68-MariaDB

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
  `mtu` int(11) NOT NULL DEFAULT '9000',
  PRIMARY KEY (`circuit_edge_id`),
  UNIQUE KEY `interface_id` (`interface_id`,`circuit_id`,`end_epoch`,`extern_vlan_id`),
  KEY `circuit_circuit_interface_membership_fk` (`circuit_id`),
  CONSTRAINT `circuit_edge_interface_membership_ibfk_1` FOREIGN KEY (`interface_id`) REFERENCES `interface` (`interface_id`),
  CONSTRAINT `circuit_edge_interface_membership_ibfk_2` FOREIGN KEY (`circuit_id`) REFERENCES `circuit` (`circuit_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `cloud_connection_vrf_ep`
--

LOCK TABLES `cloud_connection_vrf_ep` WRITE;
/*!40000 ALTER TABLE `cloud_connection_vrf_ep` DISABLE KEYS */;
/*!40000 ALTER TABLE `cloud_connection_vrf_ep` ENABLE KEYS */;
UNLOCK TABLES;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `command`
--

LOCK TABLES `command` WRITE;
/*!40000 ALTER TABLE `command` DISABLE KEYS */;
/*!40000 ALTER TABLE `command` ENABLE KEYS */;
UNLOCK TABLES;

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
-- Table structure for table `entity`
--

DROP TABLE IF EXISTS `entity`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `entity` (
  `entity_id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) DEFAULT NULL,
  `description` text,
  `logo_url` varchar(255) DEFAULT NULL,
  `url` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`entity_id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `entity`
--

LOCK TABLES `entity` WRITE;
/*!40000 ALTER TABLE `entity` DISABLE KEYS */;
INSERT INTO `entity` VALUES (1,'Root','Default Root Entity',NULL,NULL);
/*!40000 ALTER TABLE `entity` ENABLE KEYS */;
UNLOCK TABLES;

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
-- Dumping data for table `entity_hierarchy`
--

LOCK TABLES `entity_hierarchy` WRITE;
/*!40000 ALTER TABLE `entity_hierarchy` DISABLE KEYS */;
/*!40000 ALTER TABLE `entity_hierarchy` ENABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=207 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `interface`
--

LOCK TABLES `interface` WRITE;
/*!40000 ALTER TABLE `interface` DISABLE KEYS */;
INSERT INTO `interface` VALUES (1,'lc-0/0/0',NULL,'lc-0/0/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(2,'pfe-0/0/0',NULL,'pfe-0/0/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(3,'pfh-0/0/0',NULL,'pfh-0/0/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(4,'xe-0/0/0',NULL,'xe-0/0/0',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(5,'xe-0/0/1',NULL,'xe-0/0/1',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(6,'xe-0/0/2',NULL,'xe-0/0/2',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(7,'xe-0/0/3',NULL,'xe-0/0/3',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(8,'et-0/1/0',NULL,'sr10 to ixia slot 6 port 1',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(9,'lc-0/2/0',NULL,'lc-0/2/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(10,'pfe-0/2/0',NULL,'pfe-0/2/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(11,'xe-0/2/0',NULL,'xe-0/2/0',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(12,'xe-0/2/1',NULL,'xe-0/2/1',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(13,'xe-0/2/2',NULL,'xe-0/2/2',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(14,'xe-0/2/3',NULL,'xe-0/2/3',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(15,'et-0/3/0',NULL,'lr4 to cisco',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(16,'lc-1/0/0',NULL,'lc-1/0/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(17,'pfe-1/0/0',NULL,'pfe-1/0/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(18,'pfh-1/0/0',NULL,'pfh-1/0/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(19,'xe-1/0/0',NULL,'xe-1/0/0',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(20,'xe-1/0/1',NULL,'xe-1/0/1',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(21,'xe-1/0/2',NULL,'xe-1/0/2',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(22,'xe-1/0/3',NULL,'xe-1/0/3',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(23,'et-1/1/0',NULL,'sr10 to ixia slot 6 port 2',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(24,'lc-1/2/0',NULL,'lc-1/2/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(25,'pfe-1/2/0',NULL,'pfe-1/2/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(26,'xe-1/2/0',NULL,'xe-1/2/0',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(27,'xe-1/2/1',NULL,'xe-1/2/1',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(28,'xe-1/2/2',NULL,'xe-1/2/2',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(29,'xe-1/2/3',NULL,'xe-1/2/3',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(30,'et-1/3/0',NULL,'lr4 to cisco',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(31,'lc-7/0/0',NULL,'lc-7/0/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(32,'pfe-7/0/0',NULL,'pfe-7/0/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(33,'pfh-7/0/0',NULL,'pfh-7/0/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(34,'xe-7/0/0',NULL,'glimmerglass-1 7/7',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(35,'xe-7/0/1',NULL,'glimmerglass-3 3/3',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(36,'xe-7/0/2',NULL,'glimmerglass-2, 7/7',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(37,'xe-7/0/3',NULL,'test to 03.04-5200',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(38,'lc-7/1/0',NULL,'lc-7/1/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(39,'pfe-7/1/0',NULL,'pfe-7/1/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(40,'xe-7/1/0',NULL,'core3 34/1',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(41,'xe-7/1/1',NULL,'xe-7/1/1',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(42,'xe-7/1/2',NULL,'xe-7/1/2',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(43,'xe-7/1/3',NULL,'xe-7/1/3',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(44,'lc-7/2/0',NULL,'lc-7/2/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(45,'pfe-7/2/0',NULL,'pfe-7/2/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(46,'xe-7/2/0',NULL,'8201-1 Te0/0/0/30/1',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(47,'xe-7/2/1',NULL,'xe-7/2/1',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(48,'xe-7/2/2',NULL,'xe-7/2/2',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(49,'xe-7/2/3',NULL,'xe-7/2/3',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(50,'lc-7/3/0',NULL,'lc-7/3/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(51,'pfe-7/3/0',NULL,'pfe-7/3/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(52,'xe-7/3/0',NULL,'ncs-55a1-2 (AC) Te0/0/0/0',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(53,'xe-7/3/1',NULL,'xe-7/3/1',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(54,'xe-7/3/2',NULL,'[ae0] SMN-RTSW EX4600 xe-0/0/22',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(55,'xe-7/3/3',NULL,'[ae0] SMN-RTSW EX4600 xe-0/0/23',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(56,'ge-11/0/0',NULL,'ge-11/0/0',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(57,'lc-11/0/0',NULL,'lc-11/0/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(58,'pfe-11/0/0',NULL,'pfe-11/0/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(59,'pfh-11/0/0',NULL,'pfh-11/0/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(60,'ge-11/0/1',NULL,'ge-11/0/1',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(61,'ge-11/0/2',NULL,'ge-11/0/2',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(62,'ge-11/0/3',NULL,'ge-11/0/3',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(63,'ge-11/0/4',NULL,'ge-11/0/4',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(64,'ge-11/0/5',NULL,'ge-11/0/5',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(65,'ge-11/0/6',NULL,'ge-11/0/6',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(66,'ge-11/0/7',NULL,'ge-11/0/7',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(67,'ge-11/0/8',NULL,'ge-11/0/8',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(68,'ge-11/0/9',NULL,'ge-11/0/9',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(69,'ge-11/1/0',NULL,'ge-11/1/0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(70,'ge-11/1/1',NULL,'ge-11/1/1',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(71,'ge-11/1/2',NULL,'ge-11/1/2',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(72,'ge-11/1/3',NULL,'ge-11/1/3',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(73,'ge-11/1/4',NULL,'ge-11/1/4',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(74,'ge-11/1/5',NULL,'ge-11/1/5',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(75,'ge-11/1/6',NULL,'ge-11/1/6',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(76,'ge-11/1/7',NULL,'ge-11/1/7',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(77,'ge-11/1/8',NULL,'ge-11/1/8',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(78,'ge-11/1/9',NULL,'ge-11/1/9',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(79,'ae0',NULL,'EX4600 SMN-RTSW2 xe-0/0/22 & xe-0/0/22',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(80,'cbp0',NULL,'cbp0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(81,'demux0',NULL,'demux0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(82,'dsc',NULL,'dsc',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(83,'em0',NULL,'em0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(84,'em1',NULL,'em1',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(85,'esi',NULL,'esi',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(86,'fxp0',NULL,'fxp0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(87,'gre',NULL,'gre',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(88,'ipip',NULL,'ipip',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(89,'irb',NULL,'irb',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(90,'jsrv',NULL,'jsrv',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(91,'lo0',NULL,'lo0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(92,'lsi',NULL,'lsi',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(93,'mtun',NULL,'mtun',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(94,'pimd',NULL,'pimd',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(95,'pime',NULL,'pime',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(96,'pip0',NULL,'pip0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(97,'pp0',NULL,'pp0',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(98,'rbeb',NULL,'rbeb',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(99,'tap',NULL,'tap',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(100,'vtep',NULL,'vtep',NULL,NULL,'up','unknown',1,'-1','1-4095',NULL),(101,'lc-0/0/0',NULL,'lc-0/0/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(102,'pfe-0/0/0',NULL,'pfe-0/0/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(103,'pfh-0/0/0',NULL,'pfh-0/0/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(104,'xe-0/0/0',NULL,'xe-0/0/0',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(105,'xe-0/0/1',NULL,'xe-0/0/1',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(106,'xe-0/0/2',NULL,'xe-0/0/2',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(107,'xe-0/0/3',NULL,'xe-0/0/3',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(108,'et-0/1/0',NULL,'sr10 to ixia slot 6 port 1',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(109,'lc-0/2/0',NULL,'lc-0/2/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(110,'pfe-0/2/0',NULL,'pfe-0/2/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(111,'xe-0/2/0',NULL,'xe-0/2/0',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(112,'xe-0/2/1',NULL,'xe-0/2/1',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(113,'xe-0/2/2',NULL,'xe-0/2/2',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(114,'xe-0/2/3',NULL,'xe-0/2/3',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(115,'et-0/3/0',NULL,'lr4 to cisco',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(116,'lc-1/0/0',NULL,'lc-1/0/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(117,'pfe-1/0/0',NULL,'pfe-1/0/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(118,'pfh-1/0/0',NULL,'pfh-1/0/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(119,'xe-1/0/0',NULL,'xe-1/0/0',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(120,'xe-1/0/1',NULL,'xe-1/0/1',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(121,'xe-1/0/2',NULL,'xe-1/0/2',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(122,'xe-1/0/3',NULL,'xe-1/0/3',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(123,'et-1/1/0',NULL,'sr10 to ixia slot 6 port 2',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(124,'lc-1/2/0',NULL,'lc-1/2/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(125,'pfe-1/2/0',NULL,'pfe-1/2/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(126,'xe-1/2/0',NULL,'xe-1/2/0',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(127,'xe-1/2/1',NULL,'xe-1/2/1',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(128,'xe-1/2/2',NULL,'xe-1/2/2',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(129,'xe-1/2/3',NULL,'xe-1/2/3',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(130,'et-1/3/0',NULL,'lr4 to cisco',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(131,'lc-7/0/0',NULL,'lc-7/0/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(132,'pfe-7/0/0',NULL,'pfe-7/0/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(133,'pfh-7/0/0',NULL,'pfh-7/0/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(134,'xe-7/0/0',NULL,'glimmerglass-1 7/7',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(135,'xe-7/0/1',NULL,'glimmerglass-3 3/3',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(136,'xe-7/0/2',NULL,'glimmerglass-2, 7/7',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(137,'xe-7/0/3',NULL,'test to 03.04-5200',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(138,'lc-7/1/0',NULL,'lc-7/1/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(139,'pfe-7/1/0',NULL,'pfe-7/1/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(140,'xe-7/1/0',NULL,'core3 34/1',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(141,'xe-7/1/1',NULL,'xe-7/1/1',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(142,'xe-7/1/2',NULL,'xe-7/1/2',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(143,'xe-7/1/3',NULL,'xe-7/1/3',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(144,'lc-7/2/0',NULL,'lc-7/2/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(145,'pfe-7/2/0',NULL,'pfe-7/2/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(146,'xe-7/2/0',NULL,'8201-1 Te0/0/0/30/1',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(147,'xe-7/2/1',NULL,'xe-7/2/1',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(148,'xe-7/2/2',NULL,'xe-7/2/2',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(149,'xe-7/2/3',NULL,'xe-7/2/3',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(150,'lc-7/3/0',NULL,'lc-7/3/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(151,'pfe-7/3/0',NULL,'pfe-7/3/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(152,'xe-7/3/0',NULL,'ncs-55a1-2 (AC) Te0/0/0/0',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(153,'xe-7/3/1',NULL,'xe-7/3/1',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(154,'xe-7/3/2',NULL,'[ae0] SMN-RTSW EX4600 xe-0/0/22',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(155,'xe-7/3/3',NULL,'[ae0] SMN-RTSW EX4600 xe-0/0/23',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(156,'ge-11/0/0',NULL,'ge-11/0/0',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(157,'lc-11/0/0',NULL,'lc-11/0/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(158,'pfe-11/0/0',NULL,'pfe-11/0/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(159,'pfh-11/0/0',NULL,'pfh-11/0/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(160,'ge-11/0/1',NULL,'ge-11/0/1',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(161,'ge-11/0/2',NULL,'ge-11/0/2',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(162,'ge-11/0/3',NULL,'ge-11/0/3',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(163,'ge-11/0/4',NULL,'ge-11/0/4',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(164,'ge-11/0/5',NULL,'ge-11/0/5',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(165,'ge-11/0/6',NULL,'ge-11/0/6',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(166,'ge-11/0/7',NULL,'ge-11/0/7',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(167,'ge-11/0/8',NULL,'ge-11/0/8',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(168,'ge-11/0/9',NULL,'ge-11/0/9',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(169,'ge-11/1/0',NULL,'ge-11/1/0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(170,'ge-11/1/1',NULL,'ge-11/1/1',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(171,'ge-11/1/2',NULL,'ge-11/1/2',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(172,'ge-11/1/3',NULL,'ge-11/1/3',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(173,'ge-11/1/4',NULL,'ge-11/1/4',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(174,'ge-11/1/5',NULL,'ge-11/1/5',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(175,'ge-11/1/6',NULL,'ge-11/1/6',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(176,'ge-11/1/7',NULL,'ge-11/1/7',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(177,'ge-11/1/8',NULL,'ge-11/1/8',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(178,'ge-11/1/9',NULL,'ge-11/1/9',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(179,'ae0',NULL,'EX4600 SMN-RTSW2 xe-0/0/22 & xe-0/0/22',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(180,'cbp0',NULL,'cbp0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(181,'demux0',NULL,'demux0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(182,'dsc',NULL,'dsc',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(183,'em0',NULL,'em0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(184,'em1',NULL,'em1',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(185,'esi',NULL,'esi',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(186,'fxp0',NULL,'fxp0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(187,'gre',NULL,'gre',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(188,'ipip',NULL,'ipip',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(189,'irb',NULL,'irb',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(190,'jsrv',NULL,'jsrv',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(191,'lo0',NULL,'lo0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(192,'lsi',NULL,'lsi',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(193,'mtun',NULL,'mtun',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(194,'pimd',NULL,'pimd',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(195,'pime',NULL,'pime',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(196,'pip0',NULL,'pip0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(197,'pp0',NULL,'pp0',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(198,'rbeb',NULL,'rbeb',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(199,'tap',NULL,'tap',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(200,'vtep',NULL,'vtep',NULL,NULL,'up','unknown',2,'-1','1-4095',NULL),(201,'et-11/0/0',NULL,'[ae32] INTERCONNECT: LOSA2 test',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(202,'ae1',NULL,'EVPN-SVC-2',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(203,'ae32',NULL,'ae32',NULL,NULL,'down','unknown',1,'-1','1-4095',NULL),(204,'et-11/0/0',NULL,'[ae32] INTERCONNECT: LOSA2 test',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(205,'ae1',NULL,'EVPN-SVC-2',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL),(206,'ae32',NULL,'ae32',NULL,NULL,'down','unknown',2,'-1','1-4095',NULL);
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
INSERT INTO `interface_instantiation` VALUES (1,-1,'up',1631649831,10000,9000),(2,-1,'up',1631649831,10000,9000),(3,-1,'up',1631649831,10000,9000),(4,-1,'up',1631649831,10000,9000),(5,-1,'up',1631649831,10000,9000),(6,-1,'up',1631649831,10000,9000),(7,-1,'up',1631649831,10000,9000),(8,-1,'up',1631649831,10000,9000),(9,-1,'up',1631649831,10000,9000),(10,-1,'up',1631649831,10000,9000),(11,-1,'up',1631649831,10000,9000),(12,-1,'up',1631649831,10000,9000),(13,-1,'up',1631649831,10000,9000),(14,-1,'up',1631649831,10000,9000),(15,-1,'up',1631649831,10000,9000),(16,-1,'up',1631649831,10000,9000),(17,-1,'up',1631649831,10000,9000),(18,-1,'up',1631649831,10000,9000),(19,-1,'up',1631649831,10000,9000),(20,-1,'up',1631649831,10000,9000),(21,-1,'up',1631649831,10000,9000),(22,-1,'up',1631649831,10000,9000),(23,-1,'up',1631649831,10000,9000),(24,-1,'up',1631649831,10000,9000),(25,-1,'up',1631649831,10000,9000),(26,-1,'up',1631649831,10000,9000),(27,-1,'up',1631649831,10000,9000),(28,-1,'up',1631649831,10000,9000),(29,-1,'up',1631649831,10000,9000),(30,-1,'up',1631649831,10000,9000),(31,-1,'up',1631649852,800,9000),(31,1631649852,'up',1631649831,10000,9000),(32,-1,'up',1631649852,800,9000),(32,1631649852,'up',1631649831,10000,9000),(33,-1,'up',1631649852,800,9000),(33,1631649852,'up',1631649831,10000,9000),(34,-1,'up',1631649852,10000,9192),(34,1631649852,'up',1631649831,10000,9000),(35,-1,'up',1631649852,10000,9192),(35,1631649852,'up',1631649831,10000,9000),(36,-1,'up',1631649852,10000,9192),(36,1631649852,'up',1631649831,10000,9000),(37,-1,'up',1631649852,10000,9192),(37,1631649852,'up',1631649831,10000,9000),(38,-1,'up',1631649852,800,9000),(38,1631649852,'up',1631649831,10000,9000),(39,-1,'up',1631649852,800,9000),(39,1631649852,'up',1631649831,10000,9000),(40,-1,'up',1631649852,10000,9192),(40,1631649852,'up',1631649831,10000,9000),(41,-1,'up',1631649852,10000,9192),(41,1631649852,'up',1631649831,10000,9000),(42,-1,'up',1631649852,10000,1514),(42,1631649852,'up',1631649831,10000,9000),(43,-1,'up',1631649852,10000,9192),(43,1631649852,'up',1631649831,10000,9000),(44,-1,'up',1631649852,800,9000),(44,1631649852,'up',1631649831,10000,9000),(45,-1,'up',1631649852,800,9000),(45,1631649852,'up',1631649831,10000,9000),(46,-1,'up',1631649852,10000,9192),(46,1631649852,'up',1631649831,10000,9000),(47,-1,'up',1631649852,10000,9192),(47,1631649852,'up',1631649831,10000,9000),(48,-1,'up',1631649852,10000,1514),(48,1631649852,'up',1631649831,10000,9000),(49,-1,'up',1631649852,10000,1514),(49,1631649852,'up',1631649831,10000,9000),(50,-1,'up',1631649852,800,9000),(50,1631649852,'up',1631649831,10000,9000),(51,-1,'up',1631649852,800,9000),(51,1631649852,'up',1631649831,10000,9000),(52,-1,'up',1631649852,10000,9192),(52,1631649852,'up',1631649831,10000,9000),(53,-1,'up',1631649852,10000,9192),(53,1631649852,'up',1631649831,10000,9000),(54,-1,'up',1631649852,10000,9192),(54,1631649852,'up',1631649831,10000,9000),(55,-1,'up',1631649852,10000,9192),(55,1631649852,'up',1631649831,10000,9000),(56,-1,'up',1631649831,10000,9000),(57,-1,'up',1631649852,800,9000),(57,1631649852,'up',1631649831,10000,9000),(58,-1,'up',1631649852,800,9000),(58,1631649852,'up',1631649831,10000,9000),(59,-1,'up',1631649852,800,9000),(59,1631649852,'up',1631649831,10000,9000),(60,-1,'up',1631649831,10000,9000),(61,-1,'up',1631649831,10000,9000),(62,-1,'up',1631649831,10000,9000),(63,-1,'up',1631649831,10000,9000),(64,-1,'up',1631649831,10000,9000),(65,-1,'up',1631649831,10000,9000),(66,-1,'up',1631649831,10000,9000),(67,-1,'up',1631649831,10000,9000),(68,-1,'up',1631649831,10000,9000),(69,-1,'up',1631649831,10000,9000),(70,-1,'up',1631649831,10000,9000),(71,-1,'up',1631649831,10000,9000),(72,-1,'up',1631649831,10000,9000),(73,-1,'up',1631649831,10000,9000),(74,-1,'up',1631649831,10000,9000),(75,-1,'up',1631649831,10000,9000),(76,-1,'up',1631649831,10000,9000),(77,-1,'up',1631649831,10000,9000),(78,-1,'up',1631649831,10000,9000),(79,-1,'up',1631649852,20000,9192),(79,1631649852,'up',1631649831,10000,9000),(80,-1,'up',1631649852,10000,9192),(80,1631649852,'up',1631649831,10000,9000),(81,-1,'up',1631649852,10000,9192),(81,1631649852,'up',1631649831,10000,9000),(82,-1,'up',1631649852,10000,0),(82,1631649852,'up',1631649831,10000,9000),(83,-1,'up',1631649852,1000,1514),(83,1631649852,'up',1631649831,10000,9000),(84,-1,'up',1631649852,1000,1514),(84,1631649852,'up',1631649831,10000,9000),(85,-1,'up',1631649852,0,0),(85,1631649852,'up',1631649831,10000,9000),(86,-1,'up',1631649852,1000,1514),(86,1631649852,'up',1631649831,10000,9000),(87,-1,'up',1631649852,0,0),(87,1631649852,'up',1631649831,10000,9000),(88,-1,'up',1631649852,0,0),(88,1631649852,'up',1631649831,10000,9000),(89,-1,'up',1631649852,10000,1514),(89,1631649852,'up',1631649831,10000,9000),(90,-1,'up',1631649852,10000,1514),(90,1631649852,'up',1631649831,10000,9000),(91,-1,'up',1631649852,10000,0),(91,1631649852,'up',1631649831,10000,9000),(92,-1,'up',1631649852,0,0),(92,1631649852,'up',1631649831,10000,9000),(93,-1,'up',1631649852,0,0),(93,1631649852,'up',1631649831,10000,9000),(94,-1,'up',1631649852,0,0),(94,1631649852,'up',1631649831,10000,9000),(95,-1,'up',1631649852,0,0),(95,1631649852,'up',1631649831,10000,9000),(96,-1,'up',1631649852,10000,9192),(96,1631649852,'up',1631649831,10000,9000),(97,-1,'up',1631649852,10000,1532),(97,1631649852,'up',1631649831,10000,9000),(98,-1,'up',1631649852,0,0),(98,1631649852,'up',1631649831,10000,9000),(99,-1,'up',1631649852,0,0),(99,1631649852,'up',1631649831,10000,9000),(100,-1,'up',1631649852,0,0),(100,1631649852,'up',1631649831,10000,9000),(101,-1,'up',1631649832,10000,9000),(102,-1,'up',1631649832,10000,9000),(103,-1,'up',1631649832,10000,9000),(104,-1,'up',1631649832,10000,9000),(105,-1,'up',1631649832,10000,9000),(106,-1,'up',1631649832,10000,9000),(107,-1,'up',1631649832,10000,9000),(108,-1,'up',1631649832,10000,9000),(109,-1,'up',1631649832,10000,9000),(110,-1,'up',1631649832,10000,9000),(111,-1,'up',1631649832,10000,9000),(112,-1,'up',1631649832,10000,9000),(113,-1,'up',1631649832,10000,9000),(114,-1,'up',1631649832,10000,9000),(115,-1,'up',1631649832,10000,9000),(116,-1,'up',1631649832,10000,9000),(117,-1,'up',1631649832,10000,9000),(118,-1,'up',1631649832,10000,9000),(119,-1,'up',1631649832,10000,9000),(120,-1,'up',1631649832,10000,9000),(121,-1,'up',1631649832,10000,9000),(122,-1,'up',1631649832,10000,9000),(123,-1,'up',1631649832,10000,9000),(124,-1,'up',1631649832,10000,9000),(125,-1,'up',1631649832,10000,9000),(126,-1,'up',1631649832,10000,9000),(127,-1,'up',1631649832,10000,9000),(128,-1,'up',1631649832,10000,9000),(129,-1,'up',1631649832,10000,9000),(130,-1,'up',1631649832,10000,9000),(131,-1,'up',1631649852,800,9000),(131,1631649852,'up',1631649832,10000,9000),(132,-1,'up',1631649852,800,9000),(132,1631649852,'up',1631649832,10000,9000),(133,-1,'up',1631649852,800,9000),(133,1631649852,'up',1631649832,10000,9000),(134,-1,'up',1631649852,10000,9192),(134,1631649852,'up',1631649832,10000,9000),(135,-1,'up',1631649852,10000,9192),(135,1631649852,'up',1631649832,10000,9000),(136,-1,'up',1631649853,10000,9192),(136,1631649853,'up',1631649832,10000,9000),(137,-1,'up',1631649853,10000,9192),(137,1631649853,'up',1631649832,10000,9000),(138,-1,'up',1631649853,800,9000),(138,1631649853,'up',1631649832,10000,9000),(139,-1,'up',1631649853,800,9000),(139,1631649853,'up',1631649832,10000,9000),(140,-1,'up',1631649853,10000,9192),(140,1631649853,'up',1631649832,10000,9000),(141,-1,'up',1631649853,10000,9192),(141,1631649853,'up',1631649832,10000,9000),(142,-1,'up',1631649853,10000,1514),(142,1631649853,'up',1631649832,10000,9000),(143,-1,'up',1631649853,10000,9192),(143,1631649853,'up',1631649832,10000,9000),(144,-1,'up',1631649853,800,9000),(144,1631649853,'up',1631649832,10000,9000),(145,-1,'up',1631649853,800,9000),(145,1631649853,'up',1631649832,10000,9000),(146,-1,'up',1631649853,10000,9192),(146,1631649853,'up',1631649832,10000,9000),(147,-1,'up',1631649853,10000,9192),(147,1631649853,'up',1631649832,10000,9000),(148,-1,'up',1631649853,10000,1514),(148,1631649853,'up',1631649832,10000,9000),(149,-1,'up',1631649853,10000,1514),(149,1631649853,'up',1631649832,10000,9000),(150,-1,'up',1631649853,800,9000),(150,1631649853,'up',1631649832,10000,9000),(151,-1,'up',1631649853,800,9000),(151,1631649853,'up',1631649832,10000,9000),(152,-1,'up',1631649853,10000,9192),(152,1631649853,'up',1631649832,10000,9000),(153,-1,'up',1631649853,10000,9192),(153,1631649853,'up',1631649832,10000,9000),(154,-1,'up',1631649853,10000,9192),(154,1631649853,'up',1631649832,10000,9000),(155,-1,'up',1631649853,10000,9192),(155,1631649853,'up',1631649832,10000,9000),(156,-1,'up',1631649832,10000,9000),(157,-1,'up',1631649853,800,9000),(157,1631649853,'up',1631649832,10000,9000),(158,-1,'up',1631649853,800,9000),(158,1631649853,'up',1631649832,10000,9000),(159,-1,'up',1631649853,800,9000),(159,1631649853,'up',1631649832,10000,9000),(160,-1,'up',1631649832,10000,9000),(161,-1,'up',1631649832,10000,9000),(162,-1,'up',1631649832,10000,9000),(163,-1,'up',1631649832,10000,9000),(164,-1,'up',1631649832,10000,9000),(165,-1,'up',1631649832,10000,9000),(166,-1,'up',1631649832,10000,9000),(167,-1,'up',1631649832,10000,9000),(168,-1,'up',1631649832,10000,9000),(169,-1,'up',1631649832,10000,9000),(170,-1,'up',1631649832,10000,9000),(171,-1,'up',1631649832,10000,9000),(172,-1,'up',1631649832,10000,9000),(173,-1,'up',1631649832,10000,9000),(174,-1,'up',1631649832,10000,9000),(175,-1,'up',1631649832,10000,9000),(176,-1,'up',1631649832,10000,9000),(177,-1,'up',1631649832,10000,9000),(178,-1,'up',1631649832,10000,9000),(179,-1,'up',1631649853,20000,9192),(179,1631649853,'up',1631649832,10000,9000),(180,-1,'up',1631649853,10000,9192),(180,1631649853,'up',1631649832,10000,9000),(181,-1,'up',1631649853,10000,9192),(181,1631649853,'up',1631649832,10000,9000),(182,-1,'up',1631649853,10000,0),(182,1631649853,'up',1631649832,10000,9000),(183,-1,'up',1631649853,1000,1514),(183,1631649853,'up',1631649832,10000,9000),(184,-1,'up',1631649853,1000,1514),(184,1631649853,'up',1631649832,10000,9000),(185,-1,'up',1631649853,0,0),(185,1631649853,'up',1631649832,10000,9000),(186,-1,'up',1631649853,1000,1514),(186,1631649853,'up',1631649832,10000,9000),(187,-1,'up',1631649853,0,0),(187,1631649853,'up',1631649832,10000,9000),(188,-1,'up',1631649853,0,0),(188,1631649853,'up',1631649832,10000,9000),(189,-1,'up',1631649853,10000,1514),(189,1631649853,'up',1631649832,10000,9000),(190,-1,'up',1631649853,10000,1514),(190,1631649853,'up',1631649832,10000,9000),(191,-1,'up',1631649853,10000,0),(191,1631649853,'up',1631649832,10000,9000),(192,-1,'up',1631649853,0,0),(192,1631649853,'up',1631649832,10000,9000),(193,-1,'up',1631649853,0,0),(193,1631649853,'up',1631649832,10000,9000),(194,-1,'up',1631649853,0,0),(194,1631649853,'up',1631649832,10000,9000),(195,-1,'up',1631649853,0,0),(195,1631649853,'up',1631649832,10000,9000),(196,-1,'up',1631649853,10000,9192),(196,1631649853,'up',1631649832,10000,9000),(197,-1,'up',1631649853,10000,1532),(197,1631649853,'up',1631649832,10000,9000),(198,-1,'up',1631649853,0,0),(198,1631649853,'up',1631649832,10000,9000),(199,-1,'up',1631649853,0,0),(199,1631649853,'up',1631649832,10000,9000),(200,-1,'up',1631649853,0,0),(200,1631649853,'up',1631649832,10000,9000),(201,-1,'up',1631649972,100000,9192),(201,1631649972,'up',1631649852,10000,9000),(202,-1,'up',1631649972,10000,9192),(202,1631649972,'up',1631649852,10000,9000),(203,-1,'up',1631649972,10000,9192),(203,1631649972,'up',1631649852,10000,9000),(204,-1,'up',1631649972,100000,9192),(204,1631649972,'up',1631649853,10000,9000),(205,-1,'up',1631649972,10000,9192),(205,1631649972,'up',1631649853,10000,9000),(206,-1,'up',1631649972,10000,9192),(206,1631649972,'up',1631649853,10000,9000);
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
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `network`
--

LOCK TABLES `network` WRITE;
/*!40000 ALTER TABLE `network` DISABLE KEYS */;
INSERT INTO `network` VALUES (1,'oess',0,0,1);
/*!40000 ALTER TABLE `network` ENABLE KEYS */;
UNLOCK TABLES;

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
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8;
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
INSERT INTO `oess_version` VALUES ('2.0.12');
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
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
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `remote_auth`
--

LOCK TABLES `remote_auth` WRITE;
/*!40000 ALTER TABLE `remote_auth` DISABLE KEYS */;
INSERT INTO `remote_auth` VALUES (1,'admin',1),(2,'admin-nm',2),(3,'admin-ro',3),(4,'alpha',4),(5,'alpha-nm',5),(6,'alpha-ro',6),(7,'bravo',7),(8,'bravo-nm',8),(9,'bravo-ro',9);
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
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user`
--

LOCK TABLES `user` WRITE;
/*!40000 ALTER TABLE `user` DISABLE KEYS */;
INSERT INTO `user` VALUES (1,'admin@localhost','admin','admin',1,'active'),(2,'admin-nm@localhost','admin-nm','admin-nm',1,'active'),(3,'admin-ro@localhost','admin-ro','admin-ro',1,'active'),(4,'alpha@localhost','alpha','alpha',0,'active'),(5,'alpha-nm@localhost','alpha-nm','alpha-nm',0,'active'),(6,'alpha-ro@localhost','alpha-ro','alpha-ro',0,'active'),(7,'bravo@localhost','bravo','bravo',0,'active'),(8,'bravo-nm@localhost','bravo-nm','bravo-nm',0,'active'),(9,'bravo-ro@localhost','bravo-ro','bravo-ro',0,'active');
/*!40000 ALTER TABLE `user` ENABLE KEYS */;
UNLOCK TABLES;

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

--
-- Dumping data for table `user_entity_membership`
--

LOCK TABLES `user_entity_membership` WRITE;
/*!40000 ALTER TABLE `user_entity_membership` DISABLE KEYS */;
INSERT INTO `user_entity_membership` VALUES (1,1);
/*!40000 ALTER TABLE `user_entity_membership` ENABLE KEYS */;
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
  `role` enum('admin','normal','read-only') NOT NULL DEFAULT 'read-only',
  PRIMARY KEY (`workgroup_id`,`user_id`),
  KEY `user_user_workgroup_membership_fk` (`user_id`),
  CONSTRAINT `user_user_workgroup_membership_fk` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `workgroups_user_workgroup_membership_fk` FOREIGN KEY (`workgroup_id`) REFERENCES `workgroup` (`workgroup_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_workgroup_membership`
--

LOCK TABLES `user_workgroup_membership` WRITE;
/*!40000 ALTER TABLE `user_workgroup_membership` DISABLE KEYS */;
INSERT INTO `user_workgroup_membership` VALUES (1,1,'admin'),(1,2,'normal'),(1,3,'read-only'),(2,4,'admin'),(2,5,'normal'),(2,6,'read-only'),(3,7,'admin'),(3,8,'normal'),(3,9,'read-only');
/*!40000 ALTER TABLE `user_workgroup_membership` ENABLE KEYS */;
UNLOCK TABLES;

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
) ENGINE=InnoDB AUTO_INCREMENT=6000 DEFAULT CHARSET=utf8;
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
  `mtu` int(11) NOT NULL DEFAULT '9000',
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
  `ip_version` enum('ipv4','ipv6') DEFAULT NULL,
  `md5_key` varchar(255) DEFAULT NULL,
  `circuit_ep_id` int(11) DEFAULT NULL,
  `bfd` int(1) NOT NULL DEFAULT '0',
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
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `workgroup`
--

LOCK TABLES `workgroup` WRITE;
/*!40000 ALTER TABLE `workgroup` DISABLE KEYS */;
INSERT INTO `workgroup` VALUES (1,'admin','admin',NULL,'admin',10,20,10,'active'),(2,'alpha','alpha',NULL,'normal',10,20,10,'active'),(3,'bravo','bravo',NULL,'normal',10,20,10,'active');
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
-- Dumping data for table `workgroup_node_membership`
--

LOCK TABLES `workgroup_node_membership` WRITE;
/*!40000 ALTER TABLE `workgroup_node_membership` DISABLE KEYS */;
/*!40000 ALTER TABLE `workgroup_node_membership` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2021-09-14 20:16:55
