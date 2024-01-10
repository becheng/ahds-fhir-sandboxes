//Define parameters
param workspaceName string
param fhirServiceName string
param tenantId string = subscription().tenantId
param location string = resourceGroup().location
param fhirVersion string = 'fhir-R4'
param tags object = {}

//Define variables
var adhsFhirServiceName = '${workspaceName}/${fhirServiceName}'
var loginURL = environment().authentication.loginEndpoint
var authority = '${loginURL}${tenantId}'
var audience = 'https://${workspaceName}-${fhirServiceName}.fhir.azurehealthcareapis.com'

//Create an ADHS workspace
resource ahdsWorkspace 'Microsoft.HealthcareApis/workspaces@2022-06-01' = {
  name: workspaceName
  location: location
  tags: tags
}

// create a fhir resource
resource FHIRresource 'Microsoft.HealthcareApis/workspaces/fhirservices@2022-06-01' = {
  name: adhsFhirServiceName
  location: location
  kind: fhirVersion
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  dependsOn: [
    ahdsWorkspace
  ]
  properties: {
    accessPolicies: []
    authenticationConfiguration: {
      authority: authority
      audience: audience
      smartProxyEnabled: false
    }
    corsConfiguration: {
      origins: ['*']
      headers: ['*']
      methods: []
      allowCredentials: false
    }    
  }
}

output fhirServiceId string = FHIRresource.id
