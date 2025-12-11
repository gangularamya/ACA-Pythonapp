<#
.SYNOPSIS
    Deploy Python Container App with Cosmos DB using User-Assigned Managed Identity

.DESCRIPTION
    This script creates all necessary Azure resources step-by-step:
    - Resource Group
    - User-Assigned Managed Identity
    - Cosmos DB Account, Database, and Container
    - Azure Container Registry
    - Container Apps Environment
    - Container App with managed identity configuration
    - RBAC role assignment for Cosmos DB access

.NOTES
    Prerequisites:
    - Azure CLI installed and logged in
    - Docker installed (for building image)
    - Appropriate Azure subscription permissions
#>

# ============================================================================
# CONFIGURATION - Update these variables before running
# ============================================================================

$RESOURCE_GROUP = "rg-containerapp-demo"
$LOCATION = "westus2"

# Managed Identity
$IDENTITY_NAME = "id-containerapp-cosmosdb"

# Cosmos DB
$COSMOS_ACCOUNT_NAME = "cosmos-containerapp-$(Get-Random -Minimum 1000 -Maximum 9999)"
$COSMOS_DATABASE_NAME = "SampleDB"
$COSMOS_CONTAINER_NAME = "Items"

# Key Vault
$KEY_VAULT_NAME = "kv-containerapp-$(Get-Random -Minimum 1000 -Maximum 9999)"

# Container Registry
$ACR_NAME = "acrcontainerapp$(Get-Random -Minimum 1000 -Maximum 9999)"

# Container Apps
$CONTAINERAPPS_ENVIRONMENT = "env-containerapp"
$CONTAINER_APP_NAME = "app-python-cosmosdb"
$CONTAINER_IMAGE_NAME = "python-cosmosdb-app"
$CONTAINER_IMAGE_TAG = "latest"

# ============================================================================
# DEPLOYMENT STEPS
# ============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Azure Container App Deployment Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Create Resource Group with Tags
Write-Host "Step 1: Creating Resource Group with Tags..." -ForegroundColor Yellow
az group create `
    --name $RESOURCE_GROUP `
    --location $LOCATION `
    --tags "CostControl=Ignore" "SecurityControl=Ignore"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create resource group"
    exit 1
}
Write-Host "✓ Resource Group created: $RESOURCE_GROUP" -ForegroundColor Green
Write-Host "  Tags: CostControl=Ignore, SecurityControl=Ignore" -ForegroundColor Gray
Write-Host ""

# Step 2: Create User-Assigned Managed Identity
Write-Host "Step 2: Creating User-Assigned Managed Identity..." -ForegroundColor Yellow
az identity create `
    --name $IDENTITY_NAME `
    --resource-group $RESOURCE_GROUP `
    --location $LOCATION

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create managed identity"
    exit 1
}

# Get identity details
$IDENTITY_ID = az identity show `
    --name $IDENTITY_NAME `
    --resource-group $RESOURCE_GROUP `
    --query id `
    --output tsv

$IDENTITY_PRINCIPAL_ID = az identity show `
    --name $IDENTITY_NAME `
    --resource-group $RESOURCE_GROUP `
    --query principalId `
    --output tsv

$IDENTITY_CLIENT_ID = az identity show `
    --name $IDENTITY_NAME `
    --resource-group $RESOURCE_GROUP `
    --query clientId `
    --output tsv

Write-Host "✓ Managed Identity created: $IDENTITY_NAME" -ForegroundColor Green
Write-Host "  Principal ID: $IDENTITY_PRINCIPAL_ID" -ForegroundColor Gray
Write-Host "  Client ID: $IDENTITY_CLIENT_ID" -ForegroundColor Gray
Write-Host ""

# Step 3: Create Cosmos DB Account
Write-Host "Step 3: Creating Cosmos DB Account (this may take a few minutes)..." -ForegroundColor Yellow
az cosmosdb create `
    --name $COSMOS_ACCOUNT_NAME `
    --resource-group $RESOURCE_GROUP `
    --locations regionName=$LOCATION failoverPriority=0 isZoneRedundant=False `
    --default-consistency-level "Session" `
    --enable-automatic-failover false `
    --enable-free-tier false

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create Cosmos DB account"
    exit 1
}

