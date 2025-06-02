"""
AIPress Database Provisioner

Cloud Function for automated database provisioning and management.
Handles creation of databases for new WordPress tenants across shared instances.
"""

import json
import logging
import os
import random
import string
from typing import Dict, List, Optional, Tuple

import mysql.connector
from google.cloud import pubsub_v1
from google.cloud import secretmanager
from google.cloud import sql_v1
from google.cloud import spanner

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration from environment variables
SHARED_SERVICES_PROJECT = os.environ.get('SHARED_SERVICES_PROJECT')
DB_CREDENTIALS_SECRET = os.environ.get('DB_CREDENTIALS_SECRET')
MAX_DATABASES_PER_INSTANCE = int(os.environ.get('MAX_DATABASES_PER_INSTANCE', '${max_databases_per_instance}'))

# Database configuration
WORDPRESS_SCHEMA = '''
CREATE DATABASE IF NOT EXISTS `{database_name}` 
CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE `{database_name}`;

-- WordPress core tables
CREATE TABLE IF NOT EXISTS wp_posts (
    ID bigint(20) unsigned NOT NULL AUTO_INCREMENT,
    post_author bigint(20) unsigned NOT NULL DEFAULT '0',
    post_date datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
    post_date_gmt datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
    post_content longtext NOT NULL,
    post_title text NOT NULL,
    post_excerpt text NOT NULL,
    post_status varchar(20) NOT NULL DEFAULT 'publish',
    comment_status varchar(20) NOT NULL DEFAULT 'open',
    ping_status varchar(20) NOT NULL DEFAULT 'open',
    post_password varchar(255) NOT NULL DEFAULT '',
    post_name varchar(200) NOT NULL DEFAULT '',
    to_ping text NOT NULL,
    pinged text NOT NULL,
    post_modified datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
    post_modified_gmt datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
    post_content_filtered longtext NOT NULL,
    post_parent bigint(20) unsigned NOT NULL DEFAULT '0',
    guid varchar(255) NOT NULL DEFAULT '',
    menu_order int(11) NOT NULL DEFAULT '0',
    post_type varchar(20) NOT NULL DEFAULT 'post',
    post_mime_type varchar(100) NOT NULL DEFAULT '',
    comment_count bigint(20) NOT NULL DEFAULT '0',
    PRIMARY KEY (ID),
    KEY post_name (post_name(191)),
    KEY type_status_date (post_type,post_status,post_date,ID),
    KEY post_parent (post_parent),
    KEY post_author (post_author)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS wp_users (
    ID bigint(20) unsigned NOT NULL AUTO_INCREMENT,
    user_login varchar(60) NOT NULL DEFAULT '',
    user_pass varchar(255) NOT NULL DEFAULT '',
    user_nicename varchar(50) NOT NULL DEFAULT '',
    user_email varchar(100) NOT NULL DEFAULT '',
    user_url varchar(100) NOT NULL DEFAULT '',
    user_registered datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
    user_activation_key varchar(255) NOT NULL DEFAULT '',
    user_status int(11) NOT NULL DEFAULT '0',
    display_name varchar(250) NOT NULL DEFAULT '',
    PRIMARY KEY (ID),
    KEY user_login_key (user_login),
    KEY user_nicename (user_nicename),
    KEY user_email (user_email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS wp_options (
    option_id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
    option_name varchar(191) NOT NULL DEFAULT '',
    option_value longtext NOT NULL,
    autoload varchar(20) NOT NULL DEFAULT 'yes',
    PRIMARY KEY (option_id),
    UNIQUE KEY option_name (option_name),
    KEY autoload (autoload)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Additional WordPress tables would be created here
-- This is a simplified schema for the example
'''

