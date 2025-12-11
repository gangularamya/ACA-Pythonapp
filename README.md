# Azure Container Apps - Passwordless Authentication Guide

## Overview
This guide demonstrates how to deploy a Python application to Azure Container Apps that connects to Azure Cosmos DB and Azure Key Vault using **User-Assigned Managed Identity** for passwordless authentication.

## Architecture

```
┌─────────────────────────────┐
│   Azure Container App       │
│   (Python Flask API)        │
│                             │
│   Uses: DefaultAzureCredential
│   Identity: User-Assigned MI│
└──────────┬──────────────────┘
           │
           ├─────────────────────────────┐
           │                             │
           ▼                             ▼
┌──────────────────────┐      ┌──────────────────────┐
│   Azure Cosmos DB    │      │   Azure Key Vault    │
│   (NoSQL Database)   │      │   (Secrets Store)    │
│                      │      │                      │
│   Auth: RBAC         │      │   Auth: RBAC         │
│   Role: Data         │      │   Role: Secrets      │
│   Contributor        │      │   Officer            │
└──────────────────────┘      └──────────────────────┘
```

## Key Benefits

✅ **No connection strings or passwords** in code or configuration  
✅ **Automatic credential rotation** - Azure manages identity tokens  
✅ **Unified authentication** - Same identity for multiple services  
✅ **Works locally and in Azure** - DefaultAzureCredential adapts automatically  
✅ **Enhanced security** - No secrets to leak or manage  
✅ **Simplified deployment** - No key management infrastructure needed

## Prerequisites

- Azure CLI installed and authenticated
- Docker installed
- Azure subscription with appropriate permissions
- PowerShell (for deployment script)

## Implementation Steps

### 1. Create User-Assigned Managed Identity

```bash
az identity create \
    --name id-containerapp-cosmosdb \
    --resource-group rg-containerapp-demo \
    --location westus2
```

**Get Identity Details:**
```bash
IDENTITY_PRINCIPAL_ID=$(az identity show \
    --name id-containerapp-cosmosdb \
    --resource-group rg-containerapp-demo \
    --query principalId -o tsv)

IDENTITY_CLIENT_ID=$(az identity show \
    --name id-containerapp-cosmosdb \
    --resource-group rg-containerapp-demo \
    --query clientId -o tsv)
```

### 2. Create Azure Cosmos DB with RBAC

```bash
# Create Cosmos DB Account
az cosmosdb create \
    --name cosmos-containerapp-demo \
    --resource-group rg-containerapp-demo \
    --locations regionName=westus2 failoverPriority=0 \
    --default-consistency-level "Session"

# Create Database
az cosmosdb sql database create \
    --account-name cosmos-containerapp-demo \
    --resource-group rg-containerapp-demo \
    --name SampleDB

# Create Container
az cosmosdb sql container create \
    --account-name cosmos-containerapp-demo \
    --resource-group rg-containerapp-demo \
    --database-name SampleDB \
    --name Items \
    --partition-key-path "/category" \
    --throughput 400
```

**Assign RBAC Role (Built-in Data Contributor):**
```bash
COSMOS_ACCOUNT_ID=$(az cosmosdb show \
    --name cosmos-containerapp-demo \
    --resource-group rg-containerapp-demo \
    --query id -o tsv)

az cosmosdb sql role assignment create \
    --account-name cosmos-containerapp-demo \
    --resource-group rg-containerapp-demo \
    --role-definition-id "00000000-0000-0000-0000-000000000002" \
    --principal-id $IDENTITY_PRINCIPAL_ID \
    --scope $COSMOS_ACCOUNT_ID
```

### 3. Create Azure Key Vault with RBAC

```bash
# Create Key Vault with RBAC authorization
az keyvault create \
    --name kv-containerapp-demo \
    --resource-group rg-containerapp-demo \
    --location westus2 \
    --enable-rbac-authorization true

# Assign Key Vault Secrets Officer role
KEY_VAULT_ID=$(az keyvault show \
    --name kv-containerapp-demo \
    --resource-group rg-containerapp-demo \
    --query id -o tsv)

az role assignment create \
    --role "Key Vault Secrets Officer" \
    --assignee $IDENTITY_PRINCIPAL_ID \
    --scope $KEY_VAULT_ID
```

### 4. Python Application Code

**Key Components:**

```python
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

# Single credential for all Azure services
credential = DefaultAzureCredential()

# Cosmos DB Client (no connection string needed!)
cosmos_client = CosmosClient(
    COSMOS_ENDPOINT, 
    credential=credential
)

# Key Vault Client (no access keys needed!)
keyvault_client = SecretClient(
    vault_url=KEY_VAULT_URL, 
    credential=credential
)
```

**Environment Variables:**
```python
COSMOS_ENDPOINT = os.getenv("COSMOS_ENDPOINT")
KEY_VAULT_URL = os.getenv("KEY_VAULT_URL")
AZURE_CLIENT_ID = os.getenv("AZURE_CLIENT_ID")  # For managed identity
```

**Dependencies (requirements.txt):**
```
flask==3.0.0
azure-cosmos==4.5.1
azure-identity==1.15.0
azure-keyvault-secrets==4.7.0
gunicorn==21.2.0
```

### 5. Deploy to Container Apps