# Get Cosmos DB details
$COSMOS_ENDPOINT = az cosmosdb show `
    --name $COSMOS_ACCOUNT_NAME `
    --resource-group $RESOURCE_GROUP `
    --query documentEndpoint `
    --output tsv

$COSMOS_ACCOUNT_ID = az cosmosdb show `
    --name $COSMOS_ACCOUNT_NAME `
    --resource-group $RESOURCE_GROUP `
    --query id `
    --output tsv

Write-Host "✓ Cosmos DB Account created: $COSMOS_ACCOUNT_NAME" -ForegroundColor Green
Write-Host "  Endpoint: $COSMOS_ENDPOINT" -ForegroundColor Gray
Write-Host ""

# Step 4: Create Cosmos DB Database
Write-Host "Step 4: Creating Cosmos DB Database..." -ForegroundColor Yellow
az cosmosdb sql database create `
    --account-name $COSMOS_ACCOUNT_NAME `
    --resource-group $RESOURCE_GROUP `
    --name $COSMOS_DATABASE_NAME

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create Cosmos DB database"
    exit 1
}
Write-Host "✓ Database created: $COSMOS_DATABASE_NAME" -ForegroundColor Green
Write-Host ""

# Step 5: Create Cosmos DB Container
Write-Host "Step 5: Creating Cosmos DB Container..." -ForegroundColor Yellow
az cosmosdb sql container create `
    --account-name $COSMOS_ACCOUNT_NAME `
    --resource-group $RESOURCE_GROUP `
    --database-name $COSMOS_DATABASE_NAME `
    --name $COSMOS_CONTAINER_NAME `
    --partition-key-path "/category" `
    --throughput 400

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create Cosmos DB container"
    exit 1
}
Write-Host "✓ Container created: $COSMOS_CONTAINER_NAME" -ForegroundColor Green
Write-Host ""

# Step 6: Assign RBAC Role to Managed Identity for Cosmos DB
Write-Host "Step 6: Assigning Cosmos DB Data Contributor role to Managed Identity..." -ForegroundColor Yellow
Write-Host "  (Waiting 30 seconds for identity propagation...)" -ForegroundColor Gray
Start-Sleep -Seconds 30

$COSMOS_ROLE_ID = "00000000-0000-0000-0000-000000000002"  # Cosmos DB Built-in Data Contributor

az cosmosdb sql role assignment create `
    --account-name $COSMOS_ACCOUNT_NAME `
    --resource-group $RESOURCE_GROUP `
    --role-definition-id $COSMOS_ROLE_ID `
    --principal-id $IDENTITY_PRINCIPAL_ID `
    --scope $COSMOS_ACCOUNT_ID

if ($LASTEXITCODE -ne 0) {
    Write-Warning "Failed to assign RBAC role. You may need to assign it manually."
} else {
    Write-Host "✓ RBAC role assigned successfully" -ForegroundColor Green
}
Write-Host ""

# Step 6b: Create Azure Key Vault
Write-Host "Step 6b: Creating Azure Key Vault..." -ForegroundColor Yellow
az keyvault create `
    --name $KEY_VAULT_NAME `
    --resource-group $RESOURCE_GROUP `
    --location $LOCATION `
    --enable-rbac-authorization true

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create Key Vault"
    exit 1
}

$KEY_VAULT_URL = az keyvault show `
    --name $KEY_VAULT_NAME `
    --resource-group $RESOURCE_GROUP `
    --query properties.vaultUri `
    --output tsv

Write-Host "✓ Key Vault created: $KEY_VAULT_NAME" -ForegroundColor Green
Write-Host "  Vault URL: $KEY_VAULT_URL" -ForegroundColor Gray
Write-Host ""

# Step 6c: Assign Key Vault Secrets Officer role to Managed Identity
Write-Host "Step 6c: Assigning Key Vault Secrets Officer role to Managed Identity..." -ForegroundColor Yellow

$KEY_VAULT_ID = az keyvault show `
    --name $KEY_VAULT_NAME `
    --resource-group $RESOURCE_GROUP `
    --query id `
    --output tsv

