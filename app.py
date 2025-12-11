"""
Azure Container App - Python application connecting to Cosmos DB and Key Vault
using User-Assigned Managed Identity
"""
import os
import logging
from azure.cosmos import CosmosClient, PartitionKey, exceptions
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from flask import Flask, jsonify, request

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Cosmos DB configuration from environment variables
COSMOS_ENDPOINT = os.getenv("COSMOS_ENDPOINT")
DATABASE_NAME = os.getenv("COSMOS_DATABASE_NAME", "SampleDB")
CONTAINER_NAME = os.getenv("COSMOS_CONTAINER_NAME", "Items")

# Key Vault configuration
KEY_VAULT_URL = os.getenv("KEY_VAULT_URL")

# Initialize clients with Managed Identity
credential = DefaultAzureCredential()
cosmos_client = None
database = None
container = None
keyvault_client = None


def initialize_cosmos_client():
    """Initialize Cosmos DB client with managed identity authentication"""
    global cosmos_client, database, container
    
    try:
        if not COSMOS_ENDPOINT:
            raise ValueError("COSMOS_ENDPOINT environment variable is not set")
        
        logger.info(f"Connecting to Cosmos DB at {COSMOS_ENDPOINT}")
        
        # Create Cosmos client using managed identity
        cosmos_client = CosmosClient(COSMOS_ENDPOINT, credential=credential)
        
        # Get or create database
        database = cosmos_client.create_database_if_not_exists(id=DATABASE_NAME)
        logger.info(f"Database '{DATABASE_NAME}' ready")
        
        # Get or create container with partition key
        container = database.create_container_if_not_exists(
            id=CONTAINER_NAME,
            partition_key=PartitionKey(path="/category"),
            offer_throughput=400
        )
        logger.info(f"Container '{CONTAINER_NAME}' ready")
        
        return True
    except Exception as e:
        logger.error(f"Failed to initialize Cosmos DB client: {str(e)}")
        return False


def initialize_keyvault_client():
    """Initialize Key Vault client with managed identity authentication"""
    global keyvault_client
    
    try:
        if not KEY_VAULT_URL:
            logger.warning("KEY_VAULT_URL environment variable is not set")
            return False
        
        logger.info(f"Connecting to Key Vault at {KEY_VAULT_URL}")
        
        # Create Key Vault client using managed identity
        keyvault_client = SecretClient(vault_url=KEY_VAULT_URL, credential=credential)
        logger.info("Key Vault client initialized successfully")
        
        return True
    except Exception as e:
        logger.error(f"Failed to initialize Cosmos DB client: {str(e)}")
        return False


def initialize_keyvault_client():
    """Initialize Key Vault client with managed identity authentication"""
    global keyvault_client
    
    try:
        if not KEY_VAULT_URL:
            logger.warning("KEY_VAULT_URL environment variable is not set")
            return False
        
        logger.info(f"Connecting to Key Vault at {KEY_VAULT_URL}")
        
        # Create Key Vault client using managed identity
        keyvault_client = SecretClient(vault_url=KEY_VAULT_URL, credential=credential)
        logger.info("Key Vault client initialized successfully")
        
        return True
    except Exception as e:
        logger.error(f"Failed to initialize Key Vault client: {str(e)}")
        return False


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "cosmos_connected": cosmos_client is not None,
        "keyvault_connected": keyvault_client is not None
    }), 200


@app.route('/items', methods=['GET'])
def get_items():
    """Get all items from Cosmos DB"""
    try:
        if not container:
            return jsonify({"error": "Cosmos DB not initialized"}), 500
        
        items = list(container.read_all_items())
        return jsonify({
            "count": len(items),
            "items": items
        }), 200
    except Exception as e:
        logger.error(f"Error fetching items: {str(e)}")
        return jsonify({"error": str(e)}), 500


@app.route('/items/<item_id>', methods=['GET'])
def get_item(item_id):
    """Get a specific item by ID"""
    try:
        if not container:
            return jsonify({"error": "Cosmos DB not initialized"}), 500
        
        category = request.args.get('category')
        if not category:
            return jsonify({"error": "category query parameter is required"}), 400
        
        item = container.read_item(item=item_id, partition_key=category)
        return jsonify(item), 200
    except exceptions.CosmosResourceNotFoundError:
        return jsonify({"error": "Item not found"}), 404
    except Exception as e:
        logger.error(f"Error fetching item: {str(e)}")
        return jsonify({"error": str(e)}), 500


@app.route('/items', methods=['POST'])
def create_item():
    """Create a new item in Cosmos DB"""
    try:
        if not container:
            return jsonify({"error": "Cosmos DB not initialized"}), 500
        
        data = request.get_json()
        if not data:
            return jsonify({"error": "Request body is required"}), 400
        
        if 'id' not in data or 'category' not in data:
            return jsonify({"error": "id and category fields are required"}), 400
        
        created_item = container.create_item(body=data)
        return jsonify(created_item), 201
    except exceptions.CosmosResourceExistsError:
        return jsonify({"error": "Item already exists"}), 409
    except Exception as e:
        logger.error(f"Error creating item: {str(e)}")
        return jsonify({"error": str(e)}), 500


