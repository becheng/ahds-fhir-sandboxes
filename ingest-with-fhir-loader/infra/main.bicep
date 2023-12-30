targetScope = 'subscription'

@minLength(1)
@maxLength(15)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Name of the resource group')
param resourceGroupName string

@description('Name of the ADHS workspace')
param adhsWorkspaceName string = 'ws${environmentName}${substring(toLower(uniqueString(subscription().id, environmentName, location)),0,7)}'

@description('Name of the fhir service')
param fhirServiceName string = 'fs${environmentName}${substring(toLower(uniqueString(subscription().id, environmentName, location)),0,7)}'

@description('Path of the synthea jar file')
@minLength(1)
param syntheaJarPath string

// @description('AzCopy SPN application ID')
// @minLength(1)
// @secure()
// param azCopySpnApplicationId string

@description('AzCopy SPN principal [object] ID')
@minLength(1)
param azCopySpnPrincipalId string

var abbrs = loadJsonContent('abbreviations.json')

// Tags that should be applied to all resources.
var tags = {
  'azd-env-name': environmentName
}

var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// Create a fhir service
module fhirService 'core/adhs/fhir.bicep' = {
  name: 'fhirService'
  scope: rg
  params: {
    workspaceName: !empty(adhsWorkspaceName) ? adhsWorkspaceName : 'ws${environmentName}${resourceToken}'
    fhirServiceName: !empty(fhirServiceName) ? fhirServiceName : 'fs${resourceToken}' 
    location: location
    tags: tags
  }
}

// create a instance of the oss fhir loader 
// the oss-fhir-loader bicep creaes a storage account and a function app
// Currently bicep does not support 'external modules' (https://github.com/Azure/bicep/issues/660),
// so we copied the bicep file (https://raw.githubusercontent.com/microsoft/fhir-loader/main/scripts/fhirBulkImport.bicep) and its dependent bicep files from the github repo and added the to our repo.
module ossFhirLoader 'core/oss-fhir-loader/fhirBulkImport.bicep' = {
  name: 'ossFhirLoader'
  scope: rg
  params: {
    fhirServiceName: '${adhsWorkspaceName}/${fhirServiceName}'
    fhirServiceId: fhirService.outputs.fhirServiceId
  }
}

// assign the azcopy spn to the storage account
module azCopySPNRoleAssignment 'core/storage/storage-access.bicep' = {
  name: 'azCopySPNRoleAssignment'
  scope: rg
  params: {
    storageAccountName: ossFhirLoader.outputs.storageAccountName
    principalId: azCopySpnPrincipalId
    roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  }
}

// Add outputs from the deployment here, if needed.
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output STORAGE_ACCOUNT_NAME string = ossFhirLoader.outputs.storageAccountName
output AZCOPY_AUTO_LOGIN_TYPE string = 'SPN'
output AZCOPY_SPN_OBJECT_ID string = azCopySpnPrincipalId
output AZCOPY_TENANT_ID string = tenant().tenantId
output SYNTHEA_JAR_PATH string = syntheaJarPath
// output AZCOPY_SPA_APPLICATION_ID string = azCopySpnApplicationId