```bash
# Create Container Apps Environment
az containerapp env create \
    --name env-containerapp \
    --resource-group rg-containerapp-demo \
    --location westus2

# Deploy Container App with Managed Identity
az containerapp create \
    --name app-python-cosmosdb \
    --resource-group rg-containerapp-demo \
    --environment env-containerapp \
    --image <your-acr>.azurecr.io/python-app:latest \
    --target-port 8080 \
    --ingress external \
    --user-assigned <identity-resource-id> \
    --env-vars \
        "COSMOS_ENDPOINT=https://cosmos-containerapp-demo.documents.azure.com:443/" \
        "COSMOS_DATABASE_NAME=SampleDB" \
        "COSMOS_CONTAINER_NAME=Items" \
        "AZURE_CLIENT_ID=<identity-client-id>" \
        "KEY_VAULT_URL=https://kv-containerapp-demo.vault.azure.net/" \
    --cpu 0.5 \
    --memory 1.0Gi \
    --min-replicas 1 \
    --max-replicas 3
```

## How Passwordless Authentication Works

### In Azure (Production)
1. Container App is assigned the User-Assigned Managed Identity
2. `DefaultAzureCredential` detects it's running in Azure and uses the managed identity
3. Azure automatically provides OAuth tokens to the app
4. Tokens are used to authenticate to Cosmos DB and Key Vault
5. Tokens auto-rotate without application restart

### Locally (Development)
1. Developer runs `az login` to authenticate Azure CLI
2. `DefaultAzureCredential` detects Azure CLI credentials
3. Same code works locally using developer's credentials
4. No code changes needed between local and Azure environments

## API Endpoints

### Cosmos DB Operations
- `GET /health` - Check connection status
- `GET /items` - List all items
- `GET /items/<id>?category=<cat>` - Get specific item
- `POST /items` - Create new item (JSON body with id, category, and other fields)
- `PUT /items/<id>` - Update item (JSON body with category and fields)
- `DELETE /items/<id>?category=<cat>` - Delete item

### Key Vault Operations
- `GET /secrets` - List all secret names
- `GET /secrets/<name>` - Get secret value
- `POST /secrets/<name>` - Create/update secret (JSON body: `{"value": "..."}`)

## Testing with Postman

### Create Item in Cosmos DB
```
POST https://your-app.azurecontainerapps.io/items
Headers: Content-Type: application/json
Body:
{
    "id": "laptop-001",
    "category": "electronics",
    "name": "Dell Laptop",
    "price": 999.99
}
```

### Create Secret in Key Vault
```
POST https://your-app.azurecontainerapps.io/secrets/api-key
Headers: Content-Type: application/json
Body:
{
    "value": "my-secret-api-key-12345"
}
```

## Security Best Practices

1. **Use User-Assigned MI** - More control than System-Assigned, can be shared across resources
2. **Enable RBAC on Key Vault** - Don't use access policies with managed identities
3. **Principle of Least Privilege** - Assign only required roles:
   - Cosmos DB: Built-in Data Contributor (data plane access only)
   - Key Vault: Secrets Officer (for read/write) or Secrets User (read-only)
4. **Resource Tags** - Tag resources for governance and cost tracking
5. **Environment Variables** - Store endpoints in env vars, not in code
6. **No Secrets in Code** - Never hardcode connection strings or keys

## Verification Commands

**Check Cosmos DB RBAC Assignments:**
```bash
az cosmosdb sql role assignment list \
    --account-name cosmos-containerapp-demo \
    --resource-group rg-containerapp-demo
```

**Check Key Vault RBAC Assignments:**
```bash
az role assignment list \
    --scope /subscriptions/<sub-id>/resourceGroups/rg-containerapp-demo/providers/Microsoft.KeyVault/vaults/kv-containerapp-demo \
    --query "[?principalId=='<identity-principal-id>']"
```

**View Container App Environment Variables:**
```bash
az containerapp show \
    --name app-python-cosmosdb \
    --resource-group rg-containerapp-demo \
    --query "properties.template.containers[0].env" -o table
```

**View Application Logs:**
```bash
az containerapp logs show \
    --name app-python-cosmosdb \
    --resource-group rg-containerapp-demo \
    --follow

## Complete Deployment Script

A complete PowerShell deployment script is included in the repository that automates all the above steps:
- `deploy.ps1` - Creates all resources with proper configuration

Run with:
```powershell
.\deploy.ps1
```

## Summary

This solution demonstrates **modern passwordless authentication** using:
- ✅ User-Assigned Managed Identity
- ✅ Azure RBAC for authorization
- ✅ DefaultAzureCredential for unified authentication
- ✅ No secrets in code or configuration
- ✅ Works seamlessly in both Azure and local development

The same pattern can be applied to any Azure service that supports managed identities, including:
- Azure Storage (Blob, Queue, Table)
- Azure Service Bus
- Azure Event Hubs
- Azure SQL Database
- Azure App Configuration
- And many more...

## Additional Resources

- [Azure Container Apps Documentation](https://learn.microsoft.com/azure/container-apps/)
- [Managed Identities for Azure Resources](https://learn.microsoft.com/azure/active-directory/managed-identities-azure-resources/)
- [Azure Cosmos DB RBAC](https://learn.microsoft.com/azure/cosmos-db/role-based-access-control)
- [Azure Key Vault RBAC](https://learn.microsoft.com/azure/key-vault/general/rbac-guide)
- [DefaultAzureCredential](https://learn.microsoft.com/python/api/azure-identity/azure.identity.defaultazurecredential)

