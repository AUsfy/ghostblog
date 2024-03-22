param env string = 'dev'
param region string = 'we'

// web app param
// Generate unique String for web app name
param AppServiceSku string = 'F1' // The SKU of App Service Plan

param location string = resourceGroup().location // Location for all resources

// ACR
param acrSku string = 'Basic'

// DB
param dbTier string = 'Burstable'
param dbSkuName string = 'Standard_B1ms'

@minLength(1)
param administratorLogin string = 'ghostadmin'

@minLength(8)
@secure()
param administratorLoginPassword string 

param mysqlVersion string = '8.0.21'

@description('MySQL Server backup retention days')
param backupRetentionDays int = 7


@description('Provide the availability zone information of the server. (Leave blank for No Preference).')
param availabilityZone string = '1'

@description('Provide the high availability mode for a server : Disabled, SameZone, or ZoneRedundant')
@allowed([
  'Disabled'
  'SameZone'
  'ZoneRedundant'
])
param haEnabled string = 'Disabled'

@description('Provide the availability zone of the standby server.')
param standbyAvailabilityZone string = '2'

param storageSizeGB int = 20
param storageIops int = 360

@allowed([
  'Enabled'
  'Disabled'
])
param storageAutogrow string = 'Enabled'

@allowed([
  'Disabled'
  'Enabled'
])
param geoRedundantBackup string = 'Disabled'

var uniqueId = uniqueString(resourceGroup().id)
var appServicePlanName = 'ghost-asp-${env}-${region}-AppServicePlan-${uniqueId}'
var webSiteName = 'ghost-app-${env}-${region}-${uniqueId}'

var acrName = 'ghostacr${env}${region}'
var dbServerName = 'ghost-db-${env}-${region}-${uniqueId}'

var keyVaultName = 'ghost-${env}-${region}-kv'

var applicationInsightsName = 'ghost-${env}-${region}-ai'

var defaultTags = {
  Environment: env
  Region: region
}


resource kvUserSecretsRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '4633458b-17de-408a-b874-0445c86b69e6'
}

// role assignment will be applied on the ressource group level
resource kvRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, appService.name, kvUserSecretsRoleDefinition.id)
  properties: {
    roleDefinitionId: kvUserSecretsRoleDefinition.id
    principalId: appService.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource keyvault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  
  properties:{
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    accessPolicies: []
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls:{
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }

  tags: defaultTags
}

resource secret1 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyvault
  name: 'mysqlAdminLoginPassword'
  properties: {
    value: administratorLoginPassword
  }
}

resource secret2 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyvault
  name: 'mysqlAdminUserName'
  properties: {
    value: administratorLogin
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  properties: {
    reserved: true
  }
  sku: {
    name: AppServiceSku
  }
  kind: 'linux'

  tags: defaultTags
}

resource appService 'Microsoft.Web/sites@2023-01-01' = {
  name: webSiteName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'DOCKER|${acr.name}.azurecr.io/ghost:latest' //'node|14-lts' // The runtime stack of web app
      acrUseManagedIdentityCreds: false
      keyVaultReferenceIdentity: 'SystemAssigned'
      appSettings: [
        {
          name: 'url'
          value: 'https://${webSiteName}.azurewebsites.net/' 
        }
        {
          name: 'database__connection__user'
          value: administratorLogin
        }
        {
          name: 'database__connection__password'
          value: '@Microsoft.KeyVault(SecretUri=${secret1.properties.secretUri})' //administratorLoginPassword
        }
        {
          name: 'WEBSITES_PORT'
          value: '2368'
        }
        {
          name: 'database__connection__database'
          value: 'ghost'
        }
        {
          name: 'database__client'
          value: 'mysql'
        }
        {
          name: 'database__connection__host'
          value: '${ghostDbServer.name}.mysql.database.azure.com'
        }
        {
          name: 'database__connection__ssl'
          value: '{"rejectUnauthorized": "true", "secureProtocol": "TLSv1_2_method"}'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: '${acr.name}.azurecr.io'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_PASSWORD'
          value: acr.listCredentials().passwords[0].value
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_USERNAME'
          value: acr.name
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.outputs.appInsightsInstrumentationKey
        }
        
      ]
    }
  }
  identity:{
    type: 'SystemAssigned'
  }
  tags: defaultTags
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: true
  }
  tags: defaultTags
}

resource ghostDbServer 'Microsoft.DBforMySQL/flexibleServers@2023-06-30' = {
  name: dbServerName
  location: location
  sku: {
    name: dbSkuName
    tier: dbTier
  }
    properties: {
      version: mysqlVersion
      administratorLogin: administratorLogin
      administratorLoginPassword: administratorLoginPassword
      availabilityZone: availabilityZone
      highAvailability: {
        mode: haEnabled
        standbyAvailabilityZone: standbyAvailabilityZone
      }
      storage: {
        storageSizeGB: storageSizeGB
        iops: storageIops
        autoGrow: storageAutogrow
      }
      backup: {
        backupRetentionDays: backupRetentionDays
        geoRedundantBackup: geoRedundantBackup
      }
  }
  tags: defaultTags
}

resource firewallRules 'Microsoft.DBforMySQL/flexibleServers/firewallRules@2023-06-30' = {
  name: '${dbServerName}-rule1'
  parent: ghostDbServer
  properties: {
    endIpAddress: '0.0.0.0'
    startIpAddress: '0.0.0.0'
  }
}


module applicationInsights 'modules/application_insights_module.bicep' = {
  name: applicationInsightsName
  params: {
    applicationInsightsName: applicationInsightsName
    location: location
    tags: defaultTags
  }
}


  