az role assignment create `
    --role "Key Vault Secrets Officer" `
    --assignee $IDENTITY_PRINCIPAL_ID `
    --scope $KEY_VAULT_ID

if ($LASTEXITCODE -ne 0) {
    Write-Warning "Failed to assign Key Vault role. You may need to assign it manually."
} else {
    Write-Host "✓ Key Vault role assigned successfully" -ForegroundColor Green
}
Write-Host ""

# Step 6d: Create sample secrets in Key Vault
Write-Host "Step 6d: Creating sample secrets in Key Vault..." -ForegroundColor Yellow
az keyvault secret set `
    --vault-name $KEY_VAULT_NAME `
    --name "app-secret" `
    --value "Hello from Key Vault!"

az keyvault secret set `
    --vault-name $KEY_VAULT_NAME `
    --name "database-connection" `
    --value "sample-connection-string"

Write-Host "✓ Sample secrets created" -ForegroundColor Green
Write-Host ""

# Step 7: Create Azure Container Registry
Write-Host "Step 7: Creating Azure Container Registry..." -ForegroundColor Yellow
az acr create `
    --resource-group $RESOURCE_GROUP `
    --name $ACR_NAME `
    --sku Basic `
    --admin-enabled true

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create Azure Container Registry"
    exit 1
}

$ACR_LOGIN_SERVER = az acr show `
    --name $ACR_NAME `
    --resource-group $RESOURCE_GROUP `
    --query loginServer `
    --output tsv

Write-Host "✓ Container Registry created: $ACR_NAME" -ForegroundColor Green
Write-Host "  Login Server: $ACR_LOGIN_SERVER" -ForegroundColor Gray
Write-Host ""

# Step 8: Build and Push Docker Image
Write-Host "Step 8: Building and pushing Docker image to ACR..." -ForegroundColor Yellow
az acr build `
    --registry $ACR_NAME `
    --image "${CONTAINER_IMAGE_NAME}:${CONTAINER_IMAGE_TAG}" `
    --file Dockerfile `
    .

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to build and push Docker image"
    exit 1
}
Write-Host "✓ Docker image built and pushed: ${CONTAINER_IMAGE_NAME}:${CONTAINER_IMAGE_TAG}" -ForegroundColor Green
Write-Host ""

# Step 9: Create Container Apps Environment
Write-Host "Step 9: Creating Container Apps Environment..." -ForegroundColor Yellow
az containerapp env create `
    --name $CONTAINERAPPS_ENVIRONMENT `
    --resource-group $RESOURCE_GROUP `
    --location $LOCATION

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create Container Apps environment"
    exit 1
}
Write-Host "✓ Container Apps Environment created: $CONTAINERAPPS_ENVIRONMENT" -ForegroundColor Green
Write-Host ""

# Step 10: Get ACR Credentials
Write-Host "Step 10: Retrieving ACR credentials..." -ForegroundColor Yellow
$ACR_USERNAME = az acr credential show `
    --name $ACR_NAME `
    --query username `
    --output tsv

$ACR_PASSWORD = az acr credential show `
    --name $ACR_NAME `
    --query "passwords[0].value" `
    --output tsv

Write-Host "✓ ACR credentials retrieved" -ForegroundColor Green
Write-Host ""

# Step 11: Create Container App
Write-Host "Step 11: Creating Container App with Managed Identity..." -ForegroundColor Yellow
az containerapp create `
    --name $CONTAINER_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --environment $CONTAINERAPPS_ENVIRONMENT `
    --image "${ACR_LOGIN_SERVER}/${CONTAINER_IMAGE_NAME}:${CONTAINER_IMAGE_TAG}" `
    --registry-server $ACR_LOGIN_SERVER `
    --registry-username $ACR_USERNAME `
    --registry-password $ACR_PASSWORD `
    --target-port 8080 `
    --ingress external `
    --user-assigned $IDENTITY_ID `
    --env-vars `
        "COSMOS_ENDPOINT=$COSMOS_ENDPOINT" `
        "COSMOS_DATABASE_NAME=$COSMOS_DATABASE_NAME" `
        "COSMOS_CONTAINER_NAME=$COSMOS_CONTAINER_NAME" `
        "AZURE_CLIENT_ID=$IDENTITY_CLIENT_ID" `
        "KEY_VAULT_URL=$KEY_VAULT_URL" `
    --cpu 0.5 `
    --memory 1.0Gi `
    --min-replicas 1 `
    --max-replicas 3

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create Container App"
    exit 1
}

