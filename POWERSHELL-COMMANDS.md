# PowerShell Commands for Testing Azure Container Apps API

## Important Notes for PowerShell Users

PowerShell's `curl` is an **alias** for `Invoke-WebRequest`, which has different syntax than Unix curl. Use the commands below for PowerShell.

## Quick Test Commands

### 1. Health Check
```powershell
Invoke-RestMethod -Uri "https://<your-app-url>/health"
```

### 2. Create an Item
```powershell
$item = @{
    id = "1"
    category = "electronics"
    name = "Laptop"
    price = 999.99
} | ConvertTo-Json

Invoke-RestMethod -Uri "https://<your-app-url>/items" `
    -Method Post `
    -Body $item `
    -ContentType "application/json"
```

### 3. Get All Items
```powershell
Invoke-RestMethod -Uri "https://<your-app-url>/items" -Method Get
```

### 4. Get Specific Item
```powershell
Invoke-RestMethod -Uri "https://<your-app-url>/items/1?category=electronics" -Method Get
```

### 5. Update an Item
```powershell
$item = @{
    id = "1"
    category = "electronics"
    name = "Gaming Laptop"
    price = 1299.99
} | ConvertTo-Json

Invoke-RestMethod -Uri "https://<your-app-url>/items/1" `
    -Method Put `
    -Body $item `
    -ContentType "application/json"
```

### 6. Delete an Item
```powershell
Invoke-RestMethod -Uri "https://<your-app-url>/items/1?category=electronics" -Method Delete
```

## Using the Automated Test Script

For comprehensive testing, use the provided test script:

```powershell
.\test-api.ps1
```

This script automatically tests all API endpoints and displays results.

## Troubleshooting

### If you get "Cosmos DB not initialized" errors:

1. Check the logs:
```powershell
az containerapp logs show `
    --name app-python-cosmosdb `
    --resource-group rg-containerapp-demo `
    --follow
```

2. Restart the container app:
```powershell
$revision = az containerapp revision list `
    --name app-python-cosmosdb `
    --resource-group rg-containerapp-demo `
    --query "[0].name" `
    --output tsv

az containerapp revision restart `
    --name app-python-cosmosdb `
    --resource-group rg-containerapp-demo `
    --revision $revision
```

3. Wait 15-20 seconds for the restart to complete

4. Test the health endpoint:
```powershell
Invoke-RestMethod -Uri "https://<your-app-url>/health"
```

The `cosmos_connected` field should be `True`.

### Common PowerShell curl Issues

**Don't use:**
```powershell
# ❌ Wrong - This is Unix curl syntax
curl -X POST https://app-url/items -H "Content-Type: application/json" -d '{"id":"1"}'
```

**Use instead:**
```powershell
# ✅ Correct - PowerShell syntax
$body = '{"id":"1","category":"electronics","name":"Test"}' 
Invoke-RestMethod -Uri "https://app-url/items" -Method Post -Body $body -ContentType "application/json"
```

## View Application Logs

```powershell
# Follow logs in real-time
az containerapp logs show `
    --name app-python-cosmosdb `
    --resource-group rg-containerapp-demo `
    --follow

# Get last 100 log lines
az containerapp logs show `
    --name app-python-cosmosdb `
    --resource-group rg-containerapp-demo `
    --tail 100
```

## Check Container App Status

```powershell
az containerapp show `
    --name app-python-cosmosdb `
    --resource-group rg-containerapp-demo `
    --query "properties.{Status:runningStatus,FQDN:configuration.ingress.fqdn}"
```

## Update Application (After Code Changes)

```powershell
# 1. Get ACR name
$acrName = az acr list `
    --resource-group rg-containerapp-demo `
    --query "[0].name" `
    --output tsv

# 2. Build new image
az acr build `
    --registry $acrName `
    --image "python-cosmosdb-app:latest" `
    --file Dockerfile `
    .

# 3. Restart container app
$revision = az containerapp revision list `
    --name app-python-cosmosdb `
    --resource-group rg-containerapp-demo `
    --query "[0].name" `
    --output tsv

az containerapp revision restart `
    --name app-python-cosmosdb `
    --resource-group rg-containerapp-demo `
    --revision $revision

# 4. Wait and test
Start-Sleep -Seconds 20
Invoke-RestMethod -Uri "https://<your-app-url>/health"
```