class DatabaseProvisioner:
    """Handles automated database provisioning for WordPress tenants."""
    
    def __init__(self):
        self.secret_client = secretmanager.SecretManagerServiceClient()
        self.sql_client = sql_v1.SqlInstancesServiceClient()
        self.spanner_client = spanner.Client(project=SHARED_SERVICES_PROJECT)
        self.db_credentials = self._load_db_credentials()
    
    def _load_db_credentials(self) -> Dict:
        """Load database credentials from Secret Manager."""
        try:
            secret_name = f"projects/{SHARED_SERVICES_PROJECT}/secrets/{DB_CREDENTIALS_SECRET}/versions/latest"
            response = self.secret_client.access_secret_version(request={"name": secret_name})
            secret_payload = response.payload.data.decode("UTF-8")
            return json.loads(secret_payload)
        except Exception as e:
            logger.error(f"Failed to load database credentials: {e}")
            raise
    
    def _get_optimal_instance(self, region: str) -> Tuple[str, Dict]:
        """Find the optimal Cloud SQL instance for new database."""
        instances = self.db_credentials.get('instances', {})
        region_instances = {k: v for k, v in instances.items() if region in k}
        
        if not region_instances:
            raise ValueError(f"No database instances found in region {region}")
        
        # Get current database counts for each instance
        instance_loads = {}
        for instance_name, instance_info in region_instances.items():
            try:
                db_count = self._count_databases(instance_info)
                instance_loads[instance_name] = {
                    'info': instance_info,
                    'db_count': db_count,
                    'available_capacity': MAX_DATABASES_PER_INSTANCE - db_count
                }
            except Exception as e:
                logger.warning(f"Failed to get database count for {instance_name}: {e}")
                continue
        
        # Find instance with most available capacity
        if not instance_loads:
            raise ValueError("No available database instances found")
        
        optimal_instance = max(instance_loads.items(), 
                             key=lambda x: x[1]['available_capacity'])
        
        if optimal_instance[1]['available_capacity'] <= 0:
            raise ValueError("All database instances are at capacity")
        
        return optimal_instance[0], optimal_instance[1]['info']
    
    def _count_databases(self, instance_info: Dict) -> int:
        """Count existing databases on an instance."""
        connection = mysql.connector.connect(
            host=instance_info['host'],
            port=instance_info['port'],
            user=instance_info['users']['admin_user']['username'],
            password=instance_info['users']['admin_user']['password'],
            ssl_disabled=False
        )
        
        try:
            cursor = connection.cursor()
            cursor.execute("SHOW DATABASES")
            databases = cursor.fetchall()
            
            # Filter out system databases
            system_dbs = {'information_schema', 'mysql', 'performance_schema', 'sys'}
            user_dbs = [db[0] for db in databases if db[0] not in system_dbs]
            
            return len(user_dbs)
        finally:
            connection.close()
    
    def _generate_database_name(self, tenant_id: str) -> str:
        """Generate a safe database name for the tenant."""
        # WordPress database names should be alphanumeric and underscores only
        safe_tenant_id = ''.join(c for c in tenant_id if c.isalnum() or c == '_')
        return f"wp_{safe_tenant_id}"
    
    def _generate_database_user(self, tenant_id: str) -> Tuple[str, str]:
        """Generate database user and password for the tenant."""
        # Generate a safe username
        safe_tenant_id = ''.join(c for c in tenant_id if c.isalnum() or c == '_')
        username = f"wp_user_{safe_tenant_id}"[:32]  # MySQL username limit
        
        # Generate a strong password
        password = self._generate_strong_password()
        
        return username, password
    
    def _generate_strong_password(self, length: int = 24) -> str:
        """Generate a strong password for database user."""
        characters = string.ascii_letters + string.digits + "!@#$%^&*"
        password = ''.join(random.choice(characters) for _ in range(length))
        return password
    
    def create_database(self, tenant_id: str, region: str) -> Dict:
        """Create a new database for a WordPress tenant."""
        try:
            # Get optimal instance
            instance_name, instance_info = self._get_optimal_instance(region)
            
            # Generate database and user details
            database_name = self._generate_database_name(tenant_id)
            username, password = self._generate_database_user(tenant_id)
            
            # Connect to the instance
            connection = mysql.connector.connect(
                host=instance_info['host'],
                port=instance_info['port'],
                user=instance_info['users']['admin_user']['username'],
                password=instance_info['users']['admin_user']['password'],
                ssl_disabled=False
            )
            
            try:
                cursor = connection.cursor()
                
                # Create database
                cursor.execute(f"CREATE DATABASE IF NOT EXISTS `{database_name}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci")
                
                # Create user
                cursor.execute(f"CREATE USER IF NOT EXISTS '{username}'@'%' IDENTIFIED BY '{password}'")
                
                # Grant privileges
                cursor.execute(f"GRANT ALL PRIVILEGES ON `{database_name}`.* TO '{username}'@'%'")
                cursor.execute("FLUSH PRIVILEGES")
                
                # Create WordPress schema
                schema_queries = WORDPRESS_SCHEMA.format(database_name=database_name).split(';')
                for query in schema_queries:
                    query = query.strip()
                    if query:
                        cursor.execute(query)
                
                connection.commit()
                
                result = {
                    'tenant_id': tenant_id,
                    'database_name': database_name,
                    'instance_name': instance_name,
                    'host': instance_info['host'],
                    'port': instance_info['port'],
                    'username': username,
                    'password': password,
                    'region': region,
                    'status': 'created'
                }
                
                # Update metadata in Spanner
                self._update_tenant_metadata(result)
                
                logger.info(f"Successfully created database {database_name} for tenant {tenant_id}")
                return result
                
            finally:
                connection.close()
                
        except Exception as e:
            logger.error(f"Failed to create database for tenant {tenant_id}: {e}")
            raise
    
    def _update_tenant_metadata(self, db_info: Dict):
        """Update tenant metadata in Cloud Spanner."""
        try:
            instance_id = "aipress-metadata"
            database_id = "aipress-db"
            
            database = self.spanner_client.instance(instance_id).database(database_id)
            
            with database.batch() as batch:
                batch.update(
                    table="tenants",
                    columns=["tenant_id", "database_name", "database_host", "database_user"],
                    values=[(
                        db_info['tenant_id'],
                        db_info['database_name'],
                        db_info['host'],
                        db_info['username']
                    )]
                )
                
        except Exception as e:
            logger.warning(f"Failed to update tenant metadata: {e}")
    
    def delete_database(self, tenant_id: str) -> Dict:
        """Delete a database for a tenant (cleanup)."""
        try:
            database_name = self._generate_database_name(tenant_id)
            username, _ = self._generate_database_user(tenant_id)
            
            # Find which instance has this database
            for instance_name, instance_info in self.db_credentials.get('instances', {}).items():
                try:
                    connection = mysql.connector.connect(
                        host=instance_info['host'],
                        port=instance_info['port'],
                        user=instance_info['users']['admin_user']['username'],
                        password=instance_info['users']['admin_user']['password'],
                        ssl_disabled=False
                    )
                    
                    cursor = connection.cursor()
                    
                    # Check if database exists
                    cursor.execute(f"SHOW DATABASES LIKE '{database_name}'")
                    if cursor.fetchone():
                        # Drop database and user
                        cursor.execute(f"DROP DATABASE IF EXISTS `{database_name}`")
                        cursor.execute(f"DROP USER IF EXISTS '{username}'@'%'")
                        cursor.execute("FLUSH PRIVILEGES")
                        connection.commit()
                        
                        logger.info(f"Successfully deleted database {database_name} for tenant {tenant_id}")
                        return {'status': 'deleted', 'tenant_id': tenant_id}
                    
                    connection.close()
                    
                except Exception as e:
                    logger.warning(f"Error checking instance {instance_name}: {e}")
                    continue
            
            return {'status': 'not_found', 'tenant_id': tenant_id}
            
        except Exception as e:
            logger.error(f"Failed to delete database for tenant {tenant_id}: {e}")
            raise


def provision_database(cloud_event, context):
    """Cloud Function entry point for database provisioning."""
    try:
        # Parse the Pub/Sub message
        pubsub_message = cloud_event.data
        message_data = json.loads(pubsub_message.decode('utf-8'))
        
        action = message_data.get('action', 'create')
        tenant_id = message_data.get('tenant_id')
        region = message_data.get('region', 'us-central1')
        
        if not tenant_id:
            raise ValueError("tenant_id is required")
        
        provisioner = DatabaseProvisioner()
        
        if action == 'create':
            result = provisioner.create_database(tenant_id, region)
        elif action == 'delete':
            result = provisioner.delete_database(tenant_id)
        else:
            raise ValueError(f"Unknown action: {action}")
        
        logger.info(f"Database provisioning completed: {result}")
        return result
        
    except Exception as e:
        logger.error(f"Database provisioning failed: {e}")
        raise


if __name__ == "__main__":
    # For local testing
    test_event = {
        'data': json.dumps({
            'action': 'create',
            'tenant_id': 'test_tenant_001',
            'region': 'us-central1'
        }).encode('utf-8')
    }
    
    result = provision_database(test_event, None)
    print(f"Test result: {result}")