$APP_URL = az containerapp show `
    --name $CONTAINER_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --query properties.configuration.ingress.fqdn `
    --output tsv

Write-Host "✓ Container App created: $CONTAINER_APP_NAME" -ForegroundColor Green
Write-Host ""

# ============================================================================
# DEPLOYMENT SUMMARY
# ============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DEPLOYMENT COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Resource Group: $RESOURCE_GROUP" -ForegroundColor White
Write-Host "Location: $LOCATION" -ForegroundColor White
Write-Host ""
Write-Host "Managed Identity:" -ForegroundColor White
Write-Host "  Name: $IDENTITY_NAME" -ForegroundColor Gray
Write-Host "  Principal ID: $IDENTITY_PRINCIPAL_ID" -ForegroundColor Gray
Write-Host ""
Write-Host "Cosmos DB:" -ForegroundColor White
Write-Host "  Account: $COSMOS_ACCOUNT_NAME" -ForegroundColor Gray
Write-Host "  Endpoint: $COSMOS_ENDPOINT" -ForegroundColor Gray
Write-Host "  Database: $COSMOS_DATABASE_NAME" -ForegroundColor Gray
Write-Host "  Container: $COSMOS_CONTAINER_NAME" -ForegroundColor Gray
Write-Host ""
Write-Host "Key Vault:" -ForegroundColor White
Write-Host "  Name: $KEY_VAULT_NAME" -ForegroundColor Gray
Write-Host "  URL: $KEY_VAULT_URL" -ForegroundColor Gray
Write-Host ""
Write-Host "Container Registry:" -ForegroundColor White
Write-Host "  Name: $ACR_NAME" -ForegroundColor Gray
Write-Host "  Server: $ACR_LOGIN_SERVER" -ForegroundColor Gray
Write-Host ""
Write-Host "Container App:" -ForegroundColor White
Write-Host "  Name: $CONTAINER_APP_NAME" -ForegroundColor Gray
Write-Host "  URL: https://$APP_URL" -ForegroundColor Gray
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TEST YOUR APPLICATION:" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Health Check:" -ForegroundColor White
Write-Host "  curl https://$APP_URL/health" -ForegroundColor Gray
Write-Host ""
Write-Host "Create an item:" -ForegroundColor White
Write-Host "  curl -X POST https://$APP_URL/items ``" -ForegroundColor Gray
Write-Host "    -H 'Content-Type: application/json' ``" -ForegroundColor Gray
Write-Host "    -d '{\"id\":\"1\",\"category\":\"electronics\",\"name\":\"Laptop\",\"price\":999.99}'" -ForegroundColor Gray
Write-Host ""
Write-Host "Get all items:" -ForegroundColor White
Write-Host "  curl https://$APP_URL/items" -ForegroundColor Gray
Write-Host ""
Write-Host "List Key Vault secrets:" -ForegroundColor White
Write-Host "  curl https://$APP_URL/secrets" -ForegroundColor Gray
Write-Host ""
Write-Host "Get a secret value:" -ForegroundColor White
Write-Host "  curl https://$APP_URL/secrets/app-secret" -ForegroundColor Gray
Write-Host ""
Write-Host "Create a new secret:" -ForegroundColor White
Write-Host "  curl -X POST https://$APP_URL/secrets/my-secret ``" -ForegroundColor Gray
Write-Host "    -H 'Content-Type: application/json' ``" -ForegroundColor Gray
Write-Host "    -d '{\"value\":\"my-secret-value\"}'" -ForegroundColor Gray
Write-Host ""
Write-Host "View logs:" -ForegroundColor White
Write-Host "  az containerapp logs show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --follow" -ForegroundColor Gray
Write-Host ""
