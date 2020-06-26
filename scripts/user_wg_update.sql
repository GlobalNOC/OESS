USE OESS;
                                  
ALTER TABLE user_workgroup_membership ADD role enum('admin','normal','read-only') NOT NULL DEFAULT 'read-only';
UPDATE user_workgroup_membership wg, user u SET wg.role='admin' WHERE wg.user_id=u.user_id and u.type='normal';
UPDATE user_workgroup_membership wg, user u SET wg.role='read-only' WHERE wg.user_id=u.user_id AND u.type='read-only';
ALTER TABLE user DROP COLUMN type;
