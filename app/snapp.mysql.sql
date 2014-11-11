
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
DROP TABLE IF EXISTS `acl_role`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `acl_role` (
  `acl_role_id` int(10) NOT NULL,
  `name` varchar(30) NOT NULL,
  PRIMARY KEY  (`acl_role_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `category`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `category` (
  `category_id` int(10) NOT NULL auto_increment,
  `name` varchar(64) NOT NULL,
  `description` varchar(128) default NULL,
  PRIMARY KEY  (`category_id`),
  UNIQUE KEY `name_idx` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `category_acl`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `category_acl` (
  `acl_role_id` int(10) NOT NULL,
  `category_id` int(10) NOT NULL,
  `can_edit` tinyint(10) NOT NULL,
  PRIMARY KEY  (`acl_role_id`,`category_id`),
  KEY `category_category_acl_fk` (`category_id`),
  CONSTRAINT `category_category_acl_fk` FOREIGN KEY (`category_id`) REFERENCES `category` (`category_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `user_role_category_acl_fk` FOREIGN KEY (`acl_role_id`) REFERENCES `acl_role` (`acl_role_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `category_collection_membership`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `category_collection_membership` (
  `collection_id` int(8) NOT NULL,
  `category_id` int(10) NOT NULL,
  `end_epoch` int(10) NOT NULL,
  `start_epoch` int(10) NOT NULL,
  PRIMARY KEY  (`collection_id`,`category_id`,`end_epoch`),
  KEY `category_category_collection_mapping_fk` (`category_id`),
  CONSTRAINT `category_category_collection_mapping_fk` FOREIGN KEY (`category_id`) REFERENCES `category` (`category_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `collection_category_collection_mapping_fk` FOREIGN KEY (`collection_id`) REFERENCES `collection` (`collection_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `category_hierarchy`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `category_hierarchy` (
  `parent_category_id` int(10) NOT NULL,
  `child_category_id` int(10) NOT NULL,
  `end_epoch` int(10) NOT NULL,
  `start_epoch` int(10) NOT NULL,
  PRIMARY KEY  (`parent_category_id`,`child_category_id`,`end_epoch`),
  KEY `category_cateogory_hiearchy_fk_1` (`child_category_id`),
  CONSTRAINT `category_cateogory_hiearchy_fk` FOREIGN KEY (`parent_category_id`) REFERENCES `category` (`category_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `category_cateogory_hiearchy_fk_1` FOREIGN KEY (`child_category_id`) REFERENCES `category` (`category_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `collection`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `collection` (
  `collection_id` int(8) NOT NULL auto_increment,
  `name` varchar(128) NOT NULL,
  `host_id` int(8) NOT NULL,
  `rrdfile` varchar(512) default NULL,
  `premap_oid_suffix` varchar(64) NOT NULL,
  `long_identifier` varchar(128) default NULL,
  `collection_class_id` int(10) NOT NULL,
  `oid_suffix_mapping_id` int(10) default NULL,
  `collector_id` int(10) NOT NULL default 0,
   `use_local_clock` int(10) NOT NULL default 0,  
  PRIMARY KEY  (`collection_id`),
  UNIQUE KEY `ind_name` (`name`),
  UNIQUE KEY `collection_idx` (`name`),
  UNIQUE KEY `long_index` (`host_id`,`long_identifier`),
  KEY `host_id` USING BTREE (`host_id`),
  KEY `suffix_mapping_collection_fk` (`oid_suffix_mapping_id`),
  KEY `collection_class_collection_fk` (`collection_class_id`),
  CONSTRAINT `collection_class_collection_fk` FOREIGN KEY (`collection_class_id`) REFERENCES `collection_class` (`collection_class_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `collection_ibfk_1` FOREIGN KEY (`host_id`) REFERENCES `host` (`host_id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `suffix_mapping_collection_fk` FOREIGN KEY (`oid_suffix_mapping_id`) REFERENCES `oid_suffix_mapping` (`oid_suffix_mapping_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `collection_acl`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `collection_acl` (
  `acl_role_id` int(10) NOT NULL,
  `collection_id` int(8) NOT NULL,
  `can_edit` int(10) NOT NULL default '0',
  PRIMARY KEY  (`acl_role_id`,`collection_id`),
  KEY `collection_collection_acl_fk` (`collection_id`),
  CONSTRAINT `collection_collection_acl_fk` FOREIGN KEY (`collection_id`) REFERENCES `collection` (`collection_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `user_role_collection_group_user_group_acl_fk` FOREIGN KEY (`acl_role_id`) REFERENCES `acl_role` (`acl_role_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `collection_class`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `collection_class` (
  `collection_class_id` int(10) NOT NULL auto_increment,
  `name` varchar(64) NOT NULL,
  `description` varchar(64) default NULL,
  `collection_interval` int(8) NOT NULL,
  `default_cf` varchar(128) NOT NULL,
  `default_class` tinyint(1) default '0',
  PRIMARY KEY  (`collection_class_id`),
  UNIQUE KEY `name_idx_1` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `collection_group`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `collection_group` (
  `collection_group_id` int(8) NOT NULL auto_increment,
  `name` varchar(64) default NULL,
  PRIMARY KEY  (`collection_group_id`),
  UNIQUE KEY `collection_group_idx` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `collection_group_user_group_acl`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `collection_group_user_group_acl` (
  `collection_group_id` int(8) NOT NULL,
  `user_group_id` int(10) NOT NULL,
  `can_edit` int(10) NOT NULL default '0',
  PRIMARY KEY  (`collection_group_id`,`user_group_id`),
  KEY `user_group_collection_group_user_group_acl_fk` (`user_group_id`),
  CONSTRAINT `collection_group_collection_group_user_group_acl_fk` FOREIGN KEY (`collection_group_id`) REFERENCES `collection_group` (`collection_group_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `user_group_collection_group_user_group_acl_fk` FOREIGN KEY (`user_group_id`) REFERENCES `user_group` (`user_group_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `collection_instantiation`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `collection_instantiation` (
  `collection_id` int(8) NOT NULL,
  `end_epoch` int(10) NOT NULL,
  `start_epoch` int(10) NOT NULL,
  `threshold` double default NULL,
  `description` varchar(256) NOT NULL,
  `max_value` int(11) default NULL,
  PRIMARY KEY  (`collection_id`,`end_epoch`),
  UNIQUE KEY `collection_id_startn_idx` (`collection_id`,`start_epoch`),
  CONSTRAINT `collection_collection_instantiation_fk` FOREIGN KEY (`collection_id`) REFERENCES `collection` (`collection_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `global`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `global` (
  `name` varchar(64) default NULL,
  `value` varchar(256) default NULL,
  KEY `k_ind` USING BTREE (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `host`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `host` (
  `host_id` int(8) NOT NULL auto_increment,
  `ip_address` varchar(40) NOT NULL,
  `description` varchar(64) NOT NULL,
  `dns_name` varchar(128) default NULL,
  `community` varchar(50) NOT NULL,
  `external_id` varchar(128) default NULL,
  PRIMARY KEY  (`host_id`),
  UNIQUE KEY `dns_name_ip_address_idx1` (`ip_address`,`dns_name`),
  UNIQUE KEY `external_id_idx` (`external_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `log`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `log` (
  `log_id` int(10) NOT NULL auto_increment,
  `ip_address` varchar(40) NOT NULL,
  `action` varchar(200) NOT NULL,
  `epoch` int(10) NOT NULL,
  `user_id` int(8) NOT NULL,
  PRIMARY KEY  (`log_id`),
  KEY `user_log_fk` (`user_id`),
  CONSTRAINT `user_log_fk` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `oid_collection`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `oid_collection` (
  `oid_collection_id` int(10) NOT NULL auto_increment,
  `name` varchar(50) default NULL,
  `oid_prefix` varchar(128) NOT NULL,
  `datatype` varchar(128) NOT NULL,
  `description` varchar(64) default NULL,
  `displaytype` varchar(20) default NULL,
  `units` varchar(25) default NULL,
  `color` varchar(10) default NULL,
  `graph_math` varchar(128) default NULL,
  `default_rrd_name` varchar(20) NOT NULL,
  `default_on` tinyint(1) NOT NULL default '1',
  PRIMARY KEY  (`oid_collection_id`),
  UNIQUE KEY `oid_collection_idx1` (`oid_prefix`),
  UNIQUE KEY `oid_collection_idx` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `oid_collection_class_map`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `oid_collection_class_map` (
  `collection_class_id` int(10) NOT NULL,
  `oid_collection_id` int(10) NOT NULL,
  `order_val` int(10) NOT NULL default '20',
  `ds_name` varchar(20) NOT NULL,
  PRIMARY KEY  (`collection_class_id`,`oid_collection_id`),
  UNIQUE KEY `ds_name_collection_class_id_idx` (`collection_class_id`,`ds_name`),
  KEY `oid_collection_oid_collection_class_map_fk` (`oid_collection_id`),
  CONSTRAINT `collection_class_oid_collection_class_map_fk` FOREIGN KEY (`collection_class_id`) REFERENCES `collection_class` (`collection_class_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `oid_collection_oid_collection_class_map_fk` FOREIGN KEY (`oid_collection_id`) REFERENCES `oid_collection` (`oid_collection_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `oid_suffix_mapping`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `oid_suffix_mapping` (
  `oid_suffix_mapping_id` int(10) NOT NULL auto_increment,
  `name` varchar(40) NOT NULL,
  `oid_suffix_mapping_value_id` int(10) NOT NULL,
  PRIMARY KEY  (`oid_suffix_mapping_id`),
  UNIQUE KEY `oid_suffix_mapping_idx` (`name`),
  UNIQUE KEY `oid_suffix_mapping_idx1` (`oid_suffix_mapping_value_id`),
  CONSTRAINT `oid_suffix_mapping_map_type_fk` FOREIGN KEY (`oid_suffix_mapping_value_id`) REFERENCES `oid_suffix_mapping_value` (`oid_suffix_mapping_value_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `oid_suffix_mapping_value`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `oid_suffix_mapping_value` (
  `oid_suffix_mapping_value_id` int(10) NOT NULL auto_increment,
  `oid` varchar(128) default NULL,
  `description` varchar(60) default NULL,
  `next_oid_suffix_mapping_value_id` int(10) default NULL,
  PRIMARY KEY  (`oid_suffix_mapping_value_id`),
  KEY `oid_suffix_mapping_value_oid_suffix_mapping_value_fk` (`next_oid_suffix_mapping_value_id`),
  CONSTRAINT `oid_suffix_mapping_value_oid_suffix_mapping_value_fk` FOREIGN KEY (`next_oid_suffix_mapping_value_id`) REFERENCES `oid_suffix_mapping_value` (`oid_suffix_mapping_value_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `rra`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `rra` (
  `rra_id` int(10) NOT NULL auto_increment,
  `collection_class_id` int(10) default NULL,
  `step` int(8) NOT NULL,
  `cf` varchar(128) NOT NULL,
  `num_days` int(8) NOT NULL,
  `xff` double NOT NULL,
  PRIMARY KEY  (`rra_id`),
  KEY `collection_class_id` USING BTREE (`collection_class_id`),
  CONSTRAINT `rra_ibfk_1` FOREIGN KEY (`collection_class_id`) REFERENCES `collection_class` (`collection_class_id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

DROP TABLE IF EXISTS `schema_version`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `schema_version` (
  `version` varchar(16) NOT NULL,
  PRIMARY KEY  (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

LOCK TABLES `schema_version` WRITE;
/*!40000 ALTER TABLE `schema_version` DISABLE KEYS */;
INSERT INTO `schema_version` VALUES ('3.0.10');
/*!40000 ALTER TABLE `schema_version` ENABLE KEYS */;
UNLOCK TABLES;

DROP TABLE IF EXISTS `user`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `user` (
  `user_id` int(8) NOT NULL auto_increment,
  `name` varchar(30) NOT NULL,
  `comment` varchar(64) NOT NULL,
  `email` varchar(64) NOT NULL,
  `active` int(10) NOT NULL default '1',
  PRIMARY KEY  (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `user_group`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `user_group` (
  `user_group_id` int(10) NOT NULL auto_increment,
  `name` varchar(50) NOT NULL,
  PRIMARY KEY  (`user_group_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `user_role_membership`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `user_role_membership` (
  `user_id` int(8) NOT NULL,
  `acl_role_id` int(10) NOT NULL,
  PRIMARY KEY  (`user_id`,`acl_role_id`),
  KEY `acl_role_user_role_membership_fk` (`acl_role_id`),
  CONSTRAINT `acl_role_user_role_membership_fk` FOREIGN KEY (`acl_role_id`) REFERENCES `acl_role` (`acl_role_id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `user_user_role_membership_fk` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