@app.route('/items/<item_id>', methods=['PUT'])
def update_item(item_id):
    """Update an existing item"""
    try:
        if not container:
            return jsonify({"error": "Cosmos DB not initialized"}), 500
        
        data = request.get_json()
        if not data:
            return jsonify({"error": "Request body is required"}), 400
        
        if 'category' not in data:
            return jsonify({"error": "category field is required"}), 400
        
        # Ensure the ID in the body matches the URL parameter
        data['id'] = item_id
        
        updated_item = container.upsert_item(body=data)
        return jsonify(updated_item), 200
    except Exception as e:
        logger.error(f"Error updating item: {str(e)}")
        return jsonify({"error": str(e)}), 500


@app.route('/items/<item_id>', methods=['DELETE'])
def delete_item(item_id):
    """Delete an item"""
    try:
        if not container:
            return jsonify({"error": "Cosmos DB not initialized"}), 500
        
        category = request.args.get('category')
        if not category:
            return jsonify({"error": "category query parameter is required"}), 400
        
        container.delete_item(item=item_id, partition_key=category)
        return jsonify({"message": "Item deleted successfully"}), 200
    except exceptions.CosmosResourceNotFoundError:
        return jsonify({"error": "Item not found"}), 404
    except Exception as e:
        logger.error(f"Error deleting item: {str(e)}")
        return jsonify({"error": str(e)}), 500


@app.route('/secrets', methods=['GET'])
def list_secrets():
    """List all secret names from Key Vault"""
    try:
        if not keyvault_client:
            return jsonify({"error": "Key Vault not initialized"}), 500
        
        secret_properties = keyvault_client.list_properties_of_secrets()
        secrets = [{"name": secret.name, "enabled": secret.enabled} for secret in secret_properties]
        
        return jsonify({
            "count": len(secrets),
            "secrets": secrets
        }), 200
    except Exception as e:
        logger.error(f"Error listing secrets: {str(e)}")
        return jsonify({"error": str(e)}), 500


@app.route('/secrets/<secret_name>', methods=['GET'])
def get_secret(secret_name):
    """Get a specific secret value from Key Vault"""
    try:
        if not keyvault_client:
            return jsonify({"error": "Key Vault not initialized"}), 500
        
        secret = keyvault_client.get_secret(secret_name)
        
        return jsonify({
            "name": secret.name,
            "value": secret.value,
            "enabled": secret.properties.enabled,
            "created_on": secret.properties.created_on.isoformat() if secret.properties.created_on else None,
            "updated_on": secret.properties.updated_on.isoformat() if secret.properties.updated_on else None
        }), 200
    except Exception as e:
        logger.error(f"Error getting secret '{secret_name}': {str(e)}")
        return jsonify({"error": str(e)}), 500


@app.route('/secrets/<secret_name>', methods=['POST'])
def set_secret(secret_name):
    """Set or update a secret in Key Vault"""
    try:
        if not keyvault_client:
            return jsonify({"error": "Key Vault not initialized"}), 500
        
        data = request.get_json()
        if not data or 'value' not in data:
            return jsonify({"error": "Request body must contain 'value' field"}), 400
        
        secret = keyvault_client.set_secret(secret_name, data['value'])
        
        return jsonify({
            "name": secret.name,
            "message": "Secret created/updated successfully",
            "created_on": secret.properties.created_on.isoformat() if secret.properties.created_on else None
        }), 201
    except Exception as e:
        logger.error(f"Error setting secret '{secret_name}': {str(e)}")
        return jsonify({"error": str(e)}), 500


@app.route('/', methods=['GET'])
def home():
    """Root endpoint with API information"""
    return jsonify({
        "name": "Azure Container App - Cosmos DB & Key Vault Demo",
        "description": "Python app using User-Assigned Managed Identity",
        "endpoints": {
            "GET /health": "Health check",
            "GET /items": "Get all items from Cosmos DB",
            "GET /items/<id>?category=<cat>": "Get specific item",
            "POST /items": "Create new item",
            "PUT /items/<id>": "Update item",
            "DELETE /items/<id>?category=<cat>": "Delete item",
            "GET /secrets": "List all secrets from Key Vault",
            "GET /secrets/<name>": "Get secret value",
            "POST /secrets/<name>": "Set/update secret"
        }
    }), 200


# Initialize Cosmos DB and Key Vault when module loads (needed for Gunicorn)
initialize_cosmos_client()
initialize_keyvault_client()

if __name__ == '__main__':
    # This block runs only when using python app.py directly
    logger.info("Starting Flask application in development mode...")
    port = int(os.getenv('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)
